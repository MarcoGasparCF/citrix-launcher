@echo off
setlocal DisableDelayedExpansion
title Instalar Citrix Launcher
set "installDir=%USERPROFILE%\apps"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Instalar.ps1" -Destination "%installDir%"
if errorlevel 1 goto failed

pushd "%installDir%" || goto failed
call ".\updatePassword.bat"
set "result=%errorlevel%"
popd
if not "%result%"=="0" goto failed

echo.
echo Instalacao concluida em "%installDir%".
echo Execute OpenCitrix.bat para iniciar o Citrix Launcher.
pause
exit /b 0

:failed
echo.
echo A instalacao nao foi concluida. Verifique as mensagens acima.
pause
exit /b 1
