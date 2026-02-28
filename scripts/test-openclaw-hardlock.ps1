[CmdletBinding()]
param(
    [string]$BotUser = "openclaw_bot",
    [string]$WorkspacePath = (Get-Location).Path,
    [string]$StatePath = (Join-Path (Get-Location).Path ".openclaw-state")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$failures = @()
$computerBot = "$env:COMPUTERNAME\$BotUser"

function Add-Failure([string]$msg) {
    $script:failures += $msg
}

function Test-Contains([string]$text, [string]$needle) {
    return $text -like "*$needle*"
}

try {
    $u = Get-LocalUser -Name $BotUser -ErrorAction Stop
    Write-Host "[OK] Local user exists: $BotUser"
} catch {
    Add-Failure "Local user missing: $BotUser"
}

try {
    $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
    if ($admins.Name -contains $computerBot) {
        Add-Failure "$computerBot is in Administrators"
    } else {
        Write-Host "[OK] Bot user is not in Administrators"
    }
} catch {
    Add-Failure "Failed to inspect Administrators group: $($_.Exception.Message)"
}

try {
    $netInfo = (& net user $BotUser | Out-String)
    if (Test-Contains $netInfo "Password required            Yes") {
        Write-Host "[OK] Password required is Yes"
    } else {
        Add-Failure "Password required is not Yes for $BotUser"
    }
} catch {
    Add-Failure "Failed to read password requirement: $($_.Exception.Message)"
}

if (-not (Test-Path -LiteralPath $WorkspacePath)) {
    Add-Failure "Workspace path missing: $WorkspacePath"
} else {
    $acl = (& icacls $WorkspacePath | Out-String)
    if (Test-Contains $acl $BotUser) {
        Write-Host "[OK] Workspace ACL contains bot user"
    } else {
        Add-Failure "Workspace ACL does not contain $BotUser"
    }
}

if (-not (Test-Path -LiteralPath $StatePath)) {
    Add-Failure "State path missing: $StatePath"
} else {
    $acl = (& icacls $StatePath | Out-String)
    if (Test-Contains $acl $BotUser) {
        Write-Host "[OK] State ACL contains bot user"
    } else {
        Add-Failure "State ACL does not contain $BotUser"
    }
}

if (Get-Command openclaw -ErrorAction SilentlyContinue) {
    Write-Host "[OK] openclaw command found"
} else {
    Add-Failure "openclaw command not found in PATH"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Validation failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host ""
Write-Host "Validation passed." -ForegroundColor Green
