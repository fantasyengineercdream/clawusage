[CmdletBinding()]
param(
    [string]$SkillPath = "",
    [string]$Slug = "clawusage-windows-hardlock",
    [string]$Name = "ClawUsage Windows Hardlock",
    [string]$Version = "0.1.4",
    [string]$Tags = "latest,windows,openclaw",
    [string]$Changelog = "Improve chat readability with action-specific compact output templates.",
    [switch]$LoginIfNeeded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ClawHubCommand {
    $cmd = Get-Command clawhub -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return "clawhub" }
    return "npx clawhub"
}

function Invoke-ClawHub {
    param([string[]]$Arguments)
    $runner = Get-ClawHubCommand
    if ($runner -eq "clawhub") {
        & clawhub @Arguments
    } else {
        & npx clawhub @Arguments
    }
}

if ([string]::IsNullOrWhiteSpace($SkillPath)) {
    $SkillPath = Join-Path (Split-Path -Parent $PSScriptRoot) "skills\clawusage"
}

if (-not (Test-Path -LiteralPath $SkillPath)) {
    throw "Skill path not found: $SkillPath"
}

Write-Host "Checking ClawHub login..."
Invoke-ClawHub -Arguments @("whoami")
if ($LASTEXITCODE -ne 0) {
    if (-not $LoginIfNeeded) {
        throw "Not logged in. Run: clawhub login (or re-run with -LoginIfNeeded)."
    }
    Write-Host "Running login flow..."
    Invoke-ClawHub -Arguments @("login")
    if ($LASTEXITCODE -ne 0) {
        throw "Login failed."
    }
}

Write-Host "Publishing skill..."
Invoke-ClawHub -Arguments @("publish", "$SkillPath", "--slug", "$Slug", "--name", "$Name", "--version", "$Version", "--tags", "$Tags", "--changelog", "$Changelog")
if ($LASTEXITCODE -ne 0) {
    throw "ClawHub publish failed."
}

Write-Host "ClawHub publish completed." -ForegroundColor Green
