@echo off
chcp 65001 > nul
title نظام حضور وبصمة موظفي المقر - NOCI Attendance

echo ========================================================
echo   🏛️ تشغيل نظام حضور وبصمة موظفي المقر (NOCI Attendance)
echo ========================================================
echo.

cd /d "%~dp0backend"

echo [1/3] فحص قاعدة البيانات والموظفين...
node scripts/seed_employees.js

echo.
echo [2/3] جاري تشغيل الخادم واستضافة واجهة النظام على المنفذ 5000...
echo      (سيتم فتح المتصفح تلقائياً على http://localhost:5000)
echo.

start "" powershell -WindowStyle Hidden -Command "Start-Sleep -Seconds 2; Start-Process 'http://localhost:5000'"

echo [3/3] خادم النظام والواجهة قيد التشغيل المباشر الآن...
echo (اترك هذه النافذة مفتوحة طالما أنك تستخدم البرنامج)
echo ========================================================
echo.

node src/app.js

pause
