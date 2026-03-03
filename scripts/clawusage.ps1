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
if ($null -eq $Args) {
    $Args = @()
}

function Show-Help {
    Write-Host "clawusage (KISS mode)"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  clawusage                     (same as help)"
    Write-Host "  clawusage now [live|--live]"
    Write-Host "  clawusage status [live|--live]"
    Write-Host "  clawusage lang [english|chinese]"
    Write-Host "  clawusage auto on [minutes] [--interval N]   (default interval: 5)"
    Write-Host "  clawusage auto set <minutes>"
    Write-Host "  clawusage auto off"
    Write-Host "  clawusage auto status"
    Write-Host "  clawusage -help | --help | -h"
}

function Show-FirstRunLanguageHint {
    Write-Host ""
    Write-Host "Language setup:"
    Write-Host "  EN: use 'clawusage lang english' or 'clawusage lang chinese'."
    Write-Host "  ZH-CN: use 'clawusage lang chinese' to switch to Chinese output."
}

function Normalize-Language {
    param([string]$Language)
    if ([string]::IsNullOrWhiteSpace($Language)) { return "english" }
    $v = $Language.Trim().ToLowerInvariant()
    switch ($v) {
        "en" { return "english" }
        "english" { return "english" }
        "zh" { return "chinese" }
        "cn" { return "chinese" }
        "chinese" { return "chinese" }
        default { throw "Unsupported language: $Language. Use english or chinese." }
    }
}

function Ensure-ConfigProperty {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$DefaultValue
    )
    if (-not ($Config.PSObject.Properties.Name -contains $Name)) {
        $Config | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue
    }
}

