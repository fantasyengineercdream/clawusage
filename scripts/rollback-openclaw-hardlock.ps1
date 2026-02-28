[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [string]$BotUser = "openclaw_bot",
    [string]$WorkspacePath = (Get-Location).Path,
    [string]$StatePath = (Join-Path (Get-Location).Path ".openclaw-state"),
    [switch]$RemoveUser,
    [switch]$RemoveStatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $WhatIfPreference -and -not (Test-IsAdmin)) {
    throw "Administrator is required for rollback changes."
}

$workspace = [System.IO.Path]::GetFullPath($WorkspacePath)
$state = [System.IO.Path]::GetFullPath($StatePath)
$principal = "$env:COMPUTERNAME\$BotUser"

$paths = @()
if (Test-Path -LiteralPath $workspace) { $paths += $workspace }
if (Test-Path -LiteralPath $state) { $paths += $state }

foreach ($p in ($paths | Select-Object -Unique)) {
    if ($PSCmdlet.ShouldProcess($p, "Remove explicit ACL entries for $principal")) {
        & icacls $p /remove "$principal" /T /C | Out-Null
        & icacls $p /remove:d "$principal" /T /C | Out-Null
    }
}

$parent = Split-Path -Parent $workspace
if (Test-Path -LiteralPath $parent) {
    $siblings = Get-ChildItem -LiteralPath $parent -Directory | Where-Object { $_.FullName -ne $workspace }
    foreach ($dir in $siblings) {
        if ($PSCmdlet.ShouldProcess($dir.FullName, "Remove deny ACL for $principal")) {
            & icacls $dir.FullName /remove:d "$principal" /T /C | Out-Null
        }
    }
}

if ($RemoveStatePath -and (Test-Path -LiteralPath $state)) {
    if ($PSCmdlet.ShouldProcess($state, "Delete state path")) {
        Remove-Item -LiteralPath $state -Recurse -Force
    }
}

if ($RemoveUser) {
    $u = Get-LocalUser -Name $BotUser -ErrorAction SilentlyContinue
    if ($u) {
        if ($PSCmdlet.ShouldProcess("LocalUser:$BotUser", "Delete user")) {
            Remove-LocalUser -Name $BotUser
        }
    }
}

Write-Host "Rollback complete."
