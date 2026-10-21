@echo off
chcp 65001 > nul
title تشغيل نظام الحضور والبصمة - NOCI Attendance

echo ========================================================
echo   🏛️ تشغيل نظام حضور وبصمة موظفي المقر (NOCI Attendance)
echo ========================================================
echo.

cd /d "%~dp0..\backend"

echo [1/2] التحقق من قاعدة البيانات والموظفين...
node scripts/seed_employees.js

echo.
echo [2/2] إقلاع الخادم واستضافة النظام...
npm start

pause
