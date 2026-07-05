@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai-pip.ps1" %*
exit /b %ERRORLEVEL%
