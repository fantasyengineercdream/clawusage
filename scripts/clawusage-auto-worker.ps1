[CmdletBinding()]
param(
    [int]$IdleMinutes = 10,
    [string]$Provider = "openai-codex",
    [string]$SessionsFile = "$env:USERPROFILE\.openclaw\agents\main\sessions\sessions.json",
    [string]$StateFile = "",
    [switch]$IncludeLocalTokens
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($IdleMinutes -lt 1) { throw "IdleMinutes must be >= 1." }

if ([string]::IsNullOrWhiteSpace($StateFile)) {
    $StateFile = Join-Path $PSScriptRoot "..\.openclaw-state\clawusage-auto-state.json"
}
$statePath = [System.IO.Path]::GetFullPath($StateFile)
$stateDir = Split-Path -Parent $statePath
if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

function Invoke-OpenClaw {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$CaptureOutput
    )
    function Escape-CmdArg {
        param([string]$Value)
        if ($null -eq $Value) { return '""' }
        $v = $Value -replace '"', '\"'
        return '"' + $v + '"'
    }

    $escaped = @()
    foreach ($a in $Arguments) {
        $escaped += Escape-CmdArg -Value $a
    }
    $cmdLine = "openclaw " + ($escaped -join " ") + " 2>nul"

    if ($CaptureOutput) {
        $output = (& cmd /c $cmdLine | Out-String).Trim()
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = $output
        }
    }

    & cmd /c $cmdLine | Out-Null
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ""
    }
}

function Get-LatestSession {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $obj = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $best = $null
    foreach ($p in $obj.PSObject.Properties) {
        $v = $p.Value
        if ($null -eq $v) { continue }
        if (-not ($v.PSObject.Properties.Name -contains "updatedAt")) { continue }
        $updatedAtMs = [int64]$v.updatedAt
        if ($null -eq $best -or $updatedAtMs -gt $best.UpdatedAtMs) {
            $best = [pscustomobject]@{
                SessionKey = $p.Name
                UpdatedAtMs = $updatedAtMs
                UpdatedAtLocal = [datetimeoffset]::FromUnixTimeMilliseconds($updatedAtMs).ToLocalTime()
                LastChannel = if ($v.PSObject.Properties.Name -contains "lastChannel") { [string]$v.lastChannel } else { "" }
                LastTo = if ($v.PSObject.Properties.Name -contains "lastTo") { [string]$v.lastTo } else { "" }
                LastAccountId = if ($v.PSObject.Properties.Name -contains "lastAccountId") { [string]$v.lastAccountId } else { "" }
                OriginProvider = if ($v.PSObject.Properties.Name -contains "origin" -and $v.origin -ne $null -and $v.origin.PSObject.Properties.Name -contains "provider") { [string]$v.origin.provider } else { "" }
                OriginTo = if ($v.PSObject.Properties.Name -contains "origin" -and $v.origin -ne $null -and $v.origin.PSObject.Properties.Name -contains "to") { [string]$v.origin.to } else { "" }
                OriginFrom = if ($v.PSObject.Properties.Name -contains "origin" -and $v.origin -ne $null -and $v.origin.PSObject.Properties.Name -contains "from") { [string]$v.origin.from } else { "" }
                OriginAccountId = if ($v.PSObject.Properties.Name -contains "origin" -and $v.origin -ne $null -and $v.origin.PSObject.Properties.Name -contains "accountId") { [string]$v.origin.accountId } else { "" }
            }
        }
    }
    return $best
}

function Normalize-Target {
    param(
        [string]$Channel,
        [string]$Target
    )
    if ([string]::IsNullOrWhiteSpace($Target)) { return "" }
    if ($Target -match "^([a-zA-Z0-9_-]+):(.+)$") {
        $prefix = $matches[1].ToLowerInvariant()
        $tail = $matches[2]
        if ($prefix -eq $Channel.ToLowerInvariant()) {
            return $tail
        }
    }
    return $Target
}

function Resolve-Delivery {
    param([Parameter(Mandatory = $true)]$Session)
    $channel = $Session.LastChannel
    if ([string]::IsNullOrWhiteSpace($channel)) { $channel = $Session.OriginProvider }
    if ([string]::IsNullOrWhiteSpace($channel)) { $channel = "telegram" }

    $target = $Session.LastTo
    if ([string]::IsNullOrWhiteSpace($target)) { $target = $Session.OriginTo }
    if ([string]::IsNullOrWhiteSpace($target)) { $target = $Session.OriginFrom }
    $target = Normalize-Target -Channel $channel -Target $target

    $account = $Session.LastAccountId
    if ([string]::IsNullOrWhiteSpace($account)) { $account = $Session.OriginAccountId }
    if ([string]::IsNullOrWhiteSpace($account)) { $account = "default" }

    return [pscustomobject]@{
        Channel = $channel
        Target = $target
        Account = $account
    }
}

function Get-UsageRows {
    param([string]$ProviderName)
    $res = Invoke-OpenClaw -Arguments @("channels", "list", "--json") -CaptureOutput
    if ($res.ExitCode -ne 0) { return @() }
    $raw = $res.Output
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

    $obj = $raw | ConvertFrom-Json
    if ($null -eq $obj.usage -or $null -eq $obj.usage.providers) { return @() }

    $rows = @()
    foreach ($p in $obj.usage.providers) {
        if (-not [string]::IsNullOrWhiteSpace($ProviderName) -and $p.provider -ne $ProviderName) { continue }
        foreach ($w in $p.windows) {
            $rows += [pscustomobject]@{
                Label = [string]$w.label
                Used = [int]$w.usedPercent
                Left = [Math]::Max(0, 100 - [int]$w.usedPercent)
                ResetAt = [datetimeoffset]::FromUnixTimeMilliseconds([int64]$w.resetAt).ToLocalTime()
            }
        }
    }
    return $rows
}

