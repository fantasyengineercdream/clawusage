[CmdletBinding()]
param(
    [int]$IdleMinutes = 10,
    [string]$Provider = "openai-codex",
    [string]$SessionsFile = "$env:USERPROFILE\.openclaw\agents\main\sessions\sessions.json",
    [string]$StateFile = "",
    [switch]$IncludeLocalTokens,
    [switch]$NoPopup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-LocalTokenSummary {
    $sessionDir = Join-Path $env:USERPROFILE ".openclaw\agents\main\sessions"
    if (-not (Test-Path -LiteralPath $sessionDir)) {
        return [pscustomobject]@{
            TodayTokens = 0
            Last7DaysTokens = 0
            Last30DaysTokens = 0
            MessageCount = 0
        }
    }

    $todayStart = (Get-Date).Date
    $d7 = $todayStart.AddDays(-6)
    $d30 = $todayStart.AddDays(-29)

    $today = [int64]0
    $last7 = [int64]0
    $last30 = [int64]0
    $count = [int64]0

    $files = Get-ChildItem -LiteralPath $sessionDir -File | Where-Object { $_.Name -like "*.jsonl*" }
    foreach ($file in $files) {
        Get-Content -LiteralPath $file.FullName | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { return }
            try { $obj = $_ | ConvertFrom-Json -ErrorAction Stop } catch { return }
            if ($obj.type -ne "message") { return }
            if ($null -eq $obj.message) { return }
            if (-not ($obj.message.PSObject.Properties.Name -contains "provider")) { return }
            if ([string]$obj.message.provider -ne "openai-codex") { return }
            if (-not ($obj.PSObject.Properties.Name -contains "timestamp")) { return }

            $ts = $null
            try { $ts = [datetimeoffset]::Parse([string]$obj.timestamp).LocalDateTime } catch { return }
            $u = $obj.message.usage
            if ($null -eq $u) { return }

            $tokens = [int64]0
            if ($u.PSObject.Properties.Name -contains "totalTokens" -and $u.totalTokens -ne $null) {
                $tokens = [int64]$u.totalTokens
            } elseif ($u.PSObject.Properties.Name -contains "total" -and $u.total -ne $null) {
                $tokens = [int64]$u.total
            } else {
                $in = if ($u.PSObject.Properties.Name -contains "input" -and $u.input -ne $null) { [int64]$u.input } else { 0 }
                $out = if ($u.PSObject.Properties.Name -contains "output" -and $u.output -ne $null) { [int64]$u.output } else { 0 }
                $cr = if ($u.PSObject.Properties.Name -contains "cacheRead" -and $u.cacheRead -ne $null) { [int64]$u.cacheRead } else { 0 }
                $cw = if ($u.PSObject.Properties.Name -contains "cacheWrite" -and $u.cacheWrite -ne $null) { [int64]$u.cacheWrite } else { 0 }
                $tokens = $in + $out + $cr + $cw
            }
            if ($tokens -le 0) { return }

            $count++
            if ($ts -ge $d30) { $last30 += $tokens }
            if ($ts -ge $d7) { $last7 += $tokens }
            if ($ts -ge $todayStart) { $today += $tokens }
        }
    }

    return [pscustomobject]@{
        TodayTokens = $today
        Last7DaysTokens = $last7
        Last30DaysTokens = $last30
        MessageCount = $count
    }
}

function Get-LatestSessionUpdate {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $obj = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $max = $null
    $maxKey = $null
    foreach ($p in $obj.PSObject.Properties) {
        $v = $p.Value
        if ($null -eq $v) { continue }
        if (-not ($v.PSObject.Properties.Name -contains "updatedAt")) { continue }
        $u = [int64]$v.updatedAt
        if ($null -eq $max -or $u -gt $max) {
            $max = $u
            $maxKey = $p.Name
        }
    }
    if ($null -eq $max) { return $null }
    return [pscustomobject]@{
        SessionKey = $maxKey
        UpdatedAtMs = [int64]$max
        UpdatedAtLocal = [datetimeoffset]::FromUnixTimeMilliseconds([int64]$max).ToLocalTime()
    }
}

