@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run.ps1" desktop %*
set "LAB_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %LAB_EXIT%
