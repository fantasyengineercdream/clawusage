[CmdletBinding()]
param(
    [switch]$Watch,
    [int]$IntervalSec = 30,
    [string]$Provider = "",
    [switch]$Json,
    [switch]$NoClear,
    [switch]$IncludeLocalTokens,
    [ValidateSet("english", "chinese")]
    [string]$Language = "english"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Format-TimeLeft {
    param([timespan]$Span)
    if ($Span.TotalSeconds -le 0) { return "resetting" }
    if ($Span.TotalDays -ge 1) {
        return ("{0}d {1}h {2}m" -f [int]$Span.TotalDays, $Span.Hours, $Span.Minutes)
    }
    if ($Span.TotalHours -ge 1) {
        return ("{0}h {1}m {2}s" -f [int]$Span.TotalHours, $Span.Minutes, $Span.Seconds)
    }
    if ($Span.TotalMinutes -ge 1) {
        return ("{0}m {1}s" -f [int]$Span.TotalMinutes, $Span.Seconds)
    }
    return ("{0}s" -f [int]$Span.TotalSeconds)
}

function Get-LocalTokenSummary {
    $sessionDir = Join-Path $env:USERPROFILE ".openclaw\agents\main\sessions"
    if (-not (Test-Path -LiteralPath $sessionDir)) {
        return [pscustomobject]@{
            SessionDir = $sessionDir
            Exists = $false
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
        SessionDir = $sessionDir
        Exists = $true
        TodayTokens = $today
        Last7DaysTokens = $last7
        Last30DaysTokens = $last30
        MessageCount = $count
    }
}

function Get-UsageSnapshot {
    $raw = (& cmd /c "openclaw channels list --json 2>nul" | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "No JSON from `openclaw channels list --json`."
    }
    $obj = $raw | ConvertFrom-Json
    if ($null -eq $obj.usage -or $null -eq $obj.usage.providers) {
        throw "Usage data not found in OpenClaw output."
    }

    $updated = [datetimeoffset]::FromUnixTimeMilliseconds([int64]$obj.usage.updatedAt).ToLocalTime()
    $rows = @()
    foreach ($p in $obj.usage.providers) {
        if (-not [string]::IsNullOrWhiteSpace($Provider) -and $p.provider -ne $Provider) { continue }
        foreach ($w in $p.windows) {
            $used = [int]$w.usedPercent
            $remain = [Math]::Max(0, 100 - $used)
            $reset = [datetimeoffset]::FromUnixTimeMilliseconds([int64]$w.resetAt).ToLocalTime()
            $left = $reset - [datetimeoffset]::Now
            $rows += [pscustomobject]@{
                Provider = [string]$p.provider
                Plan = [string]$p.plan
                Window = [string]$w.label
                UsedPercent = $used
                RemainingPercent = $remain
                ResetAt = $reset.ToString("yyyy-MM-dd HH:mm:ss zzz")
                TimeLeft = (Format-TimeLeft -Span $left)
            }
        }
    }

    $result = [pscustomobject]@{
        UpdatedAt = $updated.ToString("yyyy-MM-dd HH:mm:ss zzz")
        Rows = $rows
    }
    if ($IncludeLocalTokens) {
        $result | Add-Member -NotePropertyName LocalTokens -NotePropertyValue (Get-LocalTokenSummary)
    }
    return $result
}

function Show-Snapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)
    Write-Host ("OpenClaw Usage Monitor  |  Updated: {0}" -f $Snapshot.UpdatedAt)
    Write-Host ("Language mode: {0}" -f $Language)

    if (($Snapshot.Rows | Measure-Object).Count -eq 0) {
        Write-Host "No usage rows matched filter."
        return
    }

    $Snapshot.Rows |
        Sort-Object Provider, Window |
        Format-Table Provider, Plan, Window, UsedPercent, RemainingPercent, ResetAt, TimeLeft -AutoSize

    if ($IncludeLocalTokens -and $null -ne $Snapshot.LocalTokens) {
        Write-Host ""
        Write-Host "Local Token Summary (from ~/.openclaw session logs)"
        $Snapshot.LocalTokens | Format-List
    }
}

if ($IntervalSec -lt 2) {
    throw "IntervalSec must be >= 2."
}

if ($Watch) {
    while ($true) {
        if (-not $NoClear) { Clear-Host }
        try {
            $snap = Get-UsageSnapshot
            if ($Json) {
                $snap | ConvertTo-Json -Depth 8
            } else {
                Show-Snapshot -Snapshot $snap
                Write-Host ("Refresh in {0}s. Press Ctrl+C to stop." -f $IntervalSec)
            }
        } catch {
            Write-Host ("[error] " + $_.Exception.Message) -ForegroundColor Red
        }
        Start-Sleep -Seconds $IntervalSec
    }
}

$single = Get-UsageSnapshot
if ($Json) {
    $single | ConvertTo-Json -Depth 8
} else {
    Show-Snapshot -Snapshot $single
}
