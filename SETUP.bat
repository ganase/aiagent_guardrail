@echo off
chcp 65001 >nul
title AI Agent Workspace Setup

:: Change to the directory containing this batch file
cd /d "%~dp0"
:: App Installer supplies winget, which the setup wizard uses for prerequisites.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\ensure_winget.ps1"
if errorlevel 1 exit /b 1


:: Ask for the Box shared-folder path only once. When UAC elevation relaunches
:: this batch file, the configuration saved by the first process is reused.
if not exist "%~dp0config\box_mount.local.cmd" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\configure_box_mount.ps1"
    if errorlevel 1 (
        echo [ERROR] Failed to configure the Box shared folder.
        pause
        exit /b 1
    )
)


:: ---- Admin check ----
net session >nul 2>&1
if %ERRORLEVEL% equ 0 goto :RUN_WIZARD

:: Not admin: request UAC elevation and relaunch this batch as admin
echo Requesting administrator privileges (UAC)...
echo Please click [Yes] on the User Account Control prompt.
echo.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
if %ERRORLEVEL% equ 0 goto :EXIT

:: UAC was declined: fall through and run without admin (wizard will show warning)
echo Continuing without administrator rights. Some features will be limited.
echo.

:RUN_WIZARD

powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ^
  -File "%~dp0installer\setup_wizard.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Failed to launch the setup wizard.
    echo Windows PowerShell 5.1 or later is required.
    echo.
    pause
)

:EXIT
exit /b 0
