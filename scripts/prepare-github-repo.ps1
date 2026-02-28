[CmdletBinding()]
param(
    [string]$OutputDir = "$env:TEMP\openclaw-windows-hardlock-publish",
    [switch]$Force,
    [string]$Branch = "main"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$zipName = "openclaw-windows-hardlock.zip"
$outputResolved = [System.IO.Path]::GetFullPath($OutputDir)
$rootResolved = [System.IO.Path]::GetFullPath($root)

if (Test-Path -LiteralPath $OutputDir) {
    if (-not $Force) {
        throw "Output directory exists: $OutputDir. Use -Force to recreate."
    }
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$exclude = @(".openclaw-state", ".git", ".publish-repo", $zipName)
$items = Get-ChildItem -LiteralPath $root -Force | Where-Object {
    if ($exclude -contains $_.Name) { return $false }
    $itemResolved = [System.IO.Path]::GetFullPath($_.FullName)
    if ($itemResolved -eq $outputResolved) { return $false }
    if ($outputResolved.StartsWith($rootResolved) -and $itemResolved.StartsWith($outputResolved)) { return $false }
    return $true
}

foreach ($item in $items) {
    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $OutputDir $item.Name) -Recurse -Force
}

Push-Location $OutputDir
try {
    $gitVersion = (& git --version 2>$null | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($gitVersion)) {
        throw "git not found in PATH."
    }

    & git init -b $Branch 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & git init | Out-Null
        & git checkout -b $Branch | Out-Null
    }

    $userName = (& git config user.name | Out-String).Trim()
    $userEmail = (& git config user.email | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($userName)) { & git config user.name "openclaw-publisher" | Out-Null }
    if ([string]::IsNullOrWhiteSpace($userEmail)) { & git config user.email "openclaw-publisher@local" | Out-Null }

    & git add -A | Out-Null
    & git commit -m "Initial release: OpenClaw Windows Hardlock + ClawUsage" | Out-Null

    Write-Host "Prepared standalone repo:" -ForegroundColor Green
    Write-Host "  $OutputDir"
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  cd '$OutputDir'"
    Write-Host "  git remote add origin <YOUR_GITHUB_REPO_URL>"
    Write-Host "  git push -u origin $Branch"
}
finally {
    Pop-Location
}
