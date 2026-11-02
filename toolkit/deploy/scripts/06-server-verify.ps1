<#
.SYNOPSIS
    06-server-verify.ps1 - يُشغَّل على [ 🖥️ الخادم ]. قراءة فقط.
.DESCRIPTION
    الفحص الشامل: المهمة والخادم المحلي، وخدمة النفق ومسارها (العطل 7)، و.env، والنسخ التلقائية،
    والدومين من الإنترنت (الـ API والواجهة).
#>

. "$PSScriptRoot\_common.ps1"
$Host.UI.RawUI.WindowTitle = "NOCI Deploy - 06 الفحص الشامل"
$Domain = $NOCI.Domain
$score = 0; $total = 7
function Pass($m) { Write-Host "  ✔ $m" -ForegroundColor Green; $script:score++ }
function Miss($m) { Write-Host "  🔴 $m" -ForegroundColor Red }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🎯 الفحص الشامل لنظام الحضور على https://$Domain" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host "`n[1/7] مهمة تشغيل الخادم..." -ForegroundColor Green
$task = Get-ScheduledTask -TaskName $NOCI.TaskName -ErrorAction SilentlyContinue
if ($task -and $task.State -eq 'Running' -and $task.Principal.UserId -match 'SYSTEM') { Pass "المهمة $($NOCI.TaskName) تعمل بحساب SYSTEM." }
elseif ($task) { Miss "المهمة موجودة لكن حالتها $($task.State). (الخطوة 4)" }
else { Miss "المهمة غير مسجلة. (الخطوة 4)" }

Write-Host "`n[2/7] الخادم المحلي..." -ForegroundColor Green
$local = Wait-LocalApi 5
if ($local) { Pass "يرد على 127.0.0.1:$($NOCI.Port) · الإصدار $($local.version) · الصيانة $($local.isMaintenance)" }
else { Miss "لا يرد. راجع $($NOCI.Backend)\logs\server.log" }

Write-Host "`n[3/7] ملف البيئة..." -ForegroundColor Green
$envFile = "$($NOCI.Backend)\.env"
if ((Test-Path $envFile) -and ((Get-Content $envFile -Raw) -match '(?m)^HOST=127\.0\.0\.1')) { Pass "HOST=127.0.0.1 (الخادم لا يقبل اتصالات الشبكة غير المشفرة)." }
else { Write-Host "  ⚠️ HOST ليس 127.0.0.1: الخادم يقبل اتصالات من الشبكة المحلية أيضاً." -ForegroundColor Yellow; $script:score++ }

Write-Host "`n[4/7] خدمة النفق..." -ForegroundColor Green
$cf = Get-Service $NOCI.CfService -ErrorAction SilentlyContinue
$img = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($NOCI.CfService)" -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
if ($cf -and $cf.Status -eq 'Running' -and $img -match '--config' -and $img -match 'tunnel run') { Pass "Cloudflared يعمل ومساره يحمل --config و tunnel run." }
elseif ($cf) { Miss "Cloudflared حالته $($cf.Status) أو مساره ناقص (العطل 7): $img  (الخطوة 5)" }
else { Miss "خدمة Cloudflared غير موجودة. (الخطوة 5)" }

Write-Host "`n[5/7] النسخ الاحتياطية التلقائية..." -ForegroundColor Green
$last = Get-ChildItem "$($NOCI.Backend)\data\backups\auto_*.db" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($last -and $last.LastWriteTime -gt (Get-Date).AddHours(-26)) { Pass "آخر نسخة تلقائية: $($last.Name)" }
elseif ($last) { Miss "آخر نسخة تلقائية قديمة: $($last.Name)" }
else { Miss "لا توجد نسخ تلقائية بعد (تُنشأ عند إقلاع الخادم)." }

Write-Host "`n[6/7] الـ API عبر الدومين..." -ForegroundColor Green
try {
    $r = Invoke-RestMethod -Uri "https://$Domain/api/system/status" -TimeoutSec 10
    if ($r.success) { Pass "https://$Domain/api/system/status يرد (الإصدار $($r.version))." } else { Miss "رد غير متوقع." }
} catch { Miss "تعذر الوصول: $($_.Exception.Message)" }

Write-Host "`n[7/7] الواجهة عبر الدومين..." -ForegroundColor Green
try {
    $w = Invoke-WebRequest -Uri "https://$Domain/" -UseBasicParsing -TimeoutSec 10
    if ($w.StatusCode -eq 200 -and $w.Content -match 'flutter') { Pass "واجهة النظام تُفتح عبر الدومين." } else { Miss "الصفحة ردت لكن محتواها ليس واجهة النظام." }
} catch { Miss "تعذر فتح الواجهة: $($_.Exception.Message)" }

Write-Host "`n==========================================================" -ForegroundColor Cyan
$c = if ($score -eq $total) { 'Green' } else { 'Yellow' }
Write-Host "  النتيجة: $score من $total" -ForegroundColor $c
Write-Host "  الاختبار الحاسم: افتح https://$Domain من الهاتف على بيانات الجوال (لا من شبكة الخادم)." -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
