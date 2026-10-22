@echo off
chcp 65001 > nul
title تثبيت التشغيل التلقائي للنظام مع إقلاع الويندوز

echo ========================================================
echo   🏛️ تثبيت التشغيل التلقائي لنظام NOCI في الخلفية
echo ========================================================
echo.

set "STARTUP_FOLDER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "VBS_SCRIPT=%~dp0run-silent.vbs"

echo جاري ربط الخادم ببدء تشغيل الويندوز...
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%STARTUP_FOLDER%\NociAttendanceServer.lnk'); $s.TargetPath = 'wscript.exe'; $s.Arguments = '\"%VBS_SCRIPT%\"'; $s.WorkingDirectory = '%~dp0..\backend'; $s.Save()"

echo.
echo ✔ تم التثبيت بنجاح!
echo من الآن فصاعداً: سيعمل الخادم تلقائياً في الخلفية في كل مرة تفتح فيها الحاسبة دون الحاجة لأي تشغيل يدوي.
echo المنفذ 5000 سيكون متاحاً دائماً.
echo.
pause
