@echo off
chcp 65001 >nul

:: 自动提权
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo.
echo  =============================================
echo    彻底重装 OpenSSH + FRP  请勿关闭窗口
echo  =============================================
echo.

:: ========== 第一步：彻底卸载 OpenSSH Server ==========
echo [1/7] 卸载旧的 OpenSSH Server...
net stop sshd >nul 2>&1
sc delete sshd >nul 2>&1
powershell -Command "Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue" >nul 2>&1

:: 删除旧配置
rd /s /q "C:\ProgramData\ssh" 2>nul
echo      完成

:: ========== 第二步：重新安装 OpenSSH Server ==========
echo [2/7] 重新安装 OpenSSH Server...
powershell -Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0" >nul 2>&1
echo      完成

:: ========== 第三步：写最简配置 ==========
echo [3/7] 写入配置...
timeout /t 2 /nobreak >nul

:: 等待安装完成生成默认配置
if not exist "C:\ProgramData\ssh" mkdir "C:\ProgramData\ssh" >nul 2>&1

:: 极简 sshd_config，不用 Match Group（这是导致连接断开的元凶）
(
echo Port 22
echo PubkeyAuthentication yes
echo PasswordAuthentication yes
echo Subsystem sftp sftp-server.exe
) > "C:\ProgramData\ssh\sshd_config"

echo      完成

:: ========== 第四步：生成主机密钥 ==========
echo [4/7] 生成主机密钥...
if exist "C:\Windows\System32\OpenSSH\ssh-keygen.exe" (
    "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -A >nul 2>&1
) else (
    ssh-keygen -A >nul 2>&1
)

:: 修复所有主机密钥权限（Windows OpenSSH 对权限极其严格）
powershell -Command ^
 "Get-ChildItem 'C:\ProgramData\ssh\ssh_host_*_key' -ErrorAction SilentlyContinue | ForEach-Object { " ^
 "  icacls $_.FullName /inheritance:r /grant 'SYSTEM:(R)' /grant 'Administrators:(R)' | Out-Null " ^
 "}"
echo      完成

:: ========== 第五步：配置公钥认证 ==========
echo [5/7] 配置公钥免密登录...

:: 因为没有 Match Group administrators，密钥放在用户目录
set SSH_DIR=C:\Users\Administrator\.ssh
if not exist "%SSH_DIR%" mkdir "%SSH_DIR%"

:: 用 PowerShell 写入（确保无 BOM、UTF-8、LF 换行）
powershell -Command ^
 "$key = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDRXdFfXYu2Xb6dkQoXv+A1w9bMpKN8dle6ENX3GvGvwocVxAKQZekeNFBu2SQtXo/2sakl3/jLCkKS+U6ZYUbAwx1u53/QMVKxVNFRKyEkDwXCYlzF8aQYtCMYCMCgILhoMjwsvwnmLIHRNEM5ibT34pImKc4wm39mgO3NIFJyWfTU7yU0f12ebQGFHIRBT73vQlpm7GPvT44W7XbZVny8Al+W2VagDBlsrrHeI1hhUYtsYHVWlUDJwXL+u4VZ8WRYK1kAQM/HnzzvsM0HSThA0r/hzcsjiO+HvoHYXWgyOPpmxHB8pmUsZzzGGKPmVUBV+uRtTbqM+MxFS+JD+xVSXT/+kuRZZD9F4a/qswx5QL/8beNGiKn7TLLZvb4Bcg8592HYMLcuILCPQFtnobgxW8xiMsK9xPeL/iHlxIg3pUYaxXF2u0Oh/i5Wg0MuoPihF9mGim11KOkvS1NUmU8d64DDqFXhi4gyfc5rTdkEkWTtjNCjdHp+mv0beuBP3mLx9fZGE77L+R/XrrgKqm+dq0WDJOME3WkFxyvAYcTFg+yJKjgZR8xM2EFv1Ui6yy0lKeGznZQIFaewv46He5Vbim/QGNTCH78N1x6GZOjnwCladKpuDUVMXNHCdItKuJyAFvjx+9R4oFeC1VDJ/SKUTrwzqEsYuv4B8o0epvc6xw== taohe.hjx@taobao.com'; " ^
 "[System.IO.File]::WriteAllText('C:\Users\Administrator\.ssh\authorized_keys', $key + \"`n\", (New-Object System.Text.UTF8Encoding($false)))"

