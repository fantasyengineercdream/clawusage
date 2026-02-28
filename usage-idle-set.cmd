@echo off
setlocal
if "%~1"=="" (
  echo Usage: %~nx0 ^<IdleMinutes^> [extra-args...]
  echo Example: %~nx0 15 -IntervalMinutes 1 -IncludeLocalTokens
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-idle-usage-task.ps1" -IdleMinutes %1 %2 %3 %4 %5 %6 %7 %8 %9
endlocal
