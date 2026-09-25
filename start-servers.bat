@echo off
REM Starts the Makkal Budget API and the ngrok tunnel in two windows that keep
REM running (and restart themselves) independently of any editor or terminal.
REM The APK and the website call https://trade-skedaddle-previous.ngrok-free.dev
REM Double-click this file after a reboot. Keep the laptop plugged in and awake.

start "Makkal Budget API (port 3000)" cmd /k ""%~dp0run\api.bat""
timeout /t 4 /nobreak >nul
start "Makkal Budget ngrok tunnel" cmd /k ""%~dp0run\ngrok.bat""

echo Started. Health check: https://trade-skedaddle-previous.ngrok-free.dev/api/health
