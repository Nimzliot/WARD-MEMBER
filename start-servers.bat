@echo off
REM Starts the Makkal Budget API + ngrok tunnel in the BACKGROUND (no windows).
REM A supervisor restarts them if they stop. Logs: run\logs\  Stop: stop-servers.bat
REM The APK and website use https://trade-skedaddle-previous.ngrok-free.dev
cd /d "%~dp0"
powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath node -ArgumentList 'run\supervisor.js' -WorkingDirectory '%~dp0' -WindowStyle Hidden"
echo Starting... check https://trade-skedaddle-previous.ngrok-free.dev/api/health in a few seconds.
timeout /t 5 >nul
