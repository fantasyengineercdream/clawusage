@echo off
setlocal
set ROOT=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\apply-openclaw-hardlock-elevated.ps1"
endlocal
