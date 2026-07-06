@echo off
title AI Agent Guardrail Setup

:: Change to the directory containing this batch file
cd /d "%~dp0"

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
