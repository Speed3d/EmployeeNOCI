<#
.SYNOPSIS
    05-server-tunnel.ps1 - يُشغَّل على [ 🖥️ الخادم ].
.DESCRIPTION
    يربط https://employee.nociraq.com بالخادم المحلي عبر Cloudflare Tunnel، دون IP ثابت ودون فتح منافذ.
    1. يثبّت cloudflared (winget، أو MSI بعد التحقق من توقيع Cloudflare).
    2. تسجيل الدخول لحساب Cloudflare (مرة واحدة: يفتح المتصفح وتختار nociraq.com).
    3. ينشئ النفق أو يعيد إنشاء ملف اعتماده إذا نُقل لحاسبة جديدة.
    4. التوجيه: الدومين كله ⇐ http://localhost:5000 (الخادم نفسه يقدم الواجهة والـ API).
    5. [العطل 7 من مشروع DMS]: ينسخ الإعدادات لحساب SYSTEM ويضبط ImagePath بـ --config و tunnel run،
       وإلا تبدأ الخدمة ثم تخرج صامتة.
#>

param(
    [string]$Domain     = "",
    [string]$TunnelName = ""
)

. "$PSScriptRoot\_common.ps1"
Assert-Admin
if (-not $Domain)     { $Domain = $NOCI.Domain }
if (-not $TunnelName) { $TunnelName = $NOCI.TunnelName }
$Port = $NOCI.Port
$Svc  = $NOCI.CfService
$Host.UI.RawUI.WindowTitle = "NOCI Deploy - 05 نفق Cloudflare"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🌐 [الخادم] نفق Cloudflare: https://$Domain ⇐ localhost:$Port" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. cloudflared
Write-Host "`n[1/6] فحص cloudflared..." -ForegroundColor Green
if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    Write-Host "  - تثبيت cloudflared..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Cloudflare.cloudflared --exact --silent --accept-source-agreements --accept-package-agreements
    } else {
        $msi = "$env:TEMP\cloudflared.msi"
        Invoke-WebRequest -UseBasicParsing -OutFile $msi -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.msi"
        $sig = Get-AuthenticodeSignature $msi
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Cloudflare') {
            Write-Host "🔴 توقيع ملف التثبيت ليس من Cloudflare. أُلغي التثبيت." -ForegroundColor Red
            Remove-Item $msi -Force; exit 1
        }
        Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
        Remove-Item $msi -Force -ErrorAction SilentlyContinue
    }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
$cfCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cfCmd) { Write-Host "🔴 تعذر العثور على cloudflared بعد التثبيت. أغلق النافذة وافتحها من جديد." -ForegroundColor Red; exit 1 }
$cfExe = $cfCmd.Source
$cfVer = (& $cfExe --version 2>&1 | Out-String).Trim()
Write-Host "✔ $cfVer" -ForegroundColor Green

# 2. تسجيل الدخول
Write-Host "`n[2/6] تفويض الدومين في Cloudflare..." -ForegroundColor Green
$userCfDir = "$env:USERPROFILE\.cloudflared"
$certPath  = "$userCfDir\cert.pem"
if (-not (Test-Path $certPath)) {
    Write-Host "  سيفتح المتصفح: سجّل الدخول لحساب Cloudflare واختر الدومين nociraq.com ثم Authorize." -ForegroundColor Cyan
    & $cfExe tunnel login
}
if (-not (Test-Path $certPath)) { Write-Host "🔴 لم يكتمل تسجيل الدخول (cert.pem غير موجود)." -ForegroundColor Red; exit 1 }
Write-Host "✔ شهادة التفويض موجودة." -ForegroundColor Green

# 3. النفق
Write-Host "`n[3/6] تهيئة النفق $TunnelName..." -ForegroundColor Green
$ErrorActionPreference = 'Continue'
$existing = & $cfExe tunnel list 2>$null | Select-String -SimpleMatch $TunnelName
$tunnelId = $null
if ($existing) { $tunnelId = ($existing.Line -split '\s+')[0] }
$credFile = if ($tunnelId) { "$userCfDir\$tunnelId.json" } else { $null }

