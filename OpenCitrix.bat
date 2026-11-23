@echo off
title CELFOCUS - Projeto CGA - Citrix
echo.
echo   ####  #####  #####  ####   #####  #   #
echo  #        #      #    #   #    #     # #
echo  #        #      #    ####     #      #
echo  #        #      #    #  #     #     # #
echo   ####  #####    #    #   #  #####  #   #
echo.
echo             CELFOCUS - Projeto CGA
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CitrixLauncher.ps1"
if errorlevel 1 pause