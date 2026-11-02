<#
.SYNOPSIS
    03-server-install.ps1 - يُشغَّل على [ 🖥️ الخادم ] للتثبيت من الصفر فقط.
.DESCRIPTION
    1. يفك الحزمة إلى C:\NOCI (backend + app\build\web).
    2. يكتب backend\.env بـ HOST=127.0.0.1 (لا اتصال غير مشفر من الشبكة؛ الوصول عبر النفق فقط).
    3. ينشئ قاعدة البيانات ومفاتيح التشفير، وحساب السوبر أدمن بكلمة مرور مؤقتة تُعرض هنا مرة واحدة.
    4. يقفل أذونات مجلد المفاتيح و.env على SYSTEM والمسؤولين.
    يرفض العمل إذا وُجد تثبيت سابق، حتى لا تُستبدل بيانات حقيقية (للتحديث: الخطوة 7).
#>

param(
    [string]$Package = "",
    [switch]$AllowLan
)

. "$PSScriptRoot\_common.ps1"
Assert-Admin
$Host.UI.RawUI.WindowTitle = "NOCI Deploy - 03 التثبيت"
$ErrorActionPreference = 'Stop'

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🖥️ [الخادم] تثبيت نظام الحضور NOCI في $($NOCI.InstallDir)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-InstalledVersion) {
    Write-Host "🔴 توقف آمن: يوجد تثبيت للإصدار $(Get-InstalledVersion) في $($NOCI.InstallDir)." -ForegroundColor Red
    Write-Host "   للتحديث مع الحفاظ على البيانات: الخطوة 7. للبدء من الصفر فعلاً: الخطوة 0 ثم أعد هذه الخطوة." -ForegroundColor Yellow
    exit 1
}

$nodeExe = Get-NodeExe
if (-not $nodeExe) { Write-Host "🔴 Node.js غير مثبت. شغّل الخطوة 2 لمعرفة الإصدار المطلوب." -ForegroundColor Red; exit 1 }

# 1. فك الحزمة
$zip = Find-ServerPackage $Package
Write-Host "`n[1/4] فك الحزمة $($zip.Name)..." -ForegroundColor Green
New-Item -ItemType Directory -Force $NOCI.InstallDir | Out-Null
Expand-Archive -Path $zip.FullName -DestinationPath $NOCI.InstallDir -Force
if (-not (Test-Path "$($NOCI.Backend)\src\app.js") -or -not (Test-Path "$($NOCI.WebDir)\index.html")) {
    Write-Host "🔴 الحزمة ناقصة بعد الفك (app.js أو index.html غير موجود)." -ForegroundColor Red
    exit 1
}
Write-Host "✔ تم فك الحزمة." -ForegroundColor Green

# 2. ملف البيئة
Write-Host "`n[2/4] كتابة backend\.env..." -ForegroundColor Green
$envHost = if ($AllowLan) { "0.0.0.0" } else { "127.0.0.1" }
@(
    "# إعدادات خادم NOCI على هذا الجهاز (لا يمسها التحديث)",
    "PORT=$($NOCI.Port)",
    "# 127.0.0.1 = الوصول عبر نفق Cloudflare فقط. 0.0.0.0 = يقبل أيضاً اتصالات الشبكة المحلية غير المشفرة",
    "HOST=$envHost",
    "ALLOWED_ORIGINS=https://$($NOCI.Domain)"
) | Out-File "$($NOCI.Backend)\.env" -Encoding utf8
Write-Host "✔ HOST=$envHost · ALLOWED_ORIGINS=https://$($NOCI.Domain)" -ForegroundColor Green

# 3. قاعدة البيانات والمفاتيح وحساب السوبر أدمن
Write-Host "`n[3/4] إنشاء قاعدة البيانات والمفاتيح وحساب السوبر أدمن..." -ForegroundColor Green
$chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$bytes = New-Object byte[] 10
$rng.GetBytes($bytes)
$tempPassword = 'Noci' + (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })) + '7'

$env:NOCI_INITIAL_ADMIN_PASSWORD = $tempPassword
Push-Location $NOCI.Backend
$ErrorActionPreference = 'Continue'
$out = & $nodeExe -e "require('./src/core/database'); console.log('DB_READY');" 2>&1 | Out-String
$ErrorActionPreference = 'Stop'
Pop-Location
Remove-Item Env:\NOCI_INITIAL_ADMIN_PASSWORD

if ($out -notmatch 'DB_READY') {
    Write-Host "🔴 فشل إنشاء قاعدة البيانات:" -ForegroundColor Red
    Write-Host $out
    Write-Host "   إذا ظهر NODE_MODULE_VERSION فإصدار Node هنا يختلف عن جهاز التطوير (راجع الخطوة 2)." -ForegroundColor Yellow
    exit 1
}
$adminCreated = $true
Write-Host "✔ قاعدة البيانات جاهزة: $($NOCI.Backend)\data\attendance.db" -ForegroundColor Green

# 4. الأذونات
Write-Host "`n[4/4] قفل أذونات المفاتيح وملف البيئة..." -ForegroundColor Green
icacls "$($NOCI.Backend)\.keys" /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" /grant:r "Administrators:(OI)(CI)F" | Out-Null
icacls "$($NOCI.Backend)\.env" /inheritance:r /grant:r "SYSTEM:F" /grant:r "Administrators:F" | Out-Null
Write-Host "✔ المفاتيح و.env لا يقرؤها إلا SYSTEM والمسؤولون." -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ تم التثبيت. التالي: الخطوة 4 (تشغيل الخادم كخدمة)." -ForegroundColor Green
if ($adminCreated) {
    Write-Host ""
    Write-Host "  🔑 حساب الدخول الأول — سجّله الآن، لن يُعرض مرة أخرى:" -ForegroundColor Yellow
    Write-Host "     اسم المستخدم: admin" -ForegroundColor Yellow
    Write-Host "     كلمة المرور المؤقتة: $tempPassword" -ForegroundColor Yellow
    Write-Host "     سيطلب النظام تغييرها عند أول دخول." -ForegroundColor Yellow
}
Write-Host "==========================================================" -ForegroundColor Green
