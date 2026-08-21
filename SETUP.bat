@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
title Coding Agent for IT Setup

:: Change to the directory containing this batch file
cd /d "%~dp0" || exit /b 1

:: App Installer supplies winget, which the setup wizard uses for prerequisites.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\ensure_winget.ps1"
if errorlevel 1 exit /b 1

:: Ask for the Box shared-folder path, unless this Windows user already has a
:: valid saved choice. configure_box_mount.ps1 checks ownership itself and
:: skips the dialog only when config\box_mount.local.cmd's TARGET_DIR belongs
:: to the current user, so a config carried over from a different user (e.g.
:: copied along with a shared installer package) is never mistaken for this
:: user's own choice.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\configure_box_mount.ps1" -SkipIfOwnedByCurrentUser
if errorlevel 1 (
    echo [ERROR] Failed to configure the Box shared folder.
    pause
    exit /b 1
)

:: Preserve the original user's locations before UAC elevation.
:: The elevated account can differ when helpdesk/admin credentials are entered at the prompt.
:: Keep user-controlled paths outside parenthesized IF blocks to avoid cmd.exe parser errors.
if /i "%~1"=="--aiagent-caller-profile" goto :CallerFromArgs

set "AIAGENT_CALLER_PROFILE=%USERPROFILE%"
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "AIAGENT_CALLER_DESKTOP=%%D"
goto :AfterCaller

:CallerFromArgs
set "AIAGENT_CALLER_PROFILE=%~2"
set "AIAGENT_CALLER_DESKTOP=%~4"

:AfterCaller
if not defined AIAGENT_CALLER_DESKTOP set "AIAGENT_CALLER_DESKTOP=%AIAGENT_CALLER_PROFILE%\Desktop"

:: Check administrator privileges.
net session >nul 2>&1
if errorlevel 1 goto :NeedUac
goto :RunWizard

:NeedUac
echo Requesting administrator privileges [UAC]...
echo Use approved credentials if prompted. Your workspace and shortcut will remain under your profile.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$al='--aiagent-caller-profile ""{0}"" --aiagent-caller-desktop ""{1}""' -f $env:AIAGENT_CALLER_PROFILE,$env:AIAGENT_CALLER_DESKTOP; Start-Process -FilePath '%~f0' -ArgumentList $al -Verb RunAs" >nul 2>&1

if not errorlevel 1 exit /b 0

echo Continuing without administrator rights. Some features will be limited.
echo.

:RunWizard
powershell -NoProfile -ExecutionPolicy Bypass ^
  -File "%~dp0installer\setup_wizard.ps1" -CallerUserProfile "%AIAGENT_CALLER_PROFILE%" -CallerDesktop "%AIAGENT_CALLER_DESKTOP%"

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to launch the setup wizard.
    echo Windows PowerShell 5.1 or later is required.
    echo.
    pause
)

exit /b 0
