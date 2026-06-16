@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ============================================
:: 双击即可，全自动，无需任何操作
:: ============================================

:: 自动请求管理员权限
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 正在请求管理员权限...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo.
echo  =============================================
echo    Mac-Windows 远程开发桥接 一键安装
echo    全自动运行，请勿关闭此窗口
echo  =============================================
echo.

:: ---------- Step 1: OpenSSH Server ----------
echo [1/5] 安装 OpenSSH Server...
dism /Online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 /NoRestart >nul 2>&1
sc config sshd start=auto >nul 2>&1
net start sshd >nul 2>&1
reg add "HKLM\SOFTWARE\OpenSSH" /v DefaultShell /t REG_SZ /d "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" /f >nul 2>&1
netsh advfirewall firewall add rule name="OpenSSH-Server-In-TCP" dir=in action=allow protocol=TCP localport=22 >nul 2>&1
echo [1/5] OpenSSH Server 完成

:: ---------- Step 2: 下载 FRP ----------
echo [2/5] 下载 FRP Client...
set FRP_DIR=C:\frp
if not exist "%FRP_DIR%" mkdir "%FRP_DIR%"

if not exist "%FRP_DIR%\frpc.exe" (
    curl -L --connect-timeout 15 -s -o "%TEMP%\frp.zip" "https://ghfast.top/https://github.com/fatedier/frp/releases/download/v0.61.1/frp_0.61.1_windows_amd64.zip" 2>nul
    if not exist "%TEMP%\frp.zip" (
        curl -L --connect-timeout 30 -s -o "%TEMP%\frp.zip" "https://github.com/fatedier/frp/releases/download/v0.61.1/frp_0.61.1_windows_amd64.zip"
    )
    tar -xf "%TEMP%\frp.zip" -C "%TEMP%" >nul 2>&1
    if exist "%TEMP%\frp_0.61.1_windows_amd64\frpc.exe" (
        copy "%TEMP%\frp_0.61.1_windows_amd64\frpc.exe" "%FRP_DIR%\frpc.exe" >nul
    ) else (
        powershell -Command "Expand-Archive -Path '%TEMP%\frp.zip' -DestinationPath '%TEMP%\frp_extract' -Force" >nul 2>&1
        copy "%TEMP%\frp_extract\frp_0.61.1_windows_amd64\frpc.exe" "%FRP_DIR%\frpc.exe" >nul
        rd /s /q "%TEMP%\frp_extract" 2>nul
    )
    rd /s /q "%TEMP%\frp_0.61.1_windows_amd64" 2>nul
    del "%TEMP%\frp.zip" 2>nul
)
echo [2/5] FRP Client 完成

:: ---------- Step 3: 写配置 ----------
echo [3/5] 写入配置文件...
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
) > "%FRP_DIR%\frpc.toml"
echo [3/5] 配置文件完成

:: ---------- Step 4: 配置免密登录 ----------
echo [4/5] 配置免密登录...
set AUTH_KEYS=C:\ProgramData\ssh\administrators_authorized_keys
echo ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDRXdFfXYu2Xb6dkQoXv+A1w9bMpKN8dle6ENX3GvGvwocVxAKQZekeNFBu2SQtXo/2sakl3/jLCkKS+U6ZYUbAwx1u53/QMVKxVNFRKyEkDwXCYlzF8aQYtCMYCMCgILhoMjwsvwnmLIHRNEM5ibT34pImKc4wm39mgO3NIFJyWfTU7yU0f12ebQGFHIRBT73vQlpm7GPvT44W7XbZVny8Al+W2VagDBlsrrHeI1hhUYtsYHVWlUDJwXL+u4VZ8WRYK1kAQM/HnzzvsM0HSThA0r/hzcsjiO+HvoHYXWgyOPpmxHB8pmUsZzzGGKPmVUBV+uRtTbqM+MxFS+JD+xVSXT/+kuRZZD9F4a/qswx5QL/8beNGiKn7TLLZvb4Bcg8592HYMLcuILCPQFtnobgxW8xiMsK9xPeL/iHlxIg3pUYaxXF2u0Oh/i5Wg0MuoPihF9mGim11KOkvS1NUmU8d64DDqFXhi4gyfc5rTdkEkWTtjNCjdHp+mv0beuBP3mLx9fZGE77L+R/XrrgKqm+dq0WDJOME3WkFxyvAYcTFg+yJKjgZR8xM2EFv1Ui6yy0lKeGznZQIFaewv46He5Vbim/QGNTCH78N1x6GZOjnwCladKpuDUVMXNHCdItKuJyAFvjx+9R4oFeC1VDJ/SKUTrwzqEsYuv4B8o0epvc6xw== taohe.hjx@taobao.com> "%AUTH_KEYS%"
icacls "%AUTH_KEYS%" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" >nul 2>&1
echo [4/5] 免密登录完成

:: ---------- Step 5: 启动 FRP 并保持后台运行 ----------
echo [5/5] 启动 FRP Client...

:: 杀掉残留进程
taskkill /F /IM frpc.exe >nul 2>&1

:: 清理旧的服务和计划任务
sc stop frpc >nul 2>&1
sc delete frpc >nul 2>&1
schtasks /delete /tn "FRP Client" /f >nul 2>&1

:: 创建 VBS 启动器（让 frpc 以隐藏窗口后台运行，不会被系统回收）
(
echo Set ws = CreateObject^("Wscript.Shell"^)
echo ws.Run "C:\frp\frpc.exe -c C:\frp\frpc.toml", 0, False
) > "%FRP_DIR%\start_frpc.vbs"

:: 注册开机自启计划任务
schtasks /create /tn "FRP Client" /tr "wscript.exe C:\frp\start_frpc.vbs" /sc onstart /ru SYSTEM /rl HIGHEST /f >nul 2>&1

:: 立即启动
wscript.exe "%FRP_DIR%\start_frpc.vbs"

:: 等待 3 秒验证
timeout /t 3 /nobreak >nul
tasklist /FI "IMAGENAME eq frpc.exe" 2>nul | find "frpc.exe" >nul
if %errorlevel% equ 0 (
    echo [5/5] FRP Client 启动成功
    echo.
    echo  =============================================
    echo    全部完成！
    echo    FRP 已在后台运行，开机自动启动
    echo    现在可以从 Mac 连接此电脑了
    echo  =============================================
) else (
    echo [5/5] FRP Client 启动失败，正在重试...
    start "" /B "%FRP_DIR%\frpc.exe" -c "%FRP_DIR%\frpc.toml"
    timeout /t 3 /nobreak >nul
    tasklist /FI "IMAGENAME eq frpc.exe" 2>nul | find "frpc.exe" >nul
    if %errorlevel% equ 0 (
        echo      重试成功！
        echo.
        echo  =============================================
        echo    全部完成！
        echo  =============================================
    ) else (
        echo      启动失败，请检查网络连接
    )
)

echo.
echo  按任意键关闭此窗口（不影响后台运行）
pause >nul