:: 修复 .ssh 目录和 authorized_keys 权限
icacls "%SSH_DIR%" /inheritance:r /grant "Administrator:F" /grant "SYSTEM:F" >nul 2>&1
icacls "%SSH_DIR%\authorized_keys" /inheritance:r /grant "Administrator:F" /grant "SYSTEM:F" >nul 2>&1

:: 删除旧的 administrators_authorized_keys（避免干扰）
del "C:\ProgramData\ssh\administrators_authorized_keys" 2>nul

:: 修复 sshd_config 权限
icacls "C:\ProgramData\ssh\sshd_config" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" >nul 2>&1

echo      完成

:: ========== 第六步：启动 sshd ==========
echo [6/7] 启动 sshd...
sc config sshd start=auto >nul 2>&1
net start sshd >nul 2>&1

timeout /t 2 /nobreak >nul

:: 验证 sshd 是否在运行
sc query sshd | find "RUNNING" >nul
if %errorlevel% equ 0 (
    echo      sshd 运行中
) else (
    echo      sshd 启动失败，尝试修复...
    :: 可能是默认 sshd_config 路径问题，试试直接启动
    powershell -Command "Start-Service sshd -ErrorAction SilentlyContinue"
    timeout /t 2 /nobreak >nul
    sc query sshd | find "RUNNING" >nul
    if %errorlevel% equ 0 (
        echo      sshd 已修复并运行
    ) else (
        echo      sshd 无法启动，请检查 Windows 事件查看器
    )
)

:: 验证 22 端口
powershell -Command "try { $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 22); if($c.Connected) { Write-Host '      本地 SSH 端口正常'; $c.Close() } } catch { Write-Host '      本地 SSH 端口异常' }"

:: ========== 第七步：确保 FRP 在运行 ==========
echo [7/7] 检查 FRP...
taskkill /F /IM frpc.exe >nul 2>&1
timeout /t 1 /nobreak >nul

:: 确保 FRP 配置存在
if not exist "C:\frp" mkdir "C:\frp"
(
echo serverAddr = "121.40.92.132"
echo serverPort = 7000
echo auth.method = "token"
echo auth.token = "frp_mac2win_f3c91dd0dfeae8bba4a08ae2d7d03791"
echo.
echo [[proxies]]
echo name = "windows-ssh"
echo type = "tcp"
echo localIP = "127.0.0.1"
echo localPort = 22
echo remotePort = 6022
) > "C:\frp\frpc.toml"

:: 创建 VBS 后台启动器
(
echo Set ws = CreateObject^("Wscript.Shell"^)
echo ws.Run "C:\frp\frpc.exe -c C:\frp\frpc.toml", 0, False
) > "C:\frp\start_frpc.vbs"

:: 启动 FRP
wscript.exe "C:\frp\start_frpc.vbs"
timeout /t 3 /nobreak >nul

tasklist /FI "IMAGENAME eq frpc.exe" 2>nul | find "frpc.exe" >nul
if %errorlevel% equ 0 (
    echo      FRP 运行中
) else (
    echo      FRP 启动失败
)

:: 注册开机自启
schtasks /delete /tn "FRP Client" /f >nul 2>&1
schtasks /create /tn "FRP Client" /tr "wscript.exe C:\frp\start_frpc.vbs" /sc onstart /ru SYSTEM /rl HIGHEST /f >nul 2>&1

echo.
echo  =============================================
echo    全部完成！告诉 Mac 端可以测试了
echo  =============================================
echo.
pause >nul
