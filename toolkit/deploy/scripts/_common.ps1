<#
    _common.ps1 - إعدادات ودوال مشتركة تُحمَّل في بداية كل سكربتات الخادم (dot-source).
    غيّر القيم هنا مرة واحدة إذا تغيّر الدومين أو مجلد التثبيت.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$NOCI = @{
    InstallDir  = "C:\NOCI"
    Domain      = "employee.nociraq.com"
    Port        = 5000
    TaskName    = "NociAttendanceServer"
    TunnelName  = "noci-attendance-tunnel"
    CfService   = "Cloudflared"
    MinCfVer    = "2026.10.2"
}
$NOCI.Backend  = Join-Path $NOCI.InstallDir "backend"
$NOCI.WebDir   = Join-Path $NOCI.InstallDir "app\build\web"
$NOCI.Releases = Join-Path $NOCI.InstallDir "releases"
# مسارات تحمل بيانات المؤسسة وأسرارها: لا يمسها التحديث أبداً
$NOCI.Preserve = @('data', '.keys', 'uploads', 'logs', '.env')

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "🔴 شغّل هذا السكربت بصلاحيات المسؤول (Run as Administrator)." -ForegroundColor Red
        exit 1
    }
}

# يبحث عن أحدث noci-server-*.zip: المسار المعطى، ثم حول أدوات النشر، ثم جذور كل المحركات عدا C
function Find-ServerPackage([string]$Path) {
    if ($Path) {
        if (Test-Path $Path) { return (Get-Item $Path) }
        Write-Host "🔴 الحزمة غير موجودة: $Path" -ForegroundColor Red
        exit 1
    }
    # بجانب أدوات النشر في الفلاشة، ومجلد releases\server عند التشغيل من المشروع نفسه
    $roots = @("$PSScriptRoot\..", "$PSScriptRoot\..\..", "$PSScriptRoot\..\..\..\releases\server") +
        (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -ne 'C:\' } | ForEach-Object { $_.Root })
    foreach ($r in $roots) {
        $zip = Get-ChildItem -Path $r -Filter "noci-server-*.zip" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($zip) { return $zip }
    }
    Write-Host "🔴 لم أجد حزمة noci-server-*.zip في الفلاشة أو بجانب أدوات النشر." -ForegroundColor Red
    Write-Host "   حدّد مسارها: -Package E:\noci-server-2.0.0.zip" -ForegroundColor Yellow
    exit 1
}

# يقرأ manifest.json من داخل الحزمة دون فكها
function Read-PackageManifest($zipItem) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($zipItem.FullName)
    try {
        $entry = $z.Entries | Where-Object { $_.FullName -eq 'manifest.json' } | Select-Object -First 1
        if (-not $entry) { return $null }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { return ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Close() }
    } finally { $z.Dispose() }
}

function Get-NodeExe {
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $default = "C:\Program Files\nodejs\node.exe"
    if (Test-Path $default) { return $default }
    return $null
}

function Get-InstalledVersion {
    $pkg = Join-Path $NOCI.Backend "package.json"
    if (-not (Test-Path $pkg)) { return $null }
    return (Get-Content $pkg -Raw | ConvertFrom-Json).version
}

# يوقف المهمة المجدولة ثم أي node يشغّل ملفات C:\NOCI (المشرف والخادم الابن)
function Stop-NociServer {
    # تعطيل المهمة مؤقتاً حتى لا تعيد سياسة "إعادة التشغيل عند الفشل" تشغيلها أثناء التحديث
    if (Get-ScheduledTask -TaskName $NOCI.TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $NOCI.TaskName -ErrorAction SilentlyContinue
        Disable-ScheduledTask -TaskName $NOCI.TaskName -ErrorAction SilentlyContinue | Out-Null
    }
    $pattern = [regex]::Escape($NOCI.InstallDir)
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
        Where-Object { $_.CommandLine -match $pattern } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

function Start-NociServer {
    Enable-ScheduledTask -TaskName $NOCI.TaskName -ErrorAction SilentlyContinue | Out-Null
    Start-ScheduledTask -TaskName $NOCI.TaskName
}

# ينتظر رد /api/system/status محلياً
function Wait-LocalApi([int]$Seconds = 30) {
    for ($i = 0; $i -lt $Seconds; $i++) {
        try {
            $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($NOCI.Port)/api/system/status" -TimeoutSec 3
            if ($r.success) { return $r }
        } catch { Start-Sleep -Seconds 1 }
    }
    return $null
}
