@echo off
rem Double-click to start the AgriEvidence demo (see start-demo.ps1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-demo.ps1" %*
if errorlevel 1 pause
