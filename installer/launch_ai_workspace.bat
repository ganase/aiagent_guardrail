@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem AI Agent workspace launcher
rem Expected Box folder layout:
rem   <TARGET_DIR>\Operation\<repository>
rem   <TARGET_DIR>\Sandbox\<Windows-user-name>\<repository>
rem The selected target folder comes from config\box_mount.local.cmd.
rem This file is written by configure_box_mount.ps1 when configured. Set
rem AI_WORKSPACE_BOX_TARGET to override it without touching that file. Set
rem AI_WORKSPACE_SANDBOX_USER only when the
rem sandbox folder name intentionally differs from the Windows logon name.

set "TARGET_DIR="
set "LOCAL_CONFIG=%~dp0..\config\box_mount.local.cmd"
rem Ask for the Box folder only until the per-user configuration has been saved.
if not exist "%LOCAL_CONFIG%" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0configure_box_mount.ps1" -ConfigPath "%LOCAL_CONFIG%"
if exist "%LOCAL_CONFIG%" call "%LOCAL_CONFIG%"
rem An absent file or BOX_ENABLED=0 leaves these values unset.
set "BOX_TARGET=%AI_WORKSPACE_BOX_TARGET%"
if not defined BOX_TARGET if defined TARGET_DIR set "BOX_TARGET=%TARGET_DIR%"
if not defined BOX_TARGET call :ResolveBoxTarget
set "SANDBOX_USER=%AI_WORKSPACE_SANDBOX_USER%"
if not defined SANDBOX_USER set "SANDBOX_USER=%USERNAME%"

call :EnsureBoxTarget
if errorlevel 1 goto :End
call :ChooseTool
if errorlevel 1 goto :End
call :ChooseArea
if errorlevel 1 goto :End
call :ChooseRepository "%WORKSPACE_ROOT%"
if errorlevel 1 goto :End

echo.
echo Starting %TOOL_NAME% in:
echo   %SELECTED_REPOSITORY%
echo.
pushd "%SELECTED_REPOSITORY%" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Could not enter the selected folder.
    goto :End
)
set "AI_AGENT_AUDIT_ROOT=%BOX_TARGET%\Sandbox\%SANDBOX_USER%\CodingAgentForIT-Audit"
call :SyncAuditLogs
if /i "%TOOL_COMMAND%"=="codex" (
    call codex --cd "%SELECTED_REPOSITORY%"
) else (
    call claude
)
set "TOOL_EXIT_CODE=!ERRORLEVEL!"
call :SyncAuditLogs
popd
exit /b !TOOL_EXIT_CODE!
goto :End


:SyncAuditLogs
set "AUDIT_TOOL=ClaudeCode"
if /i "%TOOL_COMMAND%"=="codex" set "AUDIT_TOOL=Codex"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync_ai_agent_logs.ps1" ^
  -Tool "%AUDIT_TOOL%" -BoxTarget "%BOX_TARGET%" -SandboxUser "%SANDBOX_USER%"
if errorlevel 1 echo WARNING: %TOOL_NAME% audit-log synchronization failed. The local logs were not removed.
exit /b 0


rem Fallback only: used when box_mount.local.cmd is absent, for example before
rem configure_box_mount.ps1 has ever been run, and no override env var is set.
:ResolveBoxTarget
for %%P in (
    "%USERPROFILE%\Box"
    "%USERPROFILE%\Box Sync"
    "%USERPROFILE%\Box Drive"
    "%USERPROFILE%\Documents\Box"
) do (
    if not defined BOX_TARGET if exist "%%~fP" set "BOX_TARGET=%%~fP"
)
exit /b 0


:EnsureBoxTarget
if not defined BOX_TARGET (
    echo ERROR: The shared workspace folder could not be detected.
    echo Run installer\configure_box_mount.ps1 again, or set AI_WORKSPACE_BOX_TARGET
    echo to the exact local folder path.
    exit /b 1
)
if not exist "%BOX_TARGET%" (
    echo ERROR: Shared target folder was not found:
    echo   %BOX_TARGET%
    echo Start Box or your file-sync client, then make the folder available offline,
    echo or update AI_WORKSPACE_BOX_TARGET.
    exit /b 1
)

exit /b 0


