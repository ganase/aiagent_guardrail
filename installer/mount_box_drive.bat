@echo off
chcp 65001 >nul
setlocal EnableExtensions

rem Reads config\box_mount.local.cmd.  The workspace mapping is always I:.
set "BOX_ENABLED=0"
set "LOCAL_CONFIG=%~dp0..\config\box_mount.local.cmd"
if exist "%LOCAL_CONFIG%" call "%LOCAL_CONFIG%"
if not "%BOX_ENABLED%"=="1" exit /b 0
if not defined TARGET_DIR (
    msg * "Error: TARGET_DIR is not set in box_mount.local.cmd."
    exit /b 1
)
if not defined DRIVE_LETTER set "DRIVE_LETTER=I:"
set "CONFIGURED_DRIVE_LETTER=%DRIVE_LETTER%"
set "DRIVE_LETTER=I:"

if not exist "%TARGET_DIR%" (
    msg * "Error: Box folder was not found: %TARGET_DIR%"
    exit /b 1
)

rem First detach this app's legacy mapping (such as J:), then recreate I:.
if /i not "%CONFIGURED_DRIVE_LETTER%"=="I:" subst %CONFIGURED_DRIVE_LETTER% /d >nul 2>&1
subst I: /d >nul 2>&1
if exist "I:\" (
    msg * "Error: I: is used by a physical or network drive."
    exit /b 1
)
subst I: "%TARGET_DIR%"
if errorlevel 1 (
    msg * "Error: Failed to assign I: to the Box folder."
    exit /b 1
)
echo Assigned I: to the Box workspace.
exit /b 0