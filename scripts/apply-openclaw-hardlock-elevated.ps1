param(
    [string]$WorkspacePath = (Get-Location).Path,
    [string]$StatePath = (Join-Path (Get-Location).Path ".openclaw-state"),
    [string]$BotUser = "openclaw_bot",
    [string]$BotPassword = "",
    [switch]$SkipSiblingDeny,
    [switch]$InteractiveConfirm
)

$scriptPath = Join-Path $PSScriptRoot "setup-openclaw-hardlock.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing script: $scriptPath"
}

$argList = @(
    "-NoProfile"
    "-ExecutionPolicy"
    "Bypass"
    "-File"
    "`"$scriptPath`""
    "-WorkspacePath"
    "`"$WorkspacePath`""
    "-StatePath"
    "`"$StatePath`""
    "-BotUser"
    "`"$BotUser`""
)

if (-not $InteractiveConfirm) {
    # Disable repeated Y/N prompts in elevated setup unless explicitly requested.
    $argList += "-Confirm:`$false"
}

if (-not [string]::IsNullOrWhiteSpace($BotPassword)) {
    $argList += @("-BotPassword", "`"$BotPassword`"")
}
if ($SkipSiblingDeny) {
    $argList += "-SkipSiblingDeny"
}

$joined = $argList -join " "
Write-Host "Launching elevated setup..."
$proc = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $joined -Wait -PassThru
if ($proc.ExitCode -eq 0) {
    Write-Host "Hardlock setup completed successfully."
    exit 0
}

Write-Error "Hardlock setup failed with exit code $($proc.ExitCode)."
exit $proc.ExitCode
