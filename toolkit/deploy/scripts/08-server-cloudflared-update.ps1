<#
.SYNOPSIS
    08-server-cloudflared-update.ps1 - يُشغَّل على [ 🖥️ الخادم ] عند كل تنبيه أمني من Cloudflare.
.DESCRIPTION
    منقول من أداة DMS (المرحلة 10) ومكيّف لنظام الحضور.
    خدمة النفق تعمل بـ --no-autoupdate فلا تتحدث وحدها أبداً.
    1. يقرأ مسار cloudflared.exe من ImagePath الخدمة، ويحفظ نسخة منه ومن ImagePath للتراجع.
    2. يسأل GitHub عن آخر إصدار، ويخرج بلا تغيير إن كانت النسخة حديثة.
    3. ينزّل الـ MSI الرسمي ويرفضه إن لم يكن موقّعاً من Cloudflare.
    4. يثبّت، ويعيد ImagePath كما كان حرفياً (العطل 7)، ثم يشغّل الخدمة.
    5. يفحص النسخة والخدمة والدومين، ويرجع النسخة السابقة عند أي فشل. الانقطاع ثوانٍ معدودة.
#>

param(
    [string]$Domain      = "",
    [string]$ServiceName = "",
    [string]$MinVersion  = ""
)

. "$PSScriptRoot\_common.ps1"
Assert-Admin
if (-not $Domain)      { $Domain = $NOCI.Domain }
if (-not $ServiceName) { $ServiceName = $NOCI.CfService }
if (-not $MinVersion)  { $MinVersion = $NOCI.MinCfVer }
$Host.UI.RawUI.WindowTitle = "NOCI Deploy - 08 تحديث نفق Cloudflare"
$ErrorActionPreference = 'Stop'

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🔐 [الخادم] تحديث cloudflared (النفق) بأمان" -ForegroundColor Cyan
Write-Host "  الدومين: https://$Domain · الحد الأدنى: $MinVersion" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

function Get-CfVersion([string]$exe) {
    $ErrorActionPreference = 'Continue'   # في PS 5.1 يصير stderr الأداة خطأً يوقف السكربت مع 'Stop'
    $out = & $exe --version 2>&1 | Out-String
    if ($out -match '(\d{4}\.\d+\.\d+)') { return [version]$Matches[1] }
    return $null
}

# 1. الخدمة ومسارها
Write-Host "`n[1/6] قراءة خدمة $ServiceName..." -ForegroundColor Green
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
if (-not (Test-Path $regPath)) { Write-Host "🔴 الخدمة $ServiceName غير موجودة — هل نُفّذت الخطوة 5؟" -ForegroundColor Red; exit 1 }
$imagePath = (Get-ItemProperty -Path $regPath -Name ImagePath).ImagePath
if ($imagePath -notmatch '--config') {
    Write-Host "🔴 ImagePath بلا --config (العطل 7) — أصلحه بالخطوة 5 قبل التحديث:" -ForegroundColor Red
    Write-Host "   $imagePath" -ForegroundColor Red; exit 1
}
$exe = if ($imagePath -match '^"([^"]+)"') { $Matches[1] } else { ($imagePath -split ' ')[0] }
$current = Get-CfVersion $exe
Write-Host "  ✔ الملف: $exe" -ForegroundColor Green
Write-Host "  ✔ النسخة الحالية: $current" -ForegroundColor Green

$backupDir = "$($NOCI.Releases)\cloudflared-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force $backupDir | Out-Null
Copy-Item $exe "$backupDir\cloudflared.exe" -Force
$imagePath | Out-File "$backupDir\ImagePath.txt" -Encoding utf8
Write-Host "  ✔ نسخة للتراجع في: $backupDir" -ForegroundColor Green

