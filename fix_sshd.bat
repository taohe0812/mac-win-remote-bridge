@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: 自动提权
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo.
echo  =============================================
echo    OpenSSH 修复脚本
echo  =============================================
echo.

:: 1. 停止 sshd
echo [1/6] 停止 sshd...
net stop sshd >nul 2>&1

:: 2. 修复 DefaultShell（确保路径正确）
echo [2/6] 修复 DefaultShell...
if exist "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" (
    reg add "HKLM\SOFTWARE\OpenSSH" /v DefaultShell /t REG_SZ /d "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" /f >nul 2>&1
) else (
    reg delete "HKLM\SOFTWARE\OpenSSH" /v DefaultShell /f >nul 2>&1
)

:: 3. 修复 sshd_config
echo [3/6] 修复 sshd_config...
set SSHD_CONFIG=C:\ProgramData\ssh\sshd_config

:: 备份原配置
if exist "%SSHD_CONFIG%" (
    copy "%SSHD_CONFIG%" "%SSHD_CONFIG%.bak" >nul 2>&1
)

:: 写一份干净的 sshd_config
(
echo # OpenSSH Server Configuration
echo Port 22
echo ListenAddress 0.0.0.0
echo.
echo # Authentication
echo PubkeyAuthentication yes
echo PasswordAuthentication yes
echo PermitEmptyPasswords no
echo.
echo # Logging
echo SyslogFacility LOCAL0
echo LogLevel INFO
echo.
echo # Override default of no subsystems
echo Subsystem sftp sftp-server.exe
echo.
echo # Admin users use administrators_authorized_keys
echo Match Group administrators
echo        AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
) > "%SSHD_CONFIG%"

:: 4. 修复 authorized_keys 文件（确保无 BOM、权限正确）
echo [4/6] 修复 authorized_keys...
set AUTH_KEYS=C:\ProgramData\ssh\administrators_authorized_keys

:: 用 PowerShell 写入确保无 BOM
powershell -Command "[System.IO.File]::WriteAllText('%AUTH_KEYS%', 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDRXdFfXYu2Xb6dkQoXv+A1w9bMpKN8dle6ENX3GvGvwocVxAKQZekeNFBu2SQtXo/2sakl3/jLCkKS+U6ZYUbAwx1u53/QMVKxVNFRKyEkDwXCYlzF8aQYtCMYCMCgILhoMjwsvwnmLIHRNEM5ibT34pImKc4wm39mgO3NIFJyWfTU7yU0f12ebQGFHIRBT73vQlpm7GPvT44W7XbZVny8Al+W2VagDBlsrrHeI1hhUYtsYHVWlUDJwXL+u4VZ8WRYK1kAQM/HnzzvsM0HSThA0r/hzcsjiO+HvoHYXWgyOPpmxHB8pmUsZzzGGKPmVUBV+uRtTbqM+MxFS+JD+xVSXT/+kuRZZD9F4a/qswx5QL/8beNGiKn7TLLZvb4Bcg8592HYMLcuILCPQFtnobgxW8xiMsK9xPeL/iHlxIg3pUYaxXF2u0Oh/i5Wg0MuoPihF9mGim11KOkvS1NUmU8d64DDqFXhi4gyfc5rTdkEkWTtjNCjdHp+mv0beuBP3mLx9fZGE77L+R/XrrgKqm+dq0WDJOME3WkFxyvAYcTFg+yJKjgZR8xM2EFv1Ui6yy0lKeGznZQIFaewv46He5Vbim/QGNTCH78N1x6GZOjnwCladKpuDUVMXNHCdItKuJyAFvjx+9R4oFeC1VDJ/SKUTrwzqEsYuv4B8o0epvc6xw== taohe.hjx@taobao.com' + [char]10, [System.Text.Encoding]::UTF8)"

:: 修复权限
icacls "%AUTH_KEYS%" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" >nul 2>&1
icacls "%SSHD_CONFIG%" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" >nul 2>&1

:: 5. 启动 sshd
echo [5/6] 启动 sshd...
net start sshd >nul 2>&1
if %errorlevel% neq 0 (
    echo      sshd 启动失败，尝试重新安装...
    dism /Online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 /NoRestart >nul 2>&1
    sc config sshd start=auto >nul 2>&1
    net start sshd >nul 2>&1
)

:: 6. 本地验证
echo [6/6] 本地验证...
timeout /t 2 /nobreak >nul

powershell -Command "try { $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 22); if($c.Connected) { Write-Host '      本地 22 端口正常'; $c.Close() } } catch { Write-Host '      本地 22 端口不通' }"

:: 同时确保 frpc 在运行
tasklist /FI "IMAGENAME eq frpc.exe" 2>nul | find "frpc.exe" >nul
if %errorlevel% neq 0 (
    echo      FRP Client 未运行，正在启动...
    if exist "C:\frp\start_frpc.vbs" (
        wscript.exe "C:\frp\start_frpc.vbs"
    ) else if exist "C:\frp\frpc.exe" (
        start "" /B "C:\frp\frpc.exe" -c "C:\frp\frpc.toml"
    )
    timeout /t 3 /nobreak >nul
)

tasklist /FI "IMAGENAME eq frpc.exe" 2>nul | find "frpc.exe" >nul
if %errorlevel% equ 0 (
    echo      FRP Client 运行中
) else (
    echo      FRP Client 未运行，请检查
)

echo.
echo  =============================================
echo    修复完成！请通知 Mac 端再次测试
echo  =============================================
echo.
pause >nul
