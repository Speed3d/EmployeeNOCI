<#
.SYNOPSIS
    04-server-service.ps1 - يُشغَّل على [ 🖥️ الخادم ].
.DESCRIPTION
    يسجّل الخادم كمهمة مجدولة تعمل عند إقلاع الويندوز بحساب SYSTEM، أي قبل تسجيل دخول أي مستخدم
    وتبقى تعمل بعد تسجيل الخروج (بخلاف اختصار مجلد Startup الذي لا يعمل إلا بعد الدخول).
    تشغّل المهمة المشرف backend\scripts\run-forever.js الذي يعيد تشغيل الخادم خلال 3 ثوانٍ عند أي تعطل،
    والمهمة نفسها تُعاد تلقائياً إن توقف المشرف.
#>

. "$PSScriptRoot\_common.ps1"
Assert-Admin
$Host.UI.RawUI.WindowTitle = "NOCI Deploy - 04 تشغيل الخادم كخدمة"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🖥️ [الخادم] تسجيل الخادم للعمل الدائم مع إقلاع الويندوز" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Get-InstalledVersion)) { Write-Host "🔴 لا يوجد تثبيت في $($NOCI.InstallDir). نفّذ الخطوة 3 أولاً." -ForegroundColor Red; exit 1 }
$nodeExe = Get-NodeExe
if (-not $nodeExe) { Write-Host "🔴 Node.js غير موجود." -ForegroundColor Red; exit 1 }

# 1. إزالة أي تشغيل قديم
Write-Host "`n[1/3] إيقاف أي نسخة تعمل وإزالة التسجيل القديم..." -ForegroundColor Green
Stop-NociServer
if (Get-ScheduledTask -TaskName $NOCI.TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $NOCI.TaskName -Confirm:$false
}
# اختصار Startup القديم (من install-startup-service.bat) يشغّل نسخة ثانية تتنازع المنفذ
$oldLnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\NociAttendanceServer.lnk"
if (Test-Path $oldLnk) { Remove-Item $oldLnk -Force; Write-Host "  - أُزيل اختصار التشغيل القديم من مجلد Startup." -ForegroundColor Gray }

# 2. تسجيل المهمة
Write-Host "`n[2/3] تسجيل المهمة $($NOCI.TaskName)..." -ForegroundColor Green
$action = New-ScheduledTaskAction -Execute $nodeExe -Argument "`"$($NOCI.Backend)\scripts\run-forever.js`"" -WorkingDirectory $NOCI.Backend
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $NOCI.TaskName -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Description "خادم نظام حضور موظفي المقر NOCI (المنفذ $($NOCI.Port))" | Out-Null
Write-Host "✔ المهمة مسجلة: تعمل عند الإقلاع بحساب SYSTEM وتُعاد عند التوقف." -ForegroundColor Green

# 3. التشغيل والفحص
Write-Host "`n[3/3] تشغيل الخادم والتحقق من رده..." -ForegroundColor Green
Start-NociServer
$res = Wait-LocalApi 30
if ($res) {
    Write-Host "✔ الخادم يرد على http://127.0.0.1:$($NOCI.Port) · الإصدار $($res.version) · الصيانة: $($res.isMaintenance)" -ForegroundColor Green
} else {
    Write-Host "🔴 الخادم لم يرد خلال 30 ثانية. آخر سطور السجل:" -ForegroundColor Red
    Get-Content "$($NOCI.Backend)\logs\server.log" -Tail 25 -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ الخادم يعمل دائماً مع إقلاع الويندوز. السجل: $($NOCI.Backend)\logs\server.log" -ForegroundColor Green
Write-Host "  التالي: الخطوة 5 (نفق Cloudflare للدومين $($NOCI.Domain))." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
