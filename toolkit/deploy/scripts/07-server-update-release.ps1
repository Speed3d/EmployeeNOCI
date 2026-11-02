<#
.SYNOPSIS
    07-server-update-release.ps1 - يُشغَّل على [ 🖥️ الخادم ] لتحديث نسخة عاملة (مثلاً 2.0.0 ⇐ 2.1.0).
.DESCRIPTION
    تحديث موضعي يحافظ على كل بيانات المؤسسة:
      لا يمس أبداً: backend\data (القاعدة والنسخ) و.keys (المفاتيح) وuploads (الصور) وlogs و.env
    1. يتحقق من الحزمة ومن تطابق Node مع جهاز البناء.
    2. يوقف الخادم، ويحفظ لقطة تراجع للكود ونسخة من قاعدة البيانات في C:\NOCI\releases\pre-update-...
    3. يستبدل الكود (backend\src وscripts وvendor وnode_modules وpackage*.json) والواجهة app\build\web.
    4. يشغّل الخادم (الترحيلات تُطبَّق تلقائياً عند الإقلاع) ويتحقق من الإصدار الجديد.
    5. عند أي فشل: تراجع تلقائي للكود والقاعدة معاً.
#>

param([string]$Package = "")

. "$PSScriptRoot\_common.ps1"
Assert-Admin
$Host.UI.RawUI.WindowTitle = "NOCI Deploy - 07 تحديث نسخة مرفوعة"
$ErrorActionPreference = 'Stop'

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🚀 [الخادم] تحديث نظام الحضور مع الحفاظ على البيانات" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. الفحص
Write-Host "`n[1/6] فحص الحزمة والتثبيت القائم..." -ForegroundColor Green
$oldVersion = Get-InstalledVersion
if (-not $oldVersion -or -not (Test-Path "$($NOCI.Backend)\data\attendance.db")) {
    Write-Host "🔴 توقف آمن: لا يوجد تثبيت عامل في $($NOCI.InstallDir). للتثبيت من الصفر: الخطوات 2 إلى 6." -ForegroundColor Red
    exit 1
}
$zip = Find-ServerPackage $Package
$manifest = Read-PackageManifest $zip
if (-not $manifest) { Write-Host "🔴 الحزمة بلا manifest.json." -ForegroundColor Red; exit 1 }
$nodeExe = Get-NodeExe
$nodeMajor = [int]((& $nodeExe -v).Trim().TrimStart('v').Split('.')[0])
if ($nodeMajor -ne [int]$manifest.nodeMajor) {
    Write-Host "  ⚠️ Node هنا $nodeMajor والحزمة بُنيت على $($manifest.nodeMajor). إن لم يقلع الخادم سيتراجع التحديث تلقائياً." -ForegroundColor Yellow
}
Write-Host "  ✔ الحالي: $oldVersion ⇐ الجديد: $($manifest.version) (commit $($manifest.commit))" -ForegroundColor Green
if ($manifest.version -eq $oldVersion) {
    $ans = Read-Host "  الإصدار نفسه مثبت. إعادة تثبيته؟ (y للمتابعة)"
    if ($ans -ne 'y') { Write-Host "  أُلغي." -ForegroundColor Gray; exit 0 }
}

# فك الحزمة في مجلد مؤقت أولاً: إن كانت تالفة نكتشف ذلك قبل إيقاف أي شيء
$stage = Join-Path $env:TEMP "noci-update-$(Get-Date -Format 'yyyyMMddHHmmss')"
Expand-Archive -Path $zip.FullName -DestinationPath $stage -Force
if (-not (Test-Path "$stage\backend\src\app.js") -or -not (Test-Path "$stage\app\build\web\index.html")) {
    Write-Host "🔴 الحزمة ناقصة بعد الفك." -ForegroundColor Red; Remove-Item $stage -Recurse -Force; exit 1
}

