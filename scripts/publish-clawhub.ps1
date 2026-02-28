[CmdletBinding()]
param(
    [string]$SkillPath = "",
    [string]$Slug = "clawusage-windows-hardlock",
    [string]$Name = "ClawUsage Windows Hardlock",
    [string]$Version = "0.1.0",
    [string]$Tags = "latest,windows,openclaw",
    [string]$Changelog = "Initial public release.",
    [switch]$LoginIfNeeded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SkillPath)) {
    $SkillPath = Join-Path (Split-Path -Parent $PSScriptRoot) "skills\clawusage"
}

if (-not (Test-Path -LiteralPath $SkillPath)) {
    throw "Skill path not found: $SkillPath"
}

Write-Host "Checking ClawHub login..."
& npx clawhub whoami
if ($LASTEXITCODE -ne 0) {
    if (-not $LoginIfNeeded) {
        throw "Not logged in. Run: npx clawhub login (or re-run with -LoginIfNeeded)."
    }
    Write-Host "Running login flow..."
    & npx clawhub login
    if ($LASTEXITCODE -ne 0) {
        throw "Login failed."
    }
}

Write-Host "Publishing skill..."
& npx clawhub publish "$SkillPath" --slug "$Slug" --name "$Name" --version "$Version" --tags "$Tags" --changelog "$Changelog"
if ($LASTEXITCODE -ne 0) {
    throw "ClawHub publish failed."
}

Write-Host "ClawHub publish completed." -ForegroundColor Green