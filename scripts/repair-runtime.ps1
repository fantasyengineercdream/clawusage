[CmdletBinding()]
param(
    [string]$SourceRoot = "",
    [string]$RuntimeRoot = "$env:USERPROFILE\.clawusage",
    [string]$WorkspaceSkillRoot = "$env:USERPROFILE\.openclaw\workspace\skills\clawusage",
    [string]$GlobalLauncherPath = "$env:APPDATA\npm\clawusage.cmd",
    [switch]$KeepLegacyTask
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Split-Path -Parent $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
        $SourceRoot = Split-Path -Parent $PSCommandPath
    }
}

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "SourceRoot not found: $SourceRoot"
}

Write-Host "Sync runtime files..." -ForegroundColor Cyan
$null = New-Item -ItemType Directory -Path $RuntimeRoot -Force

$rcArgs = @(
    $SourceRoot,
    $RuntimeRoot,
    "/MIR",
    "/XD", ".git", ".openclaw-state", ".publish-repo",
    "/XF", "clawusage.zip", "clawusage-test.zip",
    "/R:1", "/W:1"
)
& robocopy @rcArgs | Out-Host
if ($LASTEXITCODE -gt 7) {
    throw "robocopy failed with exit code $LASTEXITCODE"
}

Write-Host "Sync workspace skill..." -ForegroundColor Cyan
$skillSrc = Join-Path $SourceRoot "skills\clawusage\SKILL.md"
if (-not (Test-Path -LiteralPath $skillSrc)) {
    throw "Skill source not found: $skillSrc"
}
$null = New-Item -ItemType Directory -Path $WorkspaceSkillRoot -Force
$skillDst = Join-Path $WorkspaceSkillRoot "SKILL.md"
Copy-Item -LiteralPath $skillSrc -Destination $skillDst -Force

Write-Host "Write global launcher..." -ForegroundColor Cyan
$launcherDir = Split-Path -Parent $GlobalLauncherPath
if (-not (Test-Path -LiteralPath $launcherDir)) {
    $null = New-Item -ItemType Directory -Path $launcherDir -Force
}
$clawusageScript = Join-Path $RuntimeRoot "scripts\clawusage.ps1"
$launcher = @"
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "$clawusageScript" %*
endlocal
"@
Set-Content -LiteralPath $GlobalLauncherPath -Value $launcher -Encoding ASCII

if (-not $KeepLegacyTask) {
    $legacyTask = Get-ScheduledTask -TaskName "OpenClawIdleUsagePopup" -ErrorAction SilentlyContinue
    if ($null -ne $legacyTask) {
        Write-Host "Remove legacy task OpenClawIdleUsagePopup..." -ForegroundColor Cyan
        Unregister-ScheduledTask -TaskName "OpenClawIdleUsagePopup" -Confirm:$false
    }
}

$cmd = Get-Command clawusage.cmd -ErrorAction SilentlyContinue
if ($null -eq $cmd) {
    Write-Warning "clawusage.cmd not found in current PATH process. New terminal session may be needed."
} else {
    Write-Host ("clawusage command: {0}" -f $cmd.Source) -ForegroundColor Green
}

Write-Host ""
Write-Host "Runtime repair complete." -ForegroundColor Green
Write-Host ("SourceRoot:       {0}" -f $SourceRoot)
Write-Host ("RuntimeRoot:      {0}" -f $RuntimeRoot)
Write-Host ("Workspace skill:  {0}" -f $skillDst)
Write-Host ("Global launcher:  {0}" -f $GlobalLauncherPath)
