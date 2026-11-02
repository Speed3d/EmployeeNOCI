<#
.SYNOPSIS
    00-server-reset.ps1 - تصفير [ 🧪 حاسبة التجربة ] وإعادتها نظيفة لتجربة التثبيت من الصفر.
.DESCRIPTION
    ⚠️ يحذف قاعدة البيانات والمفاتيح نهائياً. لا تشغّله على الخادم الرئيسي بعد بدء العمل الفعلي.
    قبل الحذف يحفظ نسخة من backend\data و.keys في C:\NOCI-reset-backup-<التاريخ> احتياطاً.
    يحذف: مهمة الخادم، وخدمة Cloudflared وإعداداتها لحساب SYSTEM، ومجلد C:\NOCI.
    لا يحذف النفق من حساب Cloudflare (الخطوة 5 تعيد استخدامه أو تعيد إنشاء اعتماده).
#>

. "$PSScriptRoot\_common.ps1"
Assert-Admin
$Host.UI.RawUI.WindowTitle = "NOCI Deploy - 00 تصفير حاسبة التجربة"

Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host "  ⚠️ تصفير تثبيت نظام الحضور على هذه الحاسبة" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow

$installed = Get-InstalledVersion
if ($installed) {
    Write-Host "  يوجد تثبيت للإصدار $installed في $($NOCI.InstallDir)." -ForegroundColor Yellow
}
$confirm = Read-Host "سيُحذف النظام وقاعدة بياناته من هذه الحاسبة. اكتب RESET للمتابعة"
if ($confirm -ne 'RESET') { Write-Host "أُلغي التصفير." -ForegroundColor Gray; exit 0 }

Write-Host "`n[1/4] إيقاف الخادم وحذف مهمته..." -ForegroundColor Cyan
Stop-NociServer
if (Get-ScheduledTask -TaskName $NOCI.TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $NOCI.TaskName -Confirm:$false
    Write-Host "  ✔ حُذفت المهمة $($NOCI.TaskName)." -ForegroundColor Green
}

Write-Host "`n[2/4] حذف خدمة Cloudflared..." -ForegroundColor Cyan
if (Get-Service -Name $NOCI.CfService -ErrorAction SilentlyContinue) {
    Stop-Service $NOCI.CfService -Force -ErrorAction SilentlyContinue
    Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    sc.exe delete $NOCI.CfService | Out-Null
    Write-Host "  ✔ حُذفت الخدمة." -ForegroundColor Green
}
$sysCf = "C:\Windows\System32\config\systemprofile\.cloudflared"
if (Test-Path $sysCf) { Remove-Item $sysCf -Recurse -Force -ErrorAction SilentlyContinue; Write-Host "  ✔ نُظّفت إعدادات النفق لحساب SYSTEM." -ForegroundColor Green }

Write-Host "`n[3/4] نسخة احتياطية أخيرة من البيانات والمفاتيح..." -ForegroundColor Cyan
if (Test-Path "$($NOCI.Backend)\data") {
    $bk = "C:\NOCI-reset-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Force $bk | Out-Null
    Copy-Item "$($NOCI.Backend)\data" $bk -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path "$($NOCI.Backend)\.keys") { Copy-Item "$($NOCI.Backend)\.keys" $bk -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host "  ✔ حُفظت في $bk (احذفها بنفسك إن لم تعد تحتاجها)." -ForegroundColor Green
}

Write-Host "`n[4/4] حذف $($NOCI.InstallDir)..." -ForegroundColor Cyan
if (Test-Path $NOCI.InstallDir) {
    Remove-Item $NOCI.InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $NOCI.InstallDir) { Write-Host "  ⚠️ بعض الملفات قيد الاستخدام. أغلق البرامج وأعد التشغيل." -ForegroundColor Yellow }
    else { Write-Host "  ✔ حُذف المجلد." -ForegroundColor Green }
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ الحاسبة نظيفة. للتثبيت من جديد: الخطوات 2 إلى 6." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
