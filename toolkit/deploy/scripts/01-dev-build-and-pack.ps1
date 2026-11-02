<#
.SYNOPSIS
    01-dev-build-and-pack.ps1 - يُشغَّل على [ 💻 جهاز التطوير ] حصراً.
.DESCRIPTION
    يشغّل الاختبارات، ويبني واجهة الويب، ثم يجمع حزمة خادم واحدة جاهزة للنقل:
        noci-server-<الإصدار>.zip
    تحتوي: backend (مع node_modules) + app/build/web + أدوات النشر + manifest.json.
    الحزمة لا تحتوي أي بيانات أو أسرار: data و.keys وuploads وlogs و.env مستبعدة دائماً.
#>

param(
    [string]$OutputDir = "",
    [switch]$SkipTests
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "NOCI Deploy - 01 بناء وحزم جهاز التطوير"
# Continue: أدوات flutter وnpm تكتب تنبيهات في stderr، ونعتمد رمز الخروج بدلها
$ErrorActionPreference = 'Continue'

# جذر المشروع = مجلدان فوق هذا السكربت (toolkit\deploy\scripts)
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..\..").Path
$Backend  = Join-Path $RepoRoot "backend"
$AppDir   = Join-Path $RepoRoot "app"
if (-not $OutputDir) { $OutputDir = Join-Path $RepoRoot "releases\server" }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  💻 [جهاز التطوير] بناء وحزم خادم نظام الحضور NOCI" -ForegroundColor Cyan
Write-Host "  المشروع: $RepoRoot" -ForegroundColor Yellow
Write-Host "  الإخراج: $OutputDir" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-Path "$Backend\src\app.js") -or -not (Test-Path "$AppDir\pubspec.yaml")) {
    Write-Host "🔴 هذا ليس جهاز التطوير: كود المصدر غير موجود في $RepoRoot" -ForegroundColor Red
    exit 1
}

$version = (Get-Content "$Backend\package.json" -Raw | ConvertFrom-Json).version
$nodeVer = (node -v).Trim().TrimStart('v')
$nodeMajor = [int]($nodeVer.Split('.')[0])
$commit  = (git -C $RepoRoot rev-parse --short HEAD).Trim()
$build   = Get-Date -Format 'yyyyMMddHHmm'
Write-Host "  الإصدار $version · commit $commit · بناء $build · Node $nodeVer" -ForegroundColor Yellow

# 1. الاختبارات
if (-not $SkipTests) {
    Write-Host "`n[1/5] تشغيل اختبارات الخادم وFlutter..." -ForegroundColor Green
    Push-Location $Backend
    npm test
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { Write-Host "🔴 فشلت اختبارات الخادم. توقف البناء." -ForegroundColor Red; exit 1 }

    Push-Location $AppDir
    flutter analyze
    $a = $LASTEXITCODE
    flutter test
    $t = $LASTEXITCODE
    Pop-Location
    if ($a -ne 0 -or $t -ne 0) { Write-Host "🔴 فشل تحليل أو اختبارات Flutter. توقف البناء." -ForegroundColor Red; exit 1 }
    Write-Host "✔ كل الاختبارات ناجحة." -ForegroundColor Green
} else {
    Write-Host "`n[1/5] ⚠️ تم تخطي الاختبارات بطلبك (-SkipTests)." -ForegroundColor Yellow
}

# 2. بناء واجهة الويب
# الواجهة على الدومين تستعمل عنوان الصفحة نفسها للـ API (api_client.dart)، فلا يُخبز الدومين داخلها
Write-Host "`n[2/5] بناء واجهة الويب (Flutter Web)..." -ForegroundColor Green
Push-Location $AppDir
flutter build web --release "--build-name=$version" "--build-number=$build"
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Write-Host "🔴 فشل بناء الواجهة." -ForegroundColor Red; exit 1 }
Write-Host "✔ تم بناء الواجهة." -ForegroundColor Green

# 3. تجهيز مجلد الحزمة
Write-Host "`n[3/5] تجميع ملفات الحزمة..." -ForegroundColor Green
$stage = Join-Path $env:TEMP "noci-pack-$build"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force "$stage\backend", "$stage\app\build", "$stage\toolkit" | Out-Null

