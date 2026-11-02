<#
    Run_Deploy_Menu.ps1 - القائمة التفاعلية لتشغيل أي خطوة من خطوات نشر نظام الحضور NOCI.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "إعادة فتح القائمة بصلاحيات المسؤول..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
$Host.UI.RawUI.WindowTitle = "NOCI Deploy - القائمة (Administrator)"
$scripts = Join-Path $PSScriptRoot "scripts"

$steps = [ordered]@{
    "0" = @("00-server-reset.ps1",               "🔄 [حاسبة التجربة] تصفير التثبيت بالكامل", "Yellow")
    "1" = @("01-dev-build-and-pack.ps1",         "💻 [جهاز التطوير] اختبار وبناء وحزم الخادم", "Blue")
    "2" = @("02-server-preflight.ps1",           "🖥️ [الخادم] الفحص المسبق (قراءة فقط)", "Cyan")
    "3" = @("03-server-install.ps1",             "🖥️ [الخادم] التثبيت من الصفر + حساب الدخول الأول", "Cyan")
    "4" = @("04-server-service.ps1",             "🖥️ [الخادم] تشغيل الخادم دائماً مع إقلاع الويندوز", "Cyan")
    "5" = @("05-server-tunnel.ps1",              "🌐 [الخادم] نفق Cloudflare ⇐ employee.nociraq.com", "Cyan")
    "6" = @("06-server-verify.ps1",              "🎯 [الخادم] الفحص الشامل", "Green")
    "7" = @("07-server-update-release.ps1",      "🚀 [الخادم] تحديث نسخة عاملة مع الحفاظ على البيانات", "Green")
    "8" = @("08-server-cloudflared-update.ps1",  "🔐 [الخادم] تحديث cloudflared بأمان", "Green")
}

do {
    Clear-Host
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "        🚀 نشر نظام حضور موظفي المقر NOCI — القائمة التفاعلية" -ForegroundColor White
    Write-Host "========================================================================" -ForegroundColor Cyan
    foreach ($k in $steps.Keys) {
        if ($k -in '1', '2', '7') { Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray }
        Write-Host "  [$k] $($steps[$k][1])  ($($steps[$k][0]))" -ForegroundColor $steps[$k][2]
    }
    Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [H] 🌐 فتح الدليل التفاعلي في المتصفح (NOCI_Deploy_Wizard.html)" -ForegroundColor Magenta
    Write-Host "  [Q] 🚪 خروج" -ForegroundColor Gray
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "  تثبيت أول مرة: 2 ⇐ 3 ⇐ 4 ⇐ 5 ⇐ 6      تحديث إصدار: 7 فقط" -ForegroundColor DarkCyan

    $choice = (Read-Host "اختر رقم الخطوة").Trim().ToUpper()
    if ($choice -eq 'Q') { break }
    if ($choice -eq 'H') { Start-Process (Join-Path $PSScriptRoot "NOCI_Deploy_Wizard.html"); continue }
    if ($steps.Contains($choice)) {
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts $steps[$choice][0])
    } else {
        Write-Host "خيار غير صالح." -ForegroundColor Red
    }
    Write-Host "`nاضغط Enter للعودة إلى القائمة..." -ForegroundColor DarkGray
    $null = Read-Host
} while ($true)
