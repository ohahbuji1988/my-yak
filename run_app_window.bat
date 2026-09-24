@echo off
title Kidipedia App Launcher

if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" goto RUN_CHROME
if exist "C:\Program Files\Microsoft\Edge\Application\msedge.exe" goto RUN_EDGE
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" goto RUN_EDGE

start http://localhost:8080
exit /b

:RUN_CHROME
start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" --app=http://localhost:8080 --user-data-dir="%TEMP%\kidipedia_app" --window-size=420,915
exit /b

:RUN_EDGE
start "" msedge.exe --app=http://localhost:8080 --user-data-dir="%TEMP%\kidipedia_app" --window-size=420,915
exit /b
