@echo off
rem Double-click to set up the AgriEvidence demo on Windows (see setup.ps1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
pause