# 2. آخر إصدار
Write-Host "`n[2/6] السؤال عن آخر إصدار من GitHub..." -ForegroundColor Green
$latestTag = (Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/cloudflare/cloudflared/releases/latest").tag_name
$latest = [version]($latestTag -replace '^v', '')
Write-Host "  ✔ آخر إصدار: $latest" -ForegroundColor Green
if ($latest -lt [version]$MinVersion) {
    Write-Host "🔴 آخر إصدار منشور ($latest) أقلّ من الحدّ المطلوب ($MinVersion) — توقّف وراجع صفحة الإصدارات." -ForegroundColor Red; exit 1
}
if ($current -and $current -ge $latest) {
    Write-Host "`n✅ النسخة الحالية ($current) هي الأحدث — لا تغيير." -ForegroundColor Green; exit 0
}

# 3. التنزيل والتحقّق من التوقيع
Write-Host "`n[3/6] تنزيل الـMSI والتحقّق من توقيعه..." -ForegroundColor Green
$msi = "$env:TEMP\cloudflared-$latest.msi"
Invoke-WebRequest -UseBasicParsing -OutFile $msi -Uri "https://github.com/cloudflare/cloudflared/releases/download/$latestTag/cloudflared-windows-amd64.msi"
$sig = Get-AuthenticodeSignature $msi
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Cloudflare') {
    Write-Host "🔴 توقيع الملف غير صالح أو ليس من Cloudflare ($($sig.Status) · $($sig.SignerCertificate.Subject)) — لن يُثبَّت." -ForegroundColor Red
    Remove-Item $msi -Force; exit 1
}
Write-Host "  ✔ موقّع من: $($sig.SignerCertificate.Subject)" -ForegroundColor Green

function Restore-Old {
    Write-Host "`n↩️ التراجع إلى النسخة السابقة..." -ForegroundColor Yellow
    Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
    Copy-Item "$backupDir\cloudflared.exe" $exe -Force
    Set-ItemProperty -Path $regPath -Name ImagePath -Value $imagePath -Type ExpandString
    Start-Service $ServiceName
    Write-Host "  النسخة الآن: $(Get-CfVersion $exe) · الخدمة: $((Get-Service $ServiceName).Status)" -ForegroundColor Yellow
}

# 4. التثبيت (النظام ينقطع من هنا ثوانيَ)
Write-Host "`n[4/6] إيقاف النفق والتثبيت..." -ForegroundColor Green
Stop-Service $ServiceName -Force
$p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
if ($p.ExitCode -notin 0, 3010) { Write-Host "🔴 فشل التثبيت (رمز $($p.ExitCode))." -ForegroundColor Red; Restore-Old; exit 1 }

# 🔴 العطل 7: أيّ تثبيتٍ قد يعيد تسجيل الخدمة بلا --config ⟵ تُعاد كما كانت حرفياً
$after = (Get-ItemProperty -Path $regPath -Name ImagePath).ImagePath
if ($after -ne $imagePath) {
    Set-ItemProperty -Path $regPath -Name ImagePath -Value $imagePath -Type ExpandString
    Write-Host "  ⚠️ ImagePath تغيّر بالتثبيت فأُعيد كما كان." -ForegroundColor Yellow
}
Start-Service $ServiceName

# 5. الفحص
Write-Host "`n[5/6] الفحص بعد التحديث..." -ForegroundColor Green
$new = Get-CfVersion $exe
$svc = (Get-Service $ServiceName).Status
Write-Host "  النسخة: $new · الخدمة: $svc" -ForegroundColor Cyan
if (-not $new -or $new -lt [version]$MinVersion -or $svc -ne 'Running') {
    Write-Host "🔴 النسخة أو الخدمة ليست كما يجب." -ForegroundColor Red; Restore-Old; exit 1
}

$okDomain = $false
for ($i = 0; $i -lt 20 -and -not $okDomain; $i++) {
    try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Uri "https://$Domain/api/system/status"; $okDomain = ($r.StatusCode -eq 200) }
    catch { Start-Sleep 3 }
}
if (-not $okDomain) {
    Write-Host "🔴 الدومين لا يردّ بعد 60 ثانية." -ForegroundColor Red; Restore-Old; exit 1
}
Write-Host "  ✔ https://$Domain/api/system/status يردّ 200" -ForegroundColor Green
Remove-Item $msi -Force -ErrorAction SilentlyContinue

# 6. الخلاصة
Write-Host "`n[6/6] ✅ تمّ: cloudflared $current ⟵ $new" -ForegroundColor Green
Write-Host "  تأكّد من لوحة Cloudflare: Networking ⟵ Tunnels ⟵ النفق Healthy والموصل بالنسخة الجديدة." -ForegroundColor Cyan
Write-Host "  وافتح النظام من الهاتف على بيانات الجوال (لا من الحاسبة نفسها)." -ForegroundColor Cyan
Write-Host "  نسخة التراجع باقية في: $backupDir" -ForegroundColor DarkGray