function Get-UsageRows {
    param([string]$ProviderName)
    # Reads usage metadata only; does NOT invoke model inference.
    $raw = (& cmd /c "openclaw channels list --json 2>nul" | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $obj = $raw | ConvertFrom-Json
    if ($null -eq $obj.usage -or $null -eq $obj.usage.providers) { return @() }

    $rows = @()
    foreach ($p in $obj.usage.providers) {
        if (-not [string]::IsNullOrWhiteSpace($ProviderName) -and $p.provider -ne $ProviderName) { continue }
        foreach ($w in $p.windows) {
            $used = [int]$w.usedPercent
            $remain = [Math]::Max(0, 100 - $used)
            $reset = [datetimeoffset]::FromUnixTimeMilliseconds([int64]$w.resetAt).ToLocalTime()
            $rows += [pscustomobject]@{
                Provider = [string]$p.provider
                Plan = [string]$p.plan
                Window = [string]$w.label
                UsedPercent = $used
                RemainingPercent = $remain
                ResetAt = $reset
            }
        }
    }
    return $rows
}

if ($IdleMinutes -lt 1) { throw "IdleMinutes must be >= 1." }

if ([string]::IsNullOrWhiteSpace($StateFile)) {
    $StateFile = Join-Path $PSScriptRoot "..\.openclaw-state\idle-usage-notify-state.json"
}
$statePath = [System.IO.Path]::GetFullPath($StateFile)
$stateDir = Split-Path -Parent $statePath
if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

$latest = Get-LatestSessionUpdate -Path $SessionsFile
if ($null -eq $latest) { exit 0 }

$now = [datetimeoffset]::Now
$idleSpan = $now - $latest.UpdatedAtLocal
if ($idleSpan.TotalMinutes -lt $IdleMinutes) { exit 0 }

$state = $null
if (Test-Path -LiteralPath $statePath) {
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $state = $null }
}
$lastNotified = if ($null -ne $state -and $state.PSObject.Properties.Name -contains "lastNotifiedUpdatedAtMs") { [int64]$state.lastNotifiedUpdatedAtMs } else { [int64]0 }
$lastNotifiedKey = if ($null -ne $state -and $state.PSObject.Properties.Name -contains "lastNotifiedSessionKey") { [string]$state.lastNotifiedSessionKey } else { "" }
# Notify once per idle cycle (same sessionKey + updatedAt): no repeat every 10 minutes.
if ($lastNotified -eq $latest.UpdatedAtMs -and $lastNotifiedKey -eq $latest.SessionKey) { exit 0 }

$rows = Get-UsageRows -ProviderName $Provider
$lines = @()
$lines += "OpenClaw idle usage reminder"
$lines += ""
$lines += ("Idle threshold reached: {0} min" -f $IdleMinutes)
$lines += ("Last session update: {0}" -f $latest.UpdatedAtLocal.ToString("yyyy-MM-dd HH:mm:ss zzz"))
$lines += ("Session key: {0}" -f $latest.SessionKey)
$lines += ""

if (($rows | Measure-Object).Count -gt 0) {
    foreach ($r in ($rows | Sort-Object Provider, Window)) {
        $lines += ("{0}/{1} {2}: used {3}% | left {4}% | reset {5}" -f $r.Provider, $r.Plan, $r.Window, $r.UsedPercent, $r.RemainingPercent, $r.ResetAt.ToString("MM-dd HH:mm"))
    }
} else {
    $lines += "Usage rows unavailable (openclaw channels list --json returned no usage)."
}

if ($IncludeLocalTokens) {
    $t = Get-LocalTokenSummary
    $lines += ""
    $lines += ("Local tokens today: {0}" -f $t.TodayTokens)
    $lines += ("Local tokens 7d: {0}" -f $t.Last7DaysTokens)
    $lines += ("Local tokens 30d: {0}" -f $t.Last30DaysTokens)
}

$message = ($lines -join [Environment]::NewLine)

if ($NoPopup) {
    Write-Output $message
} else {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($message, "OpenClaw Usage", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

[pscustomobject]@{
    lastNotifiedUpdatedAtMs = $latest.UpdatedAtMs
    lastNotifiedSessionKey = $latest.SessionKey
    lastNotifiedAt = [datetimeoffset]::Now.ToString("o")
    idleMinutes = $IdleMinutes
} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
