[CmdletBinding()]
param(
    [string]$TaskName = "OpenClawIdleUsagePopup",
    [int]$IdleMinutes = 10,
    [int]$IntervalMinutes = 5,
    [string]$Provider = "openai-codex",
    [string]$SessionsFile = "$env:USERPROFILE\.openclaw\agents\main\sessions\sessions.json",
    [string]$StateFile = "",
    [switch]$IncludeLocalTokens
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "Register-ScheduledTask cmdlet not found on this system."
}

if ($IdleMinutes -lt 1) { throw "IdleMinutes must be >= 1." }
if ($IntervalMinutes -lt 1 -or $IntervalMinutes -gt 30) {
    throw "IntervalMinutes must be in range 1..30."
}

$idleScript = Join-Path $PSScriptRoot "openclaw-usage-idle-popup.ps1"
if (-not (Test-Path -LiteralPath $idleScript)) {
    throw "Missing script: $idleScript"
}

if ([string]::IsNullOrWhiteSpace($StateFile)) {
    $StateFile = Join-Path $PSScriptRoot "..\.openclaw-state\idle-usage-notify-state.json"
}

$statePath = [System.IO.Path]::GetFullPath($StateFile)
$stateDir = Split-Path -Parent $statePath
if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

function Quote-TaskArg {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

$argParts = @(
    "-WindowStyle Hidden",
    "-NoProfile",
    "-ExecutionPolicy Bypass",
    ("-File {0}" -f (Quote-TaskArg -Value $idleScript)),
    ("-IdleMinutes {0}" -f $IdleMinutes),
    ("-Provider {0}" -f (Quote-TaskArg -Value $Provider)),
    ("-SessionsFile {0}" -f (Quote-TaskArg -Value $SessionsFile)),
    ("-StateFile {0}" -f (Quote-TaskArg -Value $statePath))
)
if ($IncludeLocalTokens) {
    $argParts += "-IncludeLocalTokens"
}
$taskCommand = "powershell.exe " + ($argParts -join " ")
$taskArgs = $argParts -join " "

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "OpenClaw idle usage popup monitor (no model inference)." -Force | Out-Null

Write-Host "Installed scheduled task: $TaskName"
Write-Host "Check interval: every $IntervalMinutes minute(s)"
Write-Host "Idle threshold: $IdleMinutes minute(s)"
Write-Host "Task command:"
Write-Host "  $taskCommand"
Write-Host ""
Write-Host "List task:"
Write-Host "  Get-ScheduledTask -TaskName `"$TaskName`" | Format-List *"
