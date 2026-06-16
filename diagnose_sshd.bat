@echo off
chcp 65001 >nul

:: 自动提权
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo 正在采集诊断信息...

powershell -Command ^
 "$diag = @(); " ^
 "$diag += '=== SSHD SERVICE STATUS ==='; " ^
 "$diag += (Get-Service sshd | Format-List * | Out-String); " ^
 "" ^
 "$diag += '=== SSHD CONFIG ==='; " ^
 "if (Test-Path 'C:\ProgramData\ssh\sshd_config') { $diag += (Get-Content 'C:\ProgramData\ssh\sshd_config' -Raw) } else { $diag += 'FILE NOT FOUND' }; " ^
 "" ^
 "$diag += '=== HOST KEYS ==='; " ^
 "$diag += (Get-ChildItem 'C:\ProgramData\ssh\ssh_host_*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name + ' - ' + $_.Length + ' bytes' } | Out-String); " ^
 "" ^
 "$diag += '=== HOST KEY PERMISSIONS ==='; " ^
 "$diag += (icacls 'C:\ProgramData\ssh\ssh_host_ed25519_key' 2>&1 | Out-String); " ^
 "" ^
 "$diag += '=== ADMIN AUTH KEYS ==='; " ^
 "if (Test-Path 'C:\ProgramData\ssh\administrators_authorized_keys') { " ^
 "  $diag += 'EXISTS - ' + (Get-Item 'C:\ProgramData\ssh\administrators_authorized_keys').Length + ' bytes'; " ^
 "  $diag += (icacls 'C:\ProgramData\ssh\administrators_authorized_keys' 2>&1 | Out-String); " ^
 "  $bytes = [System.IO.File]::ReadAllBytes('C:\ProgramData\ssh\administrators_authorized_keys'); " ^
 "  $diag += 'First 10 bytes: ' + (($bytes[0..9] | ForEach-Object { $_.ToString('X2') }) -join ' '); " ^
 "} else { $diag += 'FILE NOT FOUND' }; " ^
 "" ^
 "$diag += '=== SSHD DEBUG (5 sec) ==='; " ^
 "net stop sshd 2>$null; " ^
 "Start-Sleep 1; " ^
 "$p = Start-Process -FilePath 'C:\Windows\System32\OpenSSH\sshd.exe' -ArgumentList '-d','-p','22' -NoNewWindow -PassThru -RedirectStandardOutput 'C:\frp\sshd_debug_out.txt' -RedirectStandardError 'C:\frp\sshd_debug_err.txt'; " ^
 "Start-Sleep 5; " ^
 "if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }; " ^
 "if (Test-Path 'C:\frp\sshd_debug_err.txt') { $diag += (Get-Content 'C:\frp\sshd_debug_err.txt' -Raw) }; " ^
 "if (Test-Path 'C:\frp\sshd_debug_out.txt') { $diag += (Get-Content 'C:\frp\sshd_debug_out.txt' -Raw) }; " ^
 "" ^
 "$diag += '=== OPENSSH VERSION ==='; " ^
 "$diag += (& 'C:\Windows\System32\OpenSSH\sshd.exe' -V 2>&1 | Out-String); " ^
 "$diag += (& 'C:\Windows\System32\OpenSSH\ssh.exe' -V 2>&1 | Out-String); " ^
 "" ^
 "$diag += '=== SSHD_CONFIG PERMISSIONS ==='; " ^
 "$diag += (icacls 'C:\ProgramData\ssh\sshd_config' 2>&1 | Out-String); " ^
 "" ^
 "$diag += '=== WINDOWS USER INFO ==='; " ^
 "$diag += (whoami | Out-String); " ^
 "$diag += (net user Administrator 2>&1 | Out-String); " ^
 "" ^
 "net start sshd 2>$null; " ^
 "" ^
 "$body = ($diag -join \"`n\"); " ^
 "try { " ^
 "  Invoke-WebRequest -Uri 'http://121.40.92.132:9999' -Method POST -Body $body -TimeoutSec 10 -UseBasicParsing | Out-Null; " ^
 "  Write-Host '诊断信息已发送！请通知 Mac 端查看。'; " ^
 "} catch { " ^
 "  Write-Host '发送失败，保存到本地 C:\frp\diag.txt'; " ^
 "  $body | Out-File 'C:\frp\diag.txt' -Encoding UTF8; " ^
 "}"

echo.
echo 完成！按任意键关闭。
pause >nul
