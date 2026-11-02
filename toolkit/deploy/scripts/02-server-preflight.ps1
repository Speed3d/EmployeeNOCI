<#
.SYNOPSIS
    02-server-preflight.ps1 - يُشغَّل على [ 🖥️ الخادم ]. قراءة فقط: لا يغيّر شيئاً.
.DESCRIPTION
    يفحص ما يقوم عليه التثبيت قبل البدء، لأن أغلب الأعطال تظهر متأخرة وبرسائل مضللة:
      · Node غير مثبت أو إصداره الرئيسي مختلف عن جهاز التطوير ⇐ مكتبة SQLite لا تُحمَّل والخادم يتوقف فوراً
      · المنفذ 5000 مشغول ⇐ الخادم يعيد التشغيل بلا نهاية
      · الحزمة ناقصة ⇐ صفحة بيضاء
#>

param([string]$Package = "")

. "$PSScriptRoot\_common.ps1"
$Host.UI.RawUI.WindowTitle = "NOCI Deploy - 02 الفحص المسبق"

$script:Fail = 0
function Ok($m)   { Write-Host "   [ نجح ]  $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "   [ فشل ]  $m" -ForegroundColor Red; $script:Fail++ }
function Note($m) { Write-Host "   [ انتبه] $m" -ForegroundColor Yellow }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🖥️ [الخادم] الفحص المسبق قبل التثبيت" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. الحزمة
Write-Host "`n══ 1) حزمة الخادم" -ForegroundColor Cyan
$zip = Find-ServerPackage $Package
$manifest = Read-PackageManifest $zip
if ($manifest) {
    Ok "الحزمة: $($zip.FullName) · الإصدار $($manifest.version) · بُنيت على Node $($manifest.nodeFull)"
} else {
    Bad "الحزمة لا تحتوي manifest.json. أعد بناءها بالخطوة 1 على جهاز التطوير."
}

# 2. Node
Write-Host "`n══ 2) Node.js" -ForegroundColor Cyan
$nodeExe = Get-NodeExe
if (-not $nodeExe) {
    Bad "Node.js غير مثبت."
    if ($manifest) { Write-Host "            ثبّت Node $($manifest.nodeMajor) LTS (Windows x64 .msi) من https://nodejs.org" -ForegroundColor DarkGray }
} else {
    $v = (& $nodeExe -v).Trim().TrimStart('v')
    $major = [int]$v.Split('.')[0]
    if ($major -lt 20) {
        Bad "Node $v قديم. المطلوب 20 فأحدث، والمفضل $($manifest.nodeMajor) مثل جهاز البناء."
    } elseif ($manifest -and $major -ne [int]$manifest.nodeMajor) {
        Ok "Node $v في $nodeExe"
        Note "الحزمة بُنيت على Node $($manifest.nodeMajor). الأسلم تثبيت نفس الإصدار الرئيسي على الخادم."
    } else {
        Ok "Node $v في $nodeExe"
    }
    if ($nodeExe -notlike "C:\Program Files\*") {
        Note "Node مثبت لمستخدم واحد ($nodeExe). الخدمة تعمل بحساب SYSTEM، فالأفضل تثبيته لكل المستخدمين بملف .msi"
    }
}

# 3. المنفذ
Write-Host "`n══ 3) المنفذ $($NOCI.Port)" -ForegroundColor Cyan
$busy = Get-NetTCPConnection -LocalPort $NOCI.Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($busy) {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($busy.OwningProcess)"
    if ($p.CommandLine -match [regex]::Escape($NOCI.InstallDir)) {
        Note "المنفذ يستخدمه خادم NOCI مثبت مسبقاً (لتحديثه استعمل الخطوة 7 لا التثبيت من جديد)."
    } else {
        Bad "المنفذ مشغول ببرنامج آخر: $($p.Name) (PID $($busy.OwningProcess))"
    }
} else {
    Ok "المنفذ $($NOCI.Port) متاح."
}

# 4. تثبيت سابق
Write-Host "`n══ 4) تثبيت سابق" -ForegroundColor Cyan
$installed = Get-InstalledVersion
if ($installed) {
    Note "يوجد تثبيت سابق للإصدار $installed في $($NOCI.InstallDir). للتحديث استعمل الخطوة 7 (تحافظ على البيانات)."
} else {
    Ok "لا يوجد تثبيت سابق في $($NOCI.InstallDir)."
}

# 5. المساحة
Write-Host "`n══ 5) المساحة على C" -ForegroundColor Cyan
$freeGb = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
if ($freeGb -lt 2) { Bad "المساحة الحرة $freeGb غيغابايت فقط." } else { Ok "المساحة الحرة $freeGb غيغابايت." }

# 6. الإنترنت وCloudflare
Write-Host "`n══ 6) الإنترنت وcloudflared" -ForegroundColor Cyan
try {
    Invoke-WebRequest -UseBasicParsing -Uri "https://www.cloudflare.com/cdn-cgi/trace" -TimeoutSec 8 | Out-Null
    Ok "الاتصال بـ Cloudflare يعمل."
} catch { Bad "لا يوجد اتصال بـ Cloudflare: $($_.Exception.Message)" }
$cf = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cf) { $cfv = (& $cf.Source --version 2>&1 | Out-String).Trim(); Ok "cloudflared مثبت: $cfv" } else { Note "cloudflared غير مثبت بعد (الخطوة 5 تثبّته)." }

Write-Host "`n==========================================================" -ForegroundColor Cyan
if ($script:Fail -eq 0) {
    Write-Host "  ✅ الفحص سليم. التالي: الخطوة 3 (التثبيت)." -ForegroundColor Green
} else {
    Write-Host "  🔴 يوجد $($script:Fail) مشكلة يجب حلها قبل التثبيت." -ForegroundColor Red
    exit 1
}
