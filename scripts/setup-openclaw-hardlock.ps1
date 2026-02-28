[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [string]$BotUser = "openclaw_bot",
    [string]$WorkspacePath = (Get-Location).Path,
    [string]$StatePath = (Join-Path (Get-Location).Path ".openclaw-state"),
    [string]$BotPassword = "",
    [switch]$SkipSiblingDeny
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-RandomPassword {
    param([int]$Length = 24)
    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*_-+=?"
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] ($Length)
    $rng.GetBytes($bytes)
    $buffer = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) {
        [void]$buffer.Append($chars[$b % $chars.Length])
    }
    return $buffer.ToString()
}

function Invoke-IcaclsGrant {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Principal,
        [Parameter(Mandatory = $true)][string]$Perm
    )
    & icacls $Path /grant "${Principal}:$Perm" /T /C | Out-Null
}

function Invoke-IcaclsDeny {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Principal,
        [Parameter(Mandatory = $true)][string]$Perm
    )
    & icacls $Path /deny "${Principal}:$Perm" /T /C | Out-Null
}

if (-not $WhatIfPreference -and -not (Test-IsAdmin)) {
    throw "Administrator is required for ACL/user changes. Re-run in elevated PowerShell, or first run with -WhatIf."
}

if (-not (Test-Path -LiteralPath $WorkspacePath)) {
    throw "Workspace not found: $WorkspacePath"
}

if (-not (Test-Path -LiteralPath $StatePath)) {
    if ($PSCmdlet.ShouldProcess($StatePath, "Create state directory")) {
        New-Item -ItemType Directory -Path $StatePath -Force | Out-Null
    }
}

$workspace = [System.IO.Path]::GetFullPath($WorkspacePath)
$state = [System.IO.Path]::GetFullPath($StatePath)
$botPrincipal = "$env:COMPUTERNAME\$BotUser"
$generatedPassword = $null

$existingUser = Get-LocalUser -Name $BotUser -ErrorAction SilentlyContinue
if (-not $existingUser) {
    if ($PSCmdlet.ShouldProcess("LocalUser:$BotUser", "Create local user")) {
        if ([string]::IsNullOrWhiteSpace($BotPassword)) {
            $BotPassword = New-RandomPassword
            $generatedPassword = $BotPassword
        }
        $secure = ConvertTo-SecureString $BotPassword -AsPlainText -Force
        New-LocalUser -Name $BotUser -Password $secure -PasswordNeverExpires -UserMayNotChangePassword -AccountNeverExpires -Description "Constrained account for OpenClaw automation" | Out-Null
        Write-Host "Created local user: $BotUser"
    }
} else {
    Write-Host "Local user already exists: $BotUser"
}

if ($PSCmdlet.ShouldProcess("LocalUser:$BotUser", "Require password for account")) {
    & net user $BotUser /passwordreq:yes | Out-Null
}

if ($PSCmdlet.ShouldProcess("Administrators", "Ensure $BotUser is not in local Administrators")) {
    try {
        Remove-LocalGroupMember -Group "Administrators" -Member $BotUser -ErrorAction Stop
        Write-Host "Removed $BotUser from Administrators."
    } catch {
        Write-Host "$BotUser is not in Administrators (ok)."
    }
}

$openclawCmd = Get-Command openclaw -ErrorAction SilentlyContinue
$allowModify = @($workspace, $state) | Select-Object -Unique

foreach ($path in $allowModify) {
    if ($PSCmdlet.ShouldProcess($path, "Grant modify to $botPrincipal")) {
        Invoke-IcaclsGrant -Path $path -Principal $botPrincipal -Perm "(OI)(CI)M"
    }
}

if ($openclawCmd) {
    $openclawBin = (Split-Path -Parent $openclawCmd.Source)
    $openclawModule = Join-Path $openclawBin "node_modules\openclaw"
    $allowReadExecute = @($openclawBin)
    if (Test-Path -LiteralPath $openclawModule) {
        $allowReadExecute += $openclawModule
    }
    $allowReadExecute = $allowReadExecute | Select-Object -Unique
    foreach ($path in $allowReadExecute) {
        if ($PSCmdlet.ShouldProcess($path, "Grant read/execute to $botPrincipal")) {
            Invoke-IcaclsGrant -Path $path -Principal $botPrincipal -Perm "(OI)(CI)RX"
        }
    }
}

if (-not $SkipSiblingDeny) {
    $parent = Split-Path -Parent $workspace
    if (Test-Path -LiteralPath $parent) {
        $siblings = Get-ChildItem -LiteralPath $parent -Directory | Where-Object { $_.FullName -ne $workspace }
        if (($siblings | Measure-Object).Count -eq 0) {
            Write-Host "No sibling directories found under parent '$parent'; sibling deny step skipped."
        }
        foreach ($dir in $siblings) {
            if ($PSCmdlet.ShouldProcess($dir.FullName, "Deny full access to $botPrincipal")) {
                Invoke-IcaclsDeny -Path $dir.FullName -Principal $botPrincipal -Perm "(OI)(CI)F"
            }
        }
    }
}

Write-Host ""
Write-Host "Done."
Write-Host "Workspace : $workspace"
Write-Host "StatePath : $state"
Write-Host "Bot user  : $botPrincipal"
if ($generatedPassword) {
    Write-Host "Generated password (save now): $generatedPassword"
}
Write-Host ""
Write-Host "Smoke test (manual):"
Write-Host "  runas /user:$botPrincipal `"powershell -NoProfile -Command `"Get-ChildItem -LiteralPath '$workspace' | Select-Object -First 3`"`""
Write-Host "Forbidden path test (manual):"
Write-Host "  runas /user:$botPrincipal `"powershell -NoProfile -Command `"Get-ChildItem -LiteralPath '$env:USERPROFILE'`"`""
Write-Host "OpenClaw shell (manual):"
Write-Host "  runas /user:$botPrincipal `"powershell -NoProfile -NoExit -Command `"`$env:OPENCLAW_STATE_DIR='$state'; `$env:OPENCLAW_CONFIG_PATH='$state\\openclaw.json'; Set-Location -LiteralPath '$workspace'; openclaw`"`""
