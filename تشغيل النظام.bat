@echo off
title NOCI Attendance System
cd /d "%~dp0backend"
echo [1/3] Checking database...
node scripts\seed_employees.js
echo.
echo [2/3] Launching browser at http://localhost:5000 ...
start "" powershell -WindowStyle Hidden -Command "Start-Sleep -Seconds 2; Start-Process 'http://localhost:5000'"
echo.
echo [3/3] Server is running on http://localhost:5000
echo ========================================================
echo Close this window to stop the server.
echo ========================================================
echo.
node src\app.js
pause
