# ============================================
# Windows FRP Client + OpenSSH Server 一键安装脚本
# 请以管理员身份运行 PowerShell 执行此脚本
# ============================================

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Step 1: 安装并启动 OpenSSH Server" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 检查 OpenSSH Server 是否已安装
$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshCapability.State -ne 'Installed') {
    Write-Host "正在安装 OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Write-Host "OpenSSH Server 安装完成" -ForegroundColor Green
} else {
    Write-Host "OpenSSH Server 已安装" -ForegroundColor Green
}

# 启动 sshd 并设置为自动启动
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
Write-Host "sshd 服务已启动并设为开机自启" -ForegroundColor Green

# 设置默认 Shell 为 PowerShell
$psPath = (Get-Command powershell.exe).Source
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value $psPath -PropertyType String -Force | Out-Null
Write-Host "默认 Shell 已设为 PowerShell" -ForegroundColor Green

# 配置防火墙规则
$firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $firewallRule) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    Write-Host "防火墙规则已添加" -ForegroundColor Green
} else {
    Write-Host "防火墙规则已存在" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Step 2: 安装 FRP Client" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$frpDir = "C:\frp"
$frpVersion = "0.61.1"
$frpZip = "$env:TEMP\frp.zip"
$frpUrl = "https://github.com/fatedier/frp/releases/download/v${frpVersion}/frp_${frpVersion}_windows_amd64.zip"
$frpMirrorUrl = "https://ghfast.top/$frpUrl"

if (-not (Test-Path "$frpDir\frpc.exe")) {
    Write-Host "正在下载 FRP v${frpVersion}..." -ForegroundColor Yellow
    
    try {
        Invoke-WebRequest -Uri $frpMirrorUrl -OutFile $frpZip -TimeoutSec 30
    } catch {
        Write-Host "镜像下载失败，尝试 GitHub 直连..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $frpUrl -OutFile $frpZip -TimeoutSec 60
    }
    
    if (-not (Test-Path $frpDir)) { New-Item -ItemType Directory -Path $frpDir | Out-Null }
    Expand-Archive -Path $frpZip -DestinationPath "$env:TEMP\frp_extract" -Force
    Copy-Item "$env:TEMP\frp_extract\frp_${frpVersion}_windows_amd64\frpc.exe" "$frpDir\frpc.exe"
    Remove-Item $frpZip -Force
    Remove-Item "$env:TEMP\frp_extract" -Recurse -Force
    Write-Host "FRP Client 安装到 $frpDir" -ForegroundColor Green
} else {
    Write-Host "FRP Client 已存在于 $frpDir" -ForegroundColor Green
}

# 写入配置文件
$frpcConfig = @"
serverAddr = "121.40.92.132"
serverPort = 7000
auth.method = "token"
auth.token = "frp_mac2win_f3c91dd0dfeae8bba4a08ae2d7d03791"

[[proxies]]
name = "windows-ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6022
"@

Set-Content -Path "$frpDir\frpc.toml" -Value $frpcConfig -Encoding UTF8
Write-Host "FRP 配置文件已写入 $frpDir\frpc.toml" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Step 3: 注册 FRP Client 为 Windows 服务" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$serviceName = "frpc"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service) {
    Write-Host "停止旧服务..." -ForegroundColor Yellow
    Stop-Service $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null
    Start-Sleep -Seconds 2
}

sc.exe create $serviceName binPath= "$frpDir\frpc.exe -c $frpDir\frpc.toml" start= auto DisplayName= "FRP Client" | Out-Null
sc.exe description $serviceName "FRP Client - Reverse proxy to ECS" | Out-Null

Write-Host "测试 FRP 连接..." -ForegroundColor Yellow
$process = Start-Process -FilePath "$frpDir\frpc.exe" -ArgumentList "-c", "$frpDir\frpc.toml" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\frpc_test.log" -RedirectStandardError "$env:TEMP\frpc_test_err.log"
Start-Sleep -Seconds 5

if (-not $process.HasExited) {
    Write-Host "FRP 连接成功！" -ForegroundColor Green
    Stop-Process -Id $process.Id -Force
    Start-Sleep -Seconds 2
    
    Start-Service $serviceName
    Write-Host "FRP 服务已启动" -ForegroundColor Green
} else {
    $errLog = Get-Content "$env:TEMP\frpc_test_err.log" -ErrorAction SilentlyContinue
    Write-Host "FRP 连接失败: $errLog" -ForegroundColor Red
    Write-Host "请确保 ECS 安全组已开放 7000 端口" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Step 4: 配置免密登录" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$sshDir = "C:\Users\Administrator\.ssh"
$authKeysFile = "$sshDir\authorized_keys"
$macPubKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDRXdFfXYu2Xb6dkQoXv+A1w9bMpKN8dle6ENX3GvGvwocVxAKQZekeNFBu2SQtXo/2sakl3/jLCkKS+U6ZYUbAwx1u53/QMVKxVNFRKyEkDwXCYlzF8aQYtCMYCMCgILhoMjwsvwnmLIHRNEM5ibT34pImKc4wm39mgO3NIFJyWfTU7yU0f12ebQGFHIRBT73vQlpm7GPvT44W7XbZVny8Al+W2VagDBlsrrHeI1hhUYtsYHVWlUDJwXL+u4VZ8WRYK1kAQM/HnzzvsM0HSThA0r/hzcsjiO+HvoHYXWgyOPpmxHB8pmUsZzzGGKPmVUBV+uRtTbqM+MxFS+JD+xVSXT/+kuRZZD9F4a/qswx5QL/8beNGiKn7TLLZvb4Bcg8592HYMLcuILCPQFtnobgxW8xiMsK9xPeL/iHlxIg3pUYaxXF2u0Oh/i5Wg0MuoPihF9mGim11KOkvS1NUmU8d64DDqFXhi4gyfc5rTdkEkWTtjNCjdHp+mv0beuBP3mLx9fZGE77L+R/XrrgKqm+dq0WDJOME3WkFxyvAYcTFg+yJKjgZR8xM2EFv1Ui6yy0lKeGznZQIFaewv46He5Vbim/QGNTCH78N1x6GZOjnwCladKpuDUVMXNHCdItKuJyAFvjx+9R4oFeC1VDJ/SKUTrwzqEsYuv4B8o0epvc6xw== taohe.hjx@taobao.com"

if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

# 对于 Administrator 用户，需要写入 ProgramData 下的 administrators_authorized_keys
$adminAuthKeys = "C:\ProgramData\ssh\administrators_authorized_keys"
Set-Content -Path $adminAuthKeys -Value $macPubKey -Encoding UTF8

# 修复权限 - 只允许 Administrators 和 SYSTEM 访问
icacls $adminAuthKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null

Write-Host "Mac 公钥已添加到 $adminAuthKeys" -ForegroundColor Green
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " 全部完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "从 Mac 测试: ssh -p 6022 Administrator@121.40.92.132" -ForegroundColor Cyan
