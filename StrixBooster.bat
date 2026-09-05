@echo off
title Fortnite Booster van StrixLuca
cd /d "%~dp0"

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator rights...
    powershell -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
    exit /b
)

echo.
echo   Fortnite Booster van StrixLuca is starting...
echo   The app window opens automatically.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0StrixBooster.ps1"

if %errorLevel% neq 0 (
    echo.
    echo   Something went wrong. Press any key to close.
    pause >nul
)
