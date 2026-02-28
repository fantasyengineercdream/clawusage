@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\uninstall-idle-usage-task.ps1" %*
endlocal
