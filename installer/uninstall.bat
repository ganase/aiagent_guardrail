@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

title AI Agent Workspace Uninstall

rem This script is intentionally destructive and removes this work environment.
rem It removes the tools installed by SETUP.bat and their user-level remnants.
rem .claude and .codex are removed on every uninstall, including their
rem authentication settings and credentials; this is intentional.

echo.
echo ============================================================
echo   AI Agent Workspace Uninstall
echo ============================================================
echo Run this file with "Run as administrator" when Node.js, Python,
echo or Git was installed for all users. Their uninstallers may require UAC.
echo The following will be removed for the current Windows user:
echo   - Python 3.12, Node.js LTS, Git for Windows (via winget)
echo   - Claude Code and Codex global npm packages
echo   - %%APPDATA%%\npm\claude* / codex* and their npm package folders
echo   - %%USERPROFILE%%\.claude and %%USERPROFILE%%\.codex (including credentials)
echo   - Related desktop/startup shortcuts and AI Agent Guardrail user install

echo.
set "CONFIRM="
set /p "CONFIRM=Type DELETE to continue: "
if /i not "%CONFIRM%"=="DELETE" (
    echo Cancelled. Nothing was removed.
    exit /b 1
)

echo.
echo [1/6] Uninstalling Claude Code and Codex npm packages...
where npm.cmd >nul 2>&1
if not errorlevel 1 (
    call npm.cmd uninstall -g @anthropic-ai/claude-code @openai/codex
) else (
    echo INFO: npm.cmd was not found. Removing npm remnants directly.
)

echo.
echo [2/6] Uninstalling Node.js and other packages installed by SETUP.bat via winget...
call :UninstallWinget "Python.Python.3.12"
call :UninstallWinget "OpenJS.NodeJS.LTS"
call :UninstallWinget "Git.Git"

echo.
echo [3/6] Removing Claude Code and Codex npm remnants...
call :RemoveFile "%APPDATA%\npm\claude"
call :RemoveFile "%APPDATA%\npm\claude.cmd"
call :RemoveFile "%APPDATA%\npm\claude.ps1"
call :RemoveFile "%APPDATA%\npm\codex"
call :RemoveFile "%APPDATA%\npm\codex.cmd"
call :RemoveFile "%APPDATA%\npm\codex.ps1"
call :RemoveTree "%APPDATA%\npm\node_modules\@anthropic-ai\claude-code"
call :RemoveTree "%APPDATA%\npm\node_modules\@openai\codex"

echo.
echo [4/6] Removing Claude Code and Codex user settings and credentials...
call :RemoveTree "%USERPROFILE%\.claude"
call :RemoveTree "%USERPROFILE%\.codex"
call :RemoveTree "%APPDATA%\Claude"
call :RemoveTree "%LOCALAPPDATA%\claude"


echo.
echo [5/6] Removing installation leftovers and shortcuts...
call :RemoveTree "%LOCALAPPDATA%\Programs\Python\Python312"
call :RemoveTree "%LOCALAPPDATA%\pip\Cache"
call :RemoveTree "%APPDATA%\Python"
if defined AIAGENT_GUARDRAIL_HOME call :RemoveTree "%AIAGENT_GUARDRAIL_HOME%"
call :RemoveTree "%LOCALAPPDATA%\AIAgentGuardrails"
call :RemoveTree "%USERPROFILE%\AIAgent_Workspace"
call :RemoveFile "%USERPROFILE%\Desktop\Claude Code.lnk"
call :RemoveFile "%USERPROFILE%\Desktop\Codex.lnk"
call :RemoveFile "%USERPROFILE%\Desktop\AI Coding Workspace.lnk"
call :RemoveFile "%USERPROFILE%\Desktop\AI Agent Workspace.lnk"
call :RemoveFile "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\AIAgent_Workspace_BoxDriveMount.lnk"

rem Undo the shared-drive subst mapping and drop its saved configuration
rem (installer\box_mount.local.cmd, written by configure_box_mount.ps1).
set "BOX_ENABLED=0"
set "DRIVE_LETTER="
if exist "%~dp0..\config\box_mount.local.cmd" call "%~dp0..\config\box_mount.local.cmd"
if "%BOX_ENABLED%"=="1" if defined DRIVE_LETTER (
    echo   Unassigning shared drive: %DRIVE_LETTER%
    subst %DRIVE_LETTER% /d >nul 2>&1
)
call :RemoveFile "%~dp0..\config\box_mount.local.cmd"


echo.
echo [6/6] Clearing Guardrail user environment variables...
setx AIAGENT_GUARDRAIL_HOME "" >nul 2>&1

echo.
echo Completed. Restart the terminal or sign out/in before reinstalling.
echo NOTE: Python or Node.js installed by another method/version may remain.
pause
exit /b 0


:UninstallWinget
where winget.exe >nul 2>&1
if errorlevel 1 (
    echo INFO: winget was not found; skipped %~1.
    exit /b 0
)
echo   winget uninstall %~1
rem Do not use --silent or redirect output here. In particular, the Node.js
rem uninstaller can require a UAC prompt; hiding it made a failed uninstall
rem look like it had completed.
winget uninstall --id %~1 --exact --accept-source-agreements
if errorlevel 1 (
    echo   WARNING: Could not uninstall %~1. If it is installed for all users,
    echo            close this window and run uninstall.bat as administrator.
) else (
    echo   Removed: %~1
)
rem Check all winget sources after the attempt. This also reports an install
rem registered by a source other than the community winget source.
winget list --id %~1 --exact >nul 2>&1
if not errorlevel 1 (
    echo   WARNING: %~1 is still registered in winget after uninstall.
)
exit /b 0

:RemoveTree
if exist "%~1" (
    echo   Removing directory: %~1
    rmdir /s /q "%~1"
    if exist "%~1" echo   WARNING: Could not remove completely: %~1
)
exit /b 0

:RemoveFile
if exist "%~1" (
    echo   Removing file: %~1
    del /f /q "%~1" >nul 2>&1
    if exist "%~1" echo   WARNING: Could not remove: %~1
)
exit /b 0