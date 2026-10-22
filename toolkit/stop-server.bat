@echo off
chcp 65001 > nul
title إيقاف خادم نظام الحضور

echo جاري فحص وإيقاف أي خادم يعمل على المنفذ 5000...

powershell -Command "Get-NetTCPConnection -LocalPort 5000 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }; Write-Host '✔ تم إيقاف الخادم بنجاح!'"

pause