function Get-LocalTokenSummary {
    $sessionDir = Join-Path $env:USERPROFILE ".openclaw\agents\main\sessions"
    if (-not (Test-Path -LiteralPath $sessionDir)) {
        return [pscustomobject]@{
            TodayTokens = 0
            Last7DaysTokens = 0
            Last30DaysTokens = 0
        }
    }

    $todayStart = (Get-Date).Date
    $d7 = $todayStart.AddDays(-6)
    $d30 = $todayStart.AddDays(-29)

    $today = [int64]0
    $last7 = [int64]0
    $last30 = [int64]0

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

            if ($ts -ge $d30) { $last30 += $tokens }
            if ($ts -ge $d7) { $last7 += $tokens }
            if ($ts -ge $todayStart) { $today += $tokens }
        }
    }

    return [pscustomobject]@{
        TodayTokens = $today
        Last7DaysTokens = $last7
        Last30DaysTokens = $last30
    }
}

function Format-IdleDuration {
    param([timespan]$Span)
    if ($Span.TotalMinutes -lt 1) { return "less than 1m" }
    if ($Span.TotalDays -ge 1) {
        return ("{0}d {1}h {2}m" -f [int]$Span.TotalDays, [int]$Span.Hours, [int]$Span.Minutes)
    }
    if ($Span.TotalHours -ge 1) {
        return ("{0}h {1}m" -f [int]$Span.TotalHours, [int]$Span.Minutes)
    }
    return ("{0}m" -f [int]$Span.TotalMinutes)
}

$latest = Get-LatestSession -Path $SessionsFile
if ($null -eq $latest) { exit 0 }

$idleSpan = [datetimeoffset]::Now - $latest.UpdatedAtLocal
if ($idleSpan.TotalMinutes -lt $IdleMinutes) { exit 0 }

$state = $null
if (Test-Path -LiteralPath $statePath) {
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $state = $null }
}
$lastNotifiedMs = if ($null -ne $state -and $state.PSObject.Properties.Name -contains "lastNotifiedUpdatedAtMs") { [int64]$state.lastNotifiedUpdatedAtMs } else { [int64]0 }
$lastNotifiedKey = if ($null -ne $state -and $state.PSObject.Properties.Name -contains "lastNotifiedSessionKey") { [string]$state.lastNotifiedSessionKey } else { "" }
if ($lastNotifiedMs -eq $latest.UpdatedAtMs -and $lastNotifiedKey -eq $latest.SessionKey) { exit 0 }

$delivery = Resolve-Delivery -Session $latest
if ([string]::IsNullOrWhiteSpace($delivery.Target)) { exit 0 }

$rows = Get-UsageRows -ProviderName $Provider
$idleNow = [datetimeoffset]::Now - $latest.UpdatedAtLocal
$parts = @()
$parts += "ClawUsage Idle Alert"
$parts += ("Threshold: {0}m" -f $IdleMinutes)
$parts += ("Last activity: {0}" -f $latest.UpdatedAtLocal.ToString('yyyy-MM-dd HH:mm'))
$parts += ("Idle now: {0}" -f (Format-IdleDuration -Span $idleNow))
if (($rows | Measure-Object).Count -gt 0) {
    $parts += ""
    $parts += "Quota:"
    foreach ($r in ($rows | Sort-Object Label)) {
        $note = ""
        $hoursUntilReset = ($r.ResetAt - [datetimeoffset]::Now).TotalHours
        if ($r.Label -ieq "Day" -and $hoursUntilReset -gt 36) {
            $note = " (provider long window label)"
        }
        $parts += ("- {0}: {1}% used, {2}% left, resets {3}{4}" -f $r.Label, $r.Used, $r.Left, $r.ResetAt.ToString('MM-dd HH:mm'), $note)
    }
}
if ($IncludeLocalTokens) {
    $t = Get-LocalTokenSummary
    $parts += ""
    $parts += "Local tokens (from local logs):"
    $parts += ("- today: {0:N0}" -f $t.TodayTokens)
    $parts += ("- 7d: {0:N0}" -f $t.Last7DaysTokens)
}
$message = ($parts -join "`n")

$sendRes = Invoke-OpenClaw -Arguments @("message", "send", "--channel", $delivery.Channel, "--account", $delivery.Account, "--target", $delivery.Target, "-m", $message, "--silent", "--json") -CaptureOutput
if ($sendRes.ExitCode -ne 0) { exit 0 }
$sendOutput = $sendRes.Output
if (-not [string]::IsNullOrWhiteSpace($sendOutput)) {
    try {
        $sendObj = $sendOutput | ConvertFrom-Json
        if ($sendObj.PSObject.Properties.Name -contains "payload" -and $sendObj.payload -ne $null) {
            if ($sendObj.payload.PSObject.Properties.Name -contains "ok" -and -not [bool]$sendObj.payload.ok) {
                exit 0
            }
        }
    } catch {
        # Ignore parse failures from non-JSON plugin logs and keep state update best-effort.
    }
}

[pscustomobject]@{
    lastNotifiedUpdatedAtMs = $latest.UpdatedAtMs
    lastNotifiedSessionKey = $latest.SessionKey
    lastNotifiedAt = [datetimeoffset]::Now.ToString("o")
    idleMinutes = $IdleMinutes
    channel = $delivery.Channel
    target = $delivery.Target
    account = $delivery.Account
} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
