@echo off
REM Stops the background supervisor, the API and the ngrok tunnel.
cd /d "%~dp0"
if exist run\supervisor.pid (
  for /f %%p in (run\supervisor.pid) do taskkill /PID %%p /T /F >nul 2>&1
  del run\supervisor.pid >nul 2>&1
)
taskkill /IM ngrok.exe /F >nul 2>&1
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":3000" ^| findstr "LISTENING"') do taskkill /PID %%p /F >nul 2>&1
echo Stopped.