# 2. الإيقاف واللقطة
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$snap = Join-Path $NOCI.Releases "pre-update-$oldVersion-$stamp"
Write-Host "`n[2/6] إيقاف الخادم وحفظ لقطة التراجع في $snap..." -ForegroundColor Green
Stop-NociServer
$codeItems = @('src', 'scripts', 'vendor', 'node_modules', 'package.json', 'package-lock.json')
New-Item -ItemType Directory -Force "$snap\backend", "$snap\db", "$snap\app\build" | Out-Null
foreach ($i in $codeItems) {
    $p = Join-Path $NOCI.Backend $i
    if (Test-Path $p) { Copy-Item $p "$snap\backend\" -Recurse -Force }
}
if (Test-Path $NOCI.WebDir) { Copy-Item $NOCI.WebDir "$snap\app\build\web" -Recurse -Force }
Get-ChildItem "$($NOCI.Backend)\data\attendance.db*" | Copy-Item -Destination "$snap\db\" -Force
Write-Host "  ✔ لقطة الكود والواجهة وقاعدة البيانات محفوظة." -ForegroundColor Green

function Restore-Snapshot {
    Write-Host "`n↩️ تراجع تلقائي إلى $oldVersion..." -ForegroundColor Yellow
    Stop-NociServer
    foreach ($i in $codeItems) {
        $p = Join-Path $NOCI.Backend $i
        if (Test-Path $p) { Remove-Item $p -Recurse -Force }
        if (Test-Path "$snap\backend\$i") { Copy-Item "$snap\backend\$i" "$($NOCI.Backend)\" -Recurse -Force }
    }
    if (Test-Path $NOCI.WebDir) { Remove-Item $NOCI.WebDir -Recurse -Force }
    Copy-Item "$snap\app\build\web" $NOCI.WebDir -Recurse -Force
    Get-ChildItem "$($NOCI.Backend)\data\attendance.db*" | Remove-Item -Force
    Copy-Item "$snap\db\*" "$($NOCI.Backend)\data\" -Force
    Start-NociServer
    $r = Wait-LocalApi 30
    $state = if ($r) { "يعمل (الإصدار $($r.version))" } else { "لا يرد — راجع logs\server.log" }
    Write-Host "  الخادم بعد التراجع: $state" -ForegroundColor Yellow
}

# 3. الاستبدال
Write-Host "`n[3/6] استبدال الكود والواجهة..." -ForegroundColor Green
try {
    foreach ($i in $codeItems) {
        $p = Join-Path $NOCI.Backend $i
        if (Test-Path $p) { Remove-Item $p -Recurse -Force }
        Copy-Item "$stage\backend\$i" "$($NOCI.Backend)\" -Recurse -Force
    }
    if (Test-Path $NOCI.WebDir) { Remove-Item $NOCI.WebDir -Recurse -Force }
    Copy-Item "$stage\app\build\web" $NOCI.WebDir -Recurse -Force
    # أدوات النشر نفسها تُحدَّث أيضاً
    if (Test-Path "$stage\toolkit\deploy") {
        $kit = Join-Path $NOCI.InstallDir "toolkit\deploy"
        if ((Resolve-Path $PSScriptRoot).Path -notlike "$kit*") {
            if (Test-Path $kit) { Remove-Item $kit -Recurse -Force }
            New-Item -ItemType Directory -Force (Split-Path $kit) | Out-Null
            Copy-Item "$stage\toolkit\deploy" $kit -Recurse -Force
        }
    }
    Copy-Item "$stage\manifest.json" $NOCI.InstallDir -Force
} catch {
    Write-Host "🔴 فشل نسخ الملفات: $($_.Exception.Message)" -ForegroundColor Red
    Restore-Snapshot; exit 1
}
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  ✔ تم الاستبدال. البيانات والمفاتيح والصور و.env لم تُمس." -ForegroundColor Green

# 4. التشغيل
Write-Host "`n[4/6] تشغيل الخادم (تُطبَّق ترحيلات القاعدة تلقائياً)..." -ForegroundColor Green
Start-NociServer
$res = Wait-LocalApi 45
if (-not $res -or $res.version -ne $manifest.version) {
    $got = if ($res) { $res.version } else { 'لا رد' }
    Write-Host "🔴 الخادم لم يقلع بالإصدار الجديد ($got). آخر السجل:" -ForegroundColor Red
    Get-Content "$($NOCI.Backend)\logs\server.log" -Tail 20 -ErrorAction SilentlyContinue
    Restore-Snapshot; exit 1
}
Write-Host "  ✔ الخادم يعمل بالإصدار $($res.version)." -ForegroundColor Green

# 5. الدومين
Write-Host "`n[5/6] الفحص عبر الدومين..." -ForegroundColor Green
try {
    $d = Invoke-RestMethod -Uri "https://$($NOCI.Domain)/api/system/status" -TimeoutSec 10
    Write-Host "  ✔ https://$($NOCI.Domain) يرد بالإصدار $($d.version)" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️ الدومين لا يرد الآن ($($_.Exception.Message)). الخادم المحلي سليم؛ افحص النفق بالخطوة 6." -ForegroundColor Yellow
}

# 6. تنظيف اللقطات القديمة (الاحتفاظ بآخر 5)
Write-Host "`n[6/6] تنظيف لقطات التراجع القديمة..." -ForegroundColor Green
Get-ChildItem $NOCI.Releases -Directory -Filter "pre-update-*" -ErrorAction SilentlyContinue |
    Sort-Object CreationTime -Descending | Select-Object -Skip 5 |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ اكتمل التحديث: $oldVersion ⇐ $($manifest.version)" -ForegroundColor Green
Write-Host "  📦 لقطة التراجع: $snap" -ForegroundColor Cyan
Write-Host "  🌐 افتح https://$($NOCI.Domain) واضغط Ctrl+F5 لتحميل الواجهة الجديدة." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
