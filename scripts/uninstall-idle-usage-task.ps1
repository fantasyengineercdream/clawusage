[CmdletBinding()]
param(
    [string]$TaskName = "OpenClawIdleUsagePopup"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "Unregister-ScheduledTask cmdlet not found on this system."
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -eq $task) {
    Write-Host "Scheduled task not found: $TaskName"
    exit 0
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

Write-Host "Removed scheduled task: $TaskName"
