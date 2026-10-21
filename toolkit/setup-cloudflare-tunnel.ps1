<#
.SYNOPSIS
    setup-cloudflare-tunnel.ps1 - إعداد وربط نفق Cloudflare لدومين Employee.nociraq.com
.DESCRIPTION
    يربط الخادم المحلي بالدومين الخارجي Employee.nociraq.com بدون فتح منافذ في الراوتر
#>

param(
    [string]$Domain     = "Employee.nociraq.com",
    [string]$TunnelName = "noci-attendance-tunnel",
    [int]$LocalPort     = 5000
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "NOCI Attendance - Cloudflare Tunnel Setup"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🏛️ إعداد نفق Cloudflare للدومين: https://$Domain" -ForegroundColor Cyan
Write-Host "  المنفذ المحلي: http://localhost:$LocalPort" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. فحص برنامج cloudflared
Write-Host "`n[1/4] فحص أداة cloudflared..." -ForegroundColor Green
$cfCmd = Get-Command cloudflared -ErrorAction SilentlyContinue

if (-not $cfCmd) {
    Write-Host "  - تحميل وتثبيت cloudflared..." -ForegroundColor Yellow
    $msi = "$env:TEMP\cloudflared.msi"
    Invoke-WebRequest -UseBasicParsing -OutFile $msi -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.msi"
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn" -Wait
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
}
Write-Host "✔ أداة cloudflared جاهزة: $(cloudflared --version)" -ForegroundColor Green

# 2. فحص تسجيل الدخول
$userCfDir = "$env:USERPROFILE\.cloudflared"
$certPath  = "$userCfDir\cert.pem"

if (-not (Test-Path $certPath)) {
    Write-Host "`n[2/4] تفويض الدومين مع Cloudflare..." -ForegroundColor Yellow
    Write-Host "سيفتح المتصفح لتسجيل الدخول إلى حساب Cloudflare واختيار دومين nociraq.com:" -ForegroundColor Cyan
    cloudflared tunnel login
}

# 3. إنشاء أو التحقق من النفق
Write-Host "`n[3/4] تهيئة النفق ($TunnelName)..." -ForegroundColor Green
$existingTunnel = cloudflared tunnel list | Select-String $TunnelName

if (-not $existingTunnel) {
    cloudflared tunnel create $TunnelName
}

# استخراج المعرف UUID
$id = (Get-ChildItem "$userCfDir\*.json" -ErrorAction SilentlyContinue | Where-Object BaseName -match '^[0-9a-f-]{36}$' | Select-Object -First 1).BaseName
Write-Host "معرف النفق (Tunnel ID): $id" -ForegroundColor Cyan

# 4. كتابة ملف التوجيه config.yml
$configContent = @"
tunnel: $id
credentials-file: $userCfDir\$id.json

ingress:
  - hostname: $Domain
    service: http://localhost:$LocalPort

  - service: http_status:404
"@

$configContent | Out-File -FilePath "$userCfDir\config-attendance.yml" -Encoding ascii -Force

Write-Host "`n[4/4] ربط الـ DNS وتشغيل النفق..." -ForegroundColor Green
cloudflared tunnel route dns -f $TunnelName $Domain

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✔ تم إعداد النفق بنجاح!" -ForegroundColor Green
Write-Host "لتشغيل النفق، نفّذ الأمر التالي:" -ForegroundColor Cyan
Write-Host "cloudflared tunnel --config `"$userCfDir\config-attendance.yml`" run $TunnelName" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Green