function Get-Config {
    $config = $null
    $needsPersist = $false
    if (Test-Path -LiteralPath $configPath) {
        try { $config = (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json) } catch {}
    }
    if ($null -eq $config) {
        $config = [pscustomobject]@{
            idleMinutes = 10
            intervalMinutes = 5
            includeLocalTokens = $true
            provider = "openai-codex"
            language = "english"
            configVersion = 2
            onboardingShown = $false
            taskName = $taskName
        }
    }

    Ensure-ConfigProperty -Config $config -Name "idleMinutes" -DefaultValue 10
    Ensure-ConfigProperty -Config $config -Name "intervalMinutes" -DefaultValue 5
    Ensure-ConfigProperty -Config $config -Name "includeLocalTokens" -DefaultValue $true
    Ensure-ConfigProperty -Config $config -Name "provider" -DefaultValue "openai-codex"
    Ensure-ConfigProperty -Config $config -Name "language" -DefaultValue "english"
    Ensure-ConfigProperty -Config $config -Name "configVersion" -DefaultValue 1
    Ensure-ConfigProperty -Config $config -Name "onboardingShown" -DefaultValue $false
    Ensure-ConfigProperty -Config $config -Name "taskName" -DefaultValue $taskName

    # One-time migration: old versions defaulted to 1m checks, which is too noisy.
    if ([int]$config.configVersion -lt 2) {
        if ([int]$config.intervalMinutes -eq 1) {
            $config.intervalMinutes = 5
        }
        $config.configVersion = 2
        $needsPersist = $true
    }

    $config.language = Normalize-Language -Language ([string]$config.language)
    if ($needsPersist) {
        $config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
    }
    return $config
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
        ("-Language {0}" -f (Quote-Arg -Value ([string]($Config.language)))),
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
    Write-Host ("language: {0}" -f [string]$config.language)
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
    param([string[]]$Tokens, [int]$Default = 5)
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

function Parse-MinutesToken {
    param(
        [string]$Token,
        [int]$Default = 0
    )
    if ([string]::IsNullOrWhiteSpace($Token)) { return $Default }
    $t = $Token.Trim().ToLowerInvariant()
    if ($t -match "^(\d+)\s*(m|min|mins|minute|minutes)?$") {
        $n = [int]$matches[1]
        if ($n -ge 1) { return $n }
    }
    return $Default
}

function Invoke-ClawUsageMonitor {
    param(
        [switch]$Json,
        [switch]$Live,
        [Parameter(Mandatory = $true)][string]$Language
    )

    $invokeParams = @{
        IncludeLocalTokens = $true
        Language = $Language
    }
    if ($Json) {
        $invokeParams.Json = $true
    }
    if (-not $Live) {
        $invokeParams.UseCache = $true
        $invokeParams.CacheMaxAgeSec = 300
    }

    & $monitorScript @invokeParams
}

if (-not (Test-Path -LiteralPath $monitorScript)) {
    throw "Missing script: $monitorScript"
}
if (-not (Test-Path -LiteralPath $workerScript)) {
    throw "Missing script: $workerScript"
}

$cmd = if ($Args.Count -gt 0) { $Args[0].ToLowerInvariant() } else { "help" }
$config = Get-Config

switch ($cmd) {
    "help" {
        Show-Help
        if (-not [bool]$config.onboardingShown) {
            Show-FirstRunLanguageHint
            $config.onboardingShown = $true
            Save-Config -Config $config
        }
        exit 0
    }
    "-help" {
        Show-Help
        if (-not [bool]$config.onboardingShown) {
            Show-FirstRunLanguageHint
            $config.onboardingShown = $true
            Save-Config -Config $config
        }
        exit 0
    }
    "--help" {
        Show-Help
        if (-not [bool]$config.onboardingShown) {
            Show-FirstRunLanguageHint
            $config.onboardingShown = $true
            Save-Config -Config $config
        }
        exit 0
    }
    "-h" {
        Show-Help
        if (-not [bool]$config.onboardingShown) {
            Show-FirstRunLanguageHint
            $config.onboardingShown = $true
            Save-Config -Config $config
        }
        exit 0
    }
    "now" {
        $json = ($Args -contains "--json")
        $live = ($Args -contains "live" -or $Args -contains "--live")
        Invoke-ClawUsageMonitor -Json:$json -Live:$live -Language $config.language
        exit 0
    }
    "status" {
        $live = ($Args -contains "live" -or $Args -contains "--live")
        Invoke-ClawUsageMonitor -Live:$live -Language $config.language
        exit 0
    }
    "lang" {
        if ($Args.Count -lt 2) {
            Write-Host ("language: {0}" -f [string]$config.language)
            exit 0
        }

        $language = Normalize-Language -Language $Args[1]
        $config.language = $language
        $config.onboardingShown = $true
        Save-Config -Config $config

        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -ne $task) {
            Install-AutoTask -Config $config
        }

        Write-Host ("language: {0}" -f $language)
        exit 0
    }
    "auto" {
        if ($Args.Count -lt 2) {
            Show-Help
            if (-not [bool]$config.onboardingShown) {
                Show-FirstRunLanguageHint
                $config.onboardingShown = $true
                Save-Config -Config $config
            }
            exit 1
        }
        $sub = $Args[1].ToLowerInvariant()
        switch ($sub) {
            "on" {
                if ($Args.Count -ge 3) {
                    $tmp = Parse-MinutesToken -Token $Args[2] -Default 0
                    if ($tmp -ge 1) {
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
                $minutes = Parse-MinutesToken -Token $Args[2] -Default 0
                if ($minutes -lt 1) {
                    throw "Idle minutes must be an integer >= 1."
                }
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
                if (-not [bool]$config.onboardingShown) {
                    Show-FirstRunLanguageHint
                    $config.onboardingShown = $true
                    Save-Config -Config $config
                }
                exit 1
            }
        }
    }
    default {
        Show-Help
        if (-not [bool]$config.onboardingShown) {
            Show-FirstRunLanguageHint
            $config.onboardingShown = $true
            Save-Config -Config $config
        }
        exit 1
    }
}

