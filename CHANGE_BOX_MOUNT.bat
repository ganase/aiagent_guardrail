@echo off
chcp 65001 >nul
title Shared Folder Configuration

cd /d "%~dp0"

echo Updating the shared folder configuration.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\configure_box_mount.ps1"
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to update the shared folder configuration.
    echo Review the error above and try again.
    echo.
    pause
    exit /b 1
)

echo.
echo [OK] The shared folder configuration was saved.
echo The new configuration will be used the next time AI Agent Workspace starts.
echo.
pause
exit /b 0
