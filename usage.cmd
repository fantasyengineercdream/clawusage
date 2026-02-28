@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\openclaw-usage-monitor.ps1" %*
endlocal
