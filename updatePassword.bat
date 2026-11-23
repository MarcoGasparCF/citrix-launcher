@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CitrixLauncher.ps1" -SetPassword
set "result=%errorlevel%"
pause
exit /b %result%