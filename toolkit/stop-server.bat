@echo off
chcp 65001 > nul
title إيقاف خادم نظام الحضور

echo جاري فحص وإيقاف أي خادم يعمل على المنفذ 5000...

REM إيقاف مشرف إعادة التشغيل التلقائي أولاً حتى لا يعيد تشغيل الخادم
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Where-Object { $_.CommandLine -like '*run-forever.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"

powershell -Command "Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }; Write-Host '✔ تم إيقاف الخادم بنجاح!'"

pause
