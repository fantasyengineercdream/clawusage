@echo off
setlocal
if "%~1"=="" (
  echo Usage: %~nx0 ^<IdleMinutes^>
  echo Example: %~nx0 15
  exit /b 1
)
call "%~dp0clawusage.cmd" auto set %1
endlocal
