# ClawUsage

Lightweight local usage monitor for OpenClaw/Codex, with optional one-shot idle reminders and Telegram-friendly skill integration.

## LLM Snapshot

```yaml
project: clawusage
goal:
  - show current session usage and quota clearly
  - provide one-shot idle reminder after inactivity threshold
  - support terminal + Telegram (/clawusage)
token_cost:
  - usage query: no model inference
  - data source: local OpenClaw metadata/log files
platform:
  - windows
```

## What This Project Includes

- `clawusage.cmd`: main command entry
- PowerShell scripts for usage snapshot and idle alert worker
- OpenClaw skill: `skills/clawusage/SKILL.md`
- helper scripts for GitHub packaging and ClawHub publish

## Quick Start

Run from this folder:

```powershell
.\clawusage.cmd now
.\clawusage.cmd status
.\clawusage.cmd lang chinese
.\clawusage.cmd lang english
.\clawusage.cmd auto on 10
.\clawusage.cmd auto set 15
.\clawusage.cmd auto off
.\clawusage.cmd auto status
.\clawusage.cmd -help
```

## Commands

- `clawusage now`: show current usage snapshot
- `clawusage status`: alias of `now`
- `clawusage lang [english|chinese]`: view/set output language
- `clawusage auto on [minutes] [--interval N]`: enable idle reminder task
- `clawusage auto set <minutes>`: change idle threshold
- `clawusage auto off`: disable reminder task
- `clawusage auto status`: task state and schedule
- `clawusage -help | --help | -h`: show help

Language behavior:

- `lang` sets the preferred chat response language (`english` or `chinese`).
- CLI monitor keeps stable field names and prints `Language mode: ...` for parser stability.

## Idle Reminder Behavior

- Reminder is sent once when idle first crosses threshold.
- No spam every X minutes.
- Another reminder only happens after new activity and then another idle crossing.

## Skill Integration

Skill file:

```text
skills/clawusage/SKILL.md
```

The skill runs `clawusage.cmd` by command name.  
For chat execution from any working directory, ensure `clawusage.cmd` is on `PATH`.

## Project Layout

```text
clawusage/
  README.md
  LICENSE
  .gitignore
  clawusage.cmd
  usage.cmd
  usage-now.cmd
  usage-idle-install.cmd
  usage-idle-set.cmd
  usage-idle-uninstall.cmd
  scripts/
    clawusage.ps1
    clawusage-auto-worker.ps1
    openclaw-usage-monitor.ps1
    openclaw-usage-idle-popup.ps1
    install-idle-usage-task.ps1
    uninstall-idle-usage-task.ps1
    publish-clawhub.ps1
    make-release-zip.ps1
    prepare-github-repo.ps1
  skills/
    clawusage/
      SKILL.md
```

## Publish Helpers

Build zip:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\make-release-zip.ps1
```

Prepare standalone git repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-github-repo.ps1 -Force
```

Publish skill:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-clawhub.ps1
```

## License

MIT
