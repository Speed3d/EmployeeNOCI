@echo off
chcp 65001 > nul
title إيقاف نظام حضور وبصمة موظفي المقر - NOCI Attendance

echo ========================================================
echo   🛑 جاري إيقاف نظام حضور وبصمة موظفي المقر (NOCI Attendance)
echo ========================================================
echo.
echo جاري فحص المنفذ 5000 وإنهاء السيرفر بأمان...

powershell -NoProfile -Command "$conns = Get-NetTCPConnection -LocalPort 5000 -ErrorAction SilentlyContinue; if ($conns) { $conns | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }; Write-Host '✔ تم إنهاء عملية الخادم بنجاح!' -ForegroundColor Green } else { Write-Host 'ℹ️ لم يتم العثور على أي خادم قيد التشغيل على المنفذ 5000 (النظام متوقف بالفعل).' -ForegroundColor Yellow }"

echo.
echo ========================================================
echo  ✔ تم إيقاف النظام بالكامل والمنفذ 5000 متاح الآن.
echo ========================================================
echo.
pause