foreach ($item in @('src', 'scripts', 'vendor', 'node_modules', 'package.json', 'package-lock.json')) {
    Copy-Item (Join-Path $Backend $item) "$stage\backend\" -Recurse -Force
}
Copy-Item "$AppDir\build\web" "$stage\app\build\web" -Recurse -Force
Copy-Item "$RepoRoot\toolkit\deploy" "$stage\toolkit\deploy" -Recurse -Force

@{
    version   = $version
    commit    = $commit
    build     = $build
    nodeMajor = $nodeMajor
    nodeFull  = $nodeVer
    builtAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm')
} | ConvertTo-Json | Out-File "$stage\manifest.json" -Encoding utf8

# 4. الحراس: لا بيانات ولا أسرار ولا واجهة ناقصة
Write-Host "`n[4/5] فحص الحراس..." -ForegroundColor Yellow
$leaks = @('backend\data', 'backend\.keys', 'backend\.env', 'backend\uploads', 'backend\logs') |
    Where-Object { Test-Path (Join-Path $stage $_) }
if ($leaks) {
    Write-Host "🔴 الحارس 1 فشل: ملفات بيانات أو أسرار داخل الحزمة: $($leaks -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "  ✔ الحارس 1: لا بيانات ولا مفاتيح ولا .env داخل الحزمة." -ForegroundColor Green

foreach ($f in @('index.html', 'main.dart.js', 'flutter_bootstrap.js', 'canvaskit\canvaskit.wasm')) {
    if (-not (Test-Path "$stage\app\build\web\$f")) {
        Write-Host "🔴 الحارس 2 فشل: الملف $f غير موجود في الواجهة (ستظهر صفحة بيضاء)." -ForegroundColor Red
        exit 1
    }
}
Write-Host "  ✔ الحارس 2: ملفات الواجهة الأساسية موجودة (index.html وmain.dart.js وcanvaskit.wasm)." -ForegroundColor Green

if (-not (Test-Path "$stage\backend\node_modules\better-sqlite3\prebuilds\win32-x64.node")) {
    Write-Host "🔴 الحارس 3 فشل: مكتبة SQLite المبنية غير موجودة. شغّل npm ci داخل backend أولاً." -ForegroundColor Red
    exit 1
}
Write-Host "  ✔ الحارس 3: مكتبة SQLite المبنية لويندوز x64 موجودة." -ForegroundColor Green

# 5. الضغط
Write-Host "`n[5/5] ضغط الحزمة..." -ForegroundColor Green
New-Item -ItemType Directory -Force $OutputDir | Out-Null
$zip = Join-Path $OutputDir "noci-server-$version.zip"
if (Test-Path $zip) {
    $old = Join-Path $OutputDir "Old\backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Force $old | Out-Null
    Move-Item $zip $old -Force
    Write-Host "  - أُرشفت الحزمة السابقة في: $old" -ForegroundColor Gray
}
Compress-Archive -Path "$stage\*" -DestinationPath $zip -Force
Remove-Item $stage -Recurse -Force

$mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
if ($mb -lt 5) { Write-Host "🔴 حجم الحزمة $mb ميغابايت فقط، وهذا أقل من المتوقع." -ForegroundColor Red; exit 1 }

# نسخة من أدوات النشر بجانب الحزمة، لتشغيل القائمة على الخادم مباشرة من الفلاشة
$kit = Join-Path $OutputDir "NOCI-Deploy"
if (Test-Path $kit) { Remove-Item $kit -Recurse -Force }
Copy-Item "$RepoRoot\toolkit\deploy" $kit -Recurse -Force

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ تم البناء والحزم: $zip ($mb ميغابايت)" -ForegroundColor Green
Write-Host "  انسخ إلى الفلاشة: الملف noci-server-$version.zip والمجلد NOCI-Deploy" -ForegroundColor Green
Write-Host "  ثم على الخادم: NOCI-Deploy\Run_Deploy_Menu.bat" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
