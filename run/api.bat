@echo off
REM Node API on port 3000; restarts automatically if it stops.
title Makkal Budget API (port 3000)
cd /d "%~dp0..\server"
:loop
node src\index.js
echo [%date% %time%] API stopped - restarting in 3 s...
timeout /t 3 /nobreak >nul
goto loop
