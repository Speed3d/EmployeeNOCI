@echo off
title Stop NOCI Attendance Server
echo Stopping server on port 5000...
powershell -NoProfile -Command "$conns = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue; if ($conns) { foreach ($c in $conns) { Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue }; Write-Host 'Server stopped successfully!' -ForegroundColor Green } else { Write-Host 'Server is not running.' -ForegroundColor Yellow }"
echo.
pause
