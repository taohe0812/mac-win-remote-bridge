@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo  Step 1: 安装并启动 OpenSSH Server
echo ========================================

:: 检查是否以管理员身份运行
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 请右键点击此脚本，选择"以管理员身份运行"
    pause
    exit /b 1
)

:: 安装 OpenSSH Server
echo 正在安装 OpenSSH Server...
dism /Online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 /NoRestart
if %errorlevel% neq 0 (
    echo OpenSSH Server 可能已安装，继续...
)

:: 启动 sshd 服务并设为自动启动
echo 启动 sshd 服务...
sc start sshd >nul 2>&1
sc config sshd start=auto >nul 2>&1
echo sshd 服务已启动并设为开机自启

:: 设置默认 Shell 为 PowerShell（cmd 通过 SSH 执行有兼容性问题）
reg add "HKLM\SOFTWARE\OpenSSH" /v DefaultShell /t REG_SZ /d "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" /f >nul 2>&1
echo 默认 Shell 已设为 PowerShell

:: 配置防火墙规则
netsh advfirewall firewall show rule name="OpenSSH-Server-In-TCP" >nul 2>&1
if %errorlevel% neq 0 (
    netsh advfirewall firewall add rule name="OpenSSH-Server-In-TCP" dir=in action=allow protocol=TCP localport=22
    echo 防火墙规则已添加
) else (
    echo 防火墙规则已存在
)

echo.
echo ========================================
echo  Step 2: 安装 FRP Client
echo ========================================

set FRP_DIR=C:\frp
set FRP_VERSION=0.61.1

if exist "%FRP_DIR%\frpc.exe" (
    echo FRP Client 已存在于 %FRP_DIR%
    goto write_config
)

echo 正在下载 FRP v%FRP_VERSION%...
if not exist "%FRP_DIR%" mkdir "%FRP_DIR%"

:: 尝试镜像下载
curl -L --connect-timeout 15 -o "%TEMP%\frp.zip" "https://ghfast.top/https://github.com/fatedier/frp/releases/download/v%FRP_VERSION%/frp_%FRP_VERSION%_windows_amd64.zip" 2>nul
if %errorlevel% neq 0 (
    echo 镜像下载失败，尝试 GitHub 直连...
    curl -L --connect-timeout 30 -o "%TEMP%\frp.zip" "https://github.com/fatedier/frp/releases/download/v%FRP_VERSION%/frp_%FRP_VERSION%_windows_amd64.zip"
)

if not exist "%TEMP%\frp.zip" (
    echo [错误] 下载失败，请手动下载 FRP 并放到 C:\frp\frpc.exe
    pause
    exit /b 1
)

:: 解压（Win10 自带 tar 命令）
echo 正在解压...
tar -xf "%TEMP%\frp.zip" -C "%TEMP%" 2>nul
if %errorlevel% neq 0 (
    :: 备用方案：用 PowerShell 解压
    powershell -Command "Expand-Archive -Path '%TEMP%\frp.zip' -DestinationPath '%TEMP%\frp_extract' -Force"
    copy "%TEMP%\frp_extract\frp_%FRP_VERSION%_windows_amd64\frpc.exe" "%FRP_DIR%\frpc.exe" >nul
    rd /s /q "%TEMP%\frp_extract" 2>nul
) else (
    copy "%TEMP%\frp_%FRP_VERSION%_windows_amd64\frpc.exe" "%FRP_DIR%\frpc.exe" >nul
    rd /s /q "%TEMP%\frp_%FRP_VERSION%_windows_amd64" 2>nul
)
del "%TEMP%\frp.zip" 2>nul
echo FRP Client 已安装到 %FRP_DIR%

:write_config
:: 写入配置文件
echo 写入 FRP 配置...
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
echo 配置文件已写入 %FRP_DIR%\frpc.toml

echo.
echo ========================================
echo  Step 3: 注册 FRP Client 为 Windows 服务
echo ========================================

:: 停止并删除旧服务
sc stop frpc >nul 2>&1
sc delete frpc >nul 2>&1
timeout /t 2 /nobreak >nul

:: 创建新服务
sc create frpc binPath= "%FRP_DIR%\frpc.exe -c %FRP_DIR%\frpc.toml" start= auto DisplayName= "FRP Client" >nul
sc description frpc "FRP Client - Reverse proxy to ECS" >nul

:: 先手动测试连接
echo 测试 FRP 连接（等待 5 秒）...
start /b "" "%FRP_DIR%\frpc.exe" -c "%FRP_DIR%\frpc.toml" > "%TEMP%\frpc_test.log" 2>&1
timeout /t 5 /nobreak >nul

:: 检查进程是否还在运行
tasklist /FI "IMAGENAME eq frpc.exe" 2>nul | find "frpc.exe" >nul
if %errorlevel% equ 0 (
    echo FRP 连接成功！
    taskkill /F /IM frpc.exe >nul 2>&1
    timeout /t 2 /nobreak >nul
    sc start frpc >nul
    echo FRP 服务已启动
) else (
    echo [警告] FRP 连接可能失败，请检查 ECS 安全组是否开放 7000 端口
    echo 日志: %TEMP%\frpc_test.log
)

echo.
echo ========================================
echo  Step 4: 配置免密登录
echo ========================================

set SSH_DIR=C:\ProgramData\ssh
set AUTH_KEYS=%SSH_DIR%\administrators_authorized_keys

:: 写入 Mac 公钥
echo ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDRXdFfXYu2Xb6dkQoXv+A1w9bMpKN8dle6ENX3GvGvwocVxAKQZekeNFBu2SQtXo/2sakl3/jLCkKS+U6ZYUbAwx1u53/QMVKxVNFRKyEkDwXCYlzF8aQYtCMYCMCgILhoMjwsvwnmLIHRNEM5ibT34pImKc4wm39mgO3NIFJyWfTU7yU0f12ebQGFHIRBT73vQlpm7GPvT44W7XbZVny8Al+W2VagDBlsrrHeI1hhUYtsYHVWlUDJwXL+u4VZ8WRYK1kAQM/HnzzvsM0HSThA0r/hzcsjiO+HvoHYXWgyOPpmxHB8pmUsZzzGGKPmVUBV+uRtTbqM+MxFS+JD+xVSXT/+kuRZZD9F4a/qswx5QL/8beNGiKn7TLLZvb4Bcg8592HYMLcuILCPQFtnobgxW8xiMsK9xPeL/iHlxIg3pUYaxXF2u0Oh/i5Wg0MuoPihF9mGim11KOkvS1NUmU8d64DDqFXhi4gyfc5rTdkEkWTtjNCjdHp+mv0beuBP3mLx9fZGE77L+R/XrrgKqm+dq0WDJOME3WkFxyvAYcTFg+yJKjgZR8xM2EFv1Ui6yy0lKeGznZQIFaewv46He5Vbim/QGNTCH78N1x6GZOjnwCladKpuDUVMXNHCdItKuJyAFvjx+9R4oFeC1VDJ/SKUTrwzqEsYuv4B8o0epvc6xw== taohe.hjx@taobao.com> "%AUTH_KEYS%"

:: 修复权限 - 只允许 Administrators 和 SYSTEM 访问
icacls "%AUTH_KEYS%" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" >nul
echo Mac 公钥已配置

echo.
echo ========================================
echo  全部完成！
echo ========================================
echo.
echo 从 Mac 终端执行以下命令测试:
echo   ssh -p 6022 Administrator@121.40.92.132
echo.
echo 或者如果已配置 SSH alias:
echo   ssh windev "hostname"
echo.
pause
