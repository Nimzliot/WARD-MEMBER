@echo off
REM ngrok tunnel on the fixed dev domain the APK uses; restarts automatically.
title Makkal Budget ngrok tunnel
:loop
ngrok http 3000 --url=https://trade-skedaddle-previous.ngrok-free.dev
echo [%date% %time%] ngrok stopped - restarting in 5 s...
timeout /t 5 /nobreak >nul
goto loop
