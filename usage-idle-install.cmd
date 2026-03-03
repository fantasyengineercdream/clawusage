@echo off
setlocal
set IDLE=%~1
if "%IDLE%"=="" set IDLE=10
set INTERVAL=%~2
if "%INTERVAL%"=="" set INTERVAL=5
call "%~dp0clawusage.cmd" auto on %IDLE% --interval %INTERVAL%
endlocal