if (-not $existing) {
    & $cfExe tunnel create $TunnelName
} elseif (-not (Test-Path $credFile)) {
    Write-Host "  ℹ النفق مسجل في Cloudflare لكن ملف اعتماده ليس على هذه الحاسبة: إعادة إنشائه..." -ForegroundColor Yellow
    & $cfExe tunnel cleanup $TunnelName 2>$null | Out-Null
    & $cfExe tunnel delete -f $TunnelName 2>$null | Out-Null
    & $cfExe tunnel create $TunnelName
} else {
    Write-Host "  ℹ النفق موجود وملف اعتماده على هذه الحاسبة." -ForegroundColor Gray
}
$line = & $cfExe tunnel list 2>$null | Select-String -SimpleMatch $TunnelName | Select-Object -First 1
$tunnelId = if ($line) { ($line.Line -split '\s+')[0] } else { $null }
if (-not $tunnelId -or -not (Test-Path "$userCfDir\$tunnelId.json")) {
    Write-Host "🔴 تعذر الحصول على معرف النفق أو ملف اعتماده." -ForegroundColor Red; exit 1
}
Write-Host "✔ معرف النفق: $tunnelId" -ForegroundColor Green

# 4. ربط الدومين
Write-Host "`n[4/6] ربط DNS: $Domain ⇐ النفق..." -ForegroundColor Green
& $cfExe tunnel route dns --overwrite-dns $TunnelName $Domain
$ErrorActionPreference = 'Stop'

# 5. إعدادات SYSTEM والخدمة (العطل 7)
Write-Host "`n[5/6] إعداد خدمة النفق بحساب SYSTEM..." -ForegroundColor Green
$sysDir = "C:\Windows\System32\config\systemprofile\.cloudflared"
New-Item -ItemType Directory -Force $sysDir | Out-Null
Copy-Item "$userCfDir\$tunnelId.json" $sysDir -Force
Copy-Item $certPath $sysDir -Force
@"
tunnel: $tunnelId
credentials-file: $sysDir\$tunnelId.json

ingress:
  - hostname: $Domain
    service: http://localhost:$Port
  - service: http_status:404
"@ | Out-File "$sysDir\config.yml" -Encoding ascii -Force

$ErrorActionPreference = 'Continue'
& $cfExe tunnel --config "$sysDir\config.yml" ingress validate
if ($LASTEXITCODE -ne 0) { Write-Host "🔴 قواعد التوجيه غير صالحة." -ForegroundColor Red; exit 1 }
if (-not (Get-Service -Name $Svc -ErrorAction SilentlyContinue)) {
    & $cfExe service install 2>&1 | Out-Null
}
$ErrorActionPreference = 'Stop'
$img = "`"$cfExe`" --config `"$sysDir\config.yml`" --no-autoupdate tunnel run"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Svc" -Name ImagePath -Value $img -Type ExpandString
sc.exe config $Svc start= auto | Out-Null
sc.exe failure $Svc reset= 86400 actions= restart/30000/restart/30000/restart/60000 | Out-Null
Write-Host "✔ ImagePath: $img" -ForegroundColor Green

# 6. التشغيل والفحص
Write-Host "`n[6/6] تشغيل النفق والتحقق عبر الإنترنت..." -ForegroundColor Green
Stop-Service $Svc -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service $Svc
$ok = $false
for ($i = 0; $i -lt 20 -and -not $ok; $i++) {
    Start-Sleep -Seconds 3
    try { $r = Invoke-RestMethod -Uri "https://$Domain/api/system/status" -TimeoutSec 8; $ok = [bool]$r.success } catch {}
}
Write-Host "  خدمة النفق: $((Get-Service $Svc).Status)" -ForegroundColor Cyan

Write-Host "`n==========================================================" -ForegroundColor Green
if ($ok) {
    Write-Host "  ✅ النظام متاح على https://$Domain" -ForegroundColor Green
} else {
    Write-Host "  ⚠️ النفق يعمل لكن الدومين لم يرد بعد (انتشار DNS قد يأخذ دقائق). أعد الفحص بالخطوة 6." -ForegroundColor Yellow
}
Write-Host "==========================================================" -ForegroundColor Green
