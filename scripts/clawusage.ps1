[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$taskName = "ClawUsageAuto"
$monitorScript = Join-Path $PSScriptRoot "openclaw-usage-monitor.ps1"
$workerScript = Join-Path $PSScriptRoot "clawusage-auto-worker.ps1"
$stateDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.openclaw-state"))
$configPath = Join-Path $stateDir "clawusage-config.json"
$workerStatePath = Join-Path $stateDir "clawusage-auto-state.json"
$sessionsPath = "$env:USERPROFILE\.openclaw\agents\main\sessions\sessions.json"

if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

function Show-Help {
    Write-Host "clawusage (KISS mode)"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  clawusage now"
    Write-Host "  clawusage auto on [minutes] [--interval N]"
    Write-Host "  clawusage auto set <minutes>"
    Write-Host "  clawusage auto off"
    Write-Host "  clawusage auto status"
}

function Get-Config {
    if (Test-Path -LiteralPath $configPath) {
        try { return (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json) } catch {}
    }
    return [pscustomobject]@{
        idleMinutes = 10
        intervalMinutes = 1
        includeLocalTokens = $true
        provider = "openai-codex"
        taskName = $taskName
    }
}

function Save-Config {
    param([Parameter(Mandatory = $true)]$Config)
    $Config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
}

function Quote-Arg {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Install-AutoTask {
    param([Parameter(Mandatory = $true)]$Config)

    if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
        throw "Register-ScheduledTask cmdlet not found on this system."
    }

    $argParts = @(
        "-WindowStyle Hidden",
        "-NoProfile",
        "-ExecutionPolicy Bypass",
        ("-File {0}" -f (Quote-Arg -Value $workerScript)),
        ("-IdleMinutes {0}" -f [int]$Config.idleMinutes),
        ("-Provider {0}" -f (Quote-Arg -Value ([string]($Config.provider)))),
        ("-SessionsFile {0}" -f (Quote-Arg -Value $sessionsPath)),
        ("-StateFile {0}" -f (Quote-Arg -Value $workerStatePath))
    )
    if ([bool]$Config.includeLocalTokens) {
        $argParts += "-IncludeLocalTokens"
    }
    $taskArgs = $argParts -join " "

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes ([int]$Config.intervalMinutes)) -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "clawusage idle reminder (send to latest OpenClaw chat)." -Force | Out-Null
}

function Remove-AutoTask {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -eq $task) { return }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

function Show-Status {
    $config = Get-Config
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
    Write-Host ("task: {0}" -f $taskName)
    Write-Host ("enabled: {0}" -f ($(if ($null -ne $task) { "on" } else { "off" })))
    Write-Host ("idleMinutes: {0}" -f [int]$config.idleMinutes)
    Write-Host ("intervalMinutes: {0}" -f [int]$config.intervalMinutes)
    if ($null -ne $task) {
        Write-Host ("state: {0}" -f [string]$task.State)
    }
    if ($null -ne $taskInfo) {
        Write-Host ("lastRun: {0}" -f $taskInfo.LastRunTime)
        Write-Host ("nextRun: {0}" -f $taskInfo.NextRunTime)
        Write-Host ("lastResult: {0}" -f $taskInfo.LastTaskResult)
    }
}

function Parse-Interval {
    param([string[]]$Tokens, [int]$Default = 1)
    $interval = $Default
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        if ($Tokens[$i] -eq "--interval" -and ($i + 1) -lt $Tokens.Count) {
            [void][int]::TryParse($Tokens[$i + 1], [ref]$interval)
        }
    }
    if ($interval -lt 1) { $interval = 1 }
    if ($interval -gt 30) { $interval = 30 }
    return $interval
}

if (-not (Test-Path -LiteralPath $monitorScript)) {
    throw "Missing script: $monitorScript"
}
if (-not (Test-Path -LiteralPath $workerScript)) {
    throw "Missing script: $workerScript"
}

$cmd = if ($Args.Count -gt 0) { $Args[0].ToLowerInvariant() } else { "now" }

switch ($cmd) {
    "help" {
        Show-Help
        exit 0
    }
    "now" {
        $json = $false
        if ($Args.Count -gt 1 -and $Args[1] -eq "--json") {
            $json = $true
        }
        if ($json) {
            & $monitorScript -IncludeLocalTokens -Json
        } else {
            & $monitorScript -IncludeLocalTokens
        }
        exit 0
    }
    "auto" {
        if ($Args.Count -lt 2) {
            Show-Help
            exit 1
        }
        $sub = $Args[1].ToLowerInvariant()
        switch ($sub) {
            "on" {
                $config = Get-Config
                if ($Args.Count -ge 3) {
                    $tmp = 0
                    if ([int]::TryParse($Args[2], [ref]$tmp) -and $tmp -ge 1) {
                        $config.idleMinutes = $tmp
                    }
                }
                $config.intervalMinutes = Parse-Interval -Tokens $Args -Default ([int]$config.intervalMinutes)
                Save-Config -Config $config
                Install-AutoTask -Config $config
                Write-Host ("auto: on (idle={0}m, interval={1}m)" -f [int]$config.idleMinutes, [int]$config.intervalMinutes)
                exit 0
            }
            "set" {
                if ($Args.Count -lt 3) {
                    throw "Usage: clawusage auto set <minutes>"
                }
                $minutes = 0
                if (-not [int]::TryParse($Args[2], [ref]$minutes) -or $minutes -lt 1) {
                    throw "Idle minutes must be an integer >= 1."
                }
                $config = Get-Config
                $config.idleMinutes = $minutes
                Save-Config -Config $config
                $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                if ($null -ne $task) {
                    Install-AutoTask -Config $config
                    Write-Host ("auto: threshold updated to {0}m (task reloaded)" -f $minutes)
                } else {
                    Write-Host ("auto: threshold saved ({0}m). run clawusage auto on to enable." -f $minutes)
                }
                exit 0
            }
            "off" {
                Remove-AutoTask
                Write-Host "auto: off"
                exit 0
            }
            "status" {
                Show-Status
                exit 0
            }
            default {
                Show-Help
                exit 1
            }
        }
    }
    default {
        Show-Help
        exit 1
    }
}