:ChooseTool
echo.
echo Which AI coding tool do you want to start?
echo   [1] Codex
echo   [2] Claude Code
echo   [0] Exit
set "TOOL_SELECTION="
set /p "TOOL_SELECTION=Select: "
if "%TOOL_SELECTION%"=="1" (
    set "TOOL_NAME=Codex"
    set "TOOL_COMMAND=codex"
    exit /b 0
)
if "%TOOL_SELECTION%"=="2" (
    set "TOOL_NAME=Claude Code"
    set "TOOL_COMMAND=claude"
    exit /b 0
)
exit /b 1


:ChooseArea
echo.
echo Choose a workspace area:
echo   [1] Operation (shared repositories)
echo   [2] Sandbox (%SANDBOX_USER%)
echo   [0] Exit
set "AREA_SELECTION="
set /p "AREA_SELECTION=Select: "
if "%AREA_SELECTION%"=="1" set "WORKSPACE_ROOT=%BOX_TARGET%\Operation"
if "%AREA_SELECTION%"=="2" set "WORKSPACE_ROOT=%BOX_TARGET%\Sandbox\%SANDBOX_USER%"
if not defined WORKSPACE_ROOT exit /b 1
if not exist "%WORKSPACE_ROOT%" (
    if "%AREA_SELECTION%"=="2" (
        mkdir "%WORKSPACE_ROOT%" >nul 2>&1
        if errorlevel 1 (
            echo ERROR: Could not create the Sandbox folder:
            echo   %WORKSPACE_ROOT%
            exit /b 1
        )
        echo Created Sandbox folder:
        echo   %WORKSPACE_ROOT%
    ) else (
        echo ERROR: Workspace folder was not found:
        echo   %WORKSPACE_ROOT%
        exit /b 1
    )
)
exit /b 0


:ChooseRepository
set "REPOSITORY_ROOT=%~1"
:RepositoryMenu
set /a REPOSITORY_COUNT=0
echo.
echo Repositories in %REPOSITORY_ROOT%:
for /d %%D in ("%REPOSITORY_ROOT%\*") do (
    set /a REPOSITORY_COUNT+=1
    set "REPOSITORY[!REPOSITORY_COUNT!]=%%~fD"
    set "REPOSITORY_MARK="
    if exist "%%~fD\.git" set "REPOSITORY_MARK= [git]"
    echo   [!REPOSITORY_COUNT!] %%~nxD!REPOSITORY_MARK!
)
if !REPOSITORY_COUNT! EQU 0 echo   No repositories yet.
echo   [N] Create a new repository
echo   [0] Back / exit
set "REPOSITORY_SELECTION="
set /p "REPOSITORY_SELECTION=Select: "
if "%REPOSITORY_SELECTION%"=="0" exit /b 1
if /i "%REPOSITORY_SELECTION%"=="N" goto :CreateRepository
for /f "delims=0123456789" %%A in ("%REPOSITORY_SELECTION%") do goto :RepositoryMenu
if not defined REPOSITORY[%REPOSITORY_SELECTION%] goto :RepositoryMenu
for %%A in (!REPOSITORY_SELECTION!) do set "SELECTED_REPOSITORY=!REPOSITORY[%%A]!"
exit /b 0

:CreateRepository
echo.
set "NEW_REPOSITORY="
set /p "NEW_REPOSITORY=New repository name: "
if not defined NEW_REPOSITORY goto :RepositoryMenu
for %%A in ("%NEW_REPOSITORY%") do set "NEW_REPOSITORY=%%~nxA"
if "%NEW_REPOSITORY%"=="." goto :RepositoryMenu
if "%NEW_REPOSITORY%"==".." goto :RepositoryMenu
if exist "%REPOSITORY_ROOT%\%NEW_REPOSITORY%" (
    echo ERROR: That repository already exists.
    goto :RepositoryMenu
)
mkdir "%REPOSITORY_ROOT%\%NEW_REPOSITORY%" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Could not create the repository folder.
    goto :RepositoryMenu
)
set "SELECTED_REPOSITORY=%REPOSITORY_ROOT%\%NEW_REPOSITORY%"
echo Created repository:
echo   %SELECTED_REPOSITORY%
exit /b 0


:End
endlocal
