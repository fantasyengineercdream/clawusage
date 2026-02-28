# OpenClaw Windows Hardlock + ClawUsage

Windows-native safe baseline for OpenClaw without Docker/WSL, plus a lightweight usage monitor (`clawusage`) that works in terminal and Telegram.

## LLM Snapshot

```yaml
project: openclaw-windows-hardlock
platform: windows-no-wsl-no-docker
goals:
  - harden filesystem access for OpenClaw on host
  - keep workflow simple (KISS)
  - monitor Codex usage locally with zero model-inference overhead
core_components:
  - windows-acl-hardlock-scripts
  - clawusage-command
  - clawusage-openclaw-skill
security_boundary:
  mechanism:
    - dedicated local user (openclaw_bot)
    - NTFS ACL allowlist (workspace + state)
  requirement:
    - run OpenClaw under openclaw_bot for isolation to take effect
not_a_container_sandbox: true
```

## What This Project Includes

1. **Windows Hardlock** (ACL + low-privilege account)
2. **`clawusage` command** (ccusage-style quick monitor)
3. **Telegram-ready skill** (`/clawusage ...` native skill command)

## Quick Start

### 1) Apply hardlock (elevated)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-openclaw-hardlock-elevated.ps1 \
  -WorkspacePath "D:\path\to\workspace" \
  -StatePath "D:\path\to\workspace\.openclaw-state"
```

### 2) Verify setup

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-openclaw-hardlock.ps1 \
  -WorkspacePath "D:\path\to\workspace" \
  -StatePath "D:\path\to\workspace\.openclaw-state"
```

Pass signal: `Validation passed.`

### 3) Run OpenClaw as constrained user

```powershell
runas /user:YOUR_PC_NAME\openclaw_bot "powershell -NoProfile -NoExit -Command \"$env:OPENCLAW_STATE_DIR='D:\path\to\workspace\.openclaw-state'; $env:OPENCLAW_CONFIG_PATH='D:\path\to\workspace\.openclaw-state\openclaw.json'; Set-Location -LiteralPath 'D:\path\to\workspace'; openclaw\""
```

### 4) Use `clawusage`

```powershell
.\clawusage.cmd now
.\clawusage.cmd auto on 10
.\clawusage.cmd auto set 15
.\clawusage.cmd auto off
.\clawusage.cmd auto status
.\clawusage.cmd -help
```

In Telegram (after skill registration):

```text
/clawusage now
/clawusage auto on 10
```

## `clawusage` Command Reference

- `clawusage now`: show current usage snapshot (no model inference)
- `clawusage auto on [minutes] [--interval N]`: enable one-shot idle reminder
- `clawusage auto set <minutes>`: update idle threshold
- `clawusage auto off`: disable idle reminder task
- `clawusage auto status`: show task status
- `clawusage -help | --help | -h`: show help

## How To Read `clawusage` Output

Example fields:

- `Model`: current session model (for example `openai-codex/gpt-5.3-codex`)
- `Tokens`: **current session** input/output tokens, not total account lifetime
- `Context`: used context tokens vs max context (for example `15k / 272k (6%)`)
- `Compactions`: number of context compactions in this session
- `5h window`: short-term quota window (near-term throttle risk)
- `Day window`: provider label; **reset timestamp is authoritative** (it may exceed 24h)
- `Local tokens today / 7d`: parsed from local OpenClaw session logs only

## Idle Reminder Behavior (Important)

`clawusage auto on X` means:

- checks idle every interval minute(s)
- sends **one** reminder when idle first crosses threshold `X`
- does **not** spam every X minutes
- sends next reminder only after new activity, then idle crosses threshold again

## Security Model

### What it does

- reduces accidental/prompt-driven writes outside workspace
- reduces blast radius using low-privilege process token
- provides repeatable apply/verify/rollback scripts

### What it does not do

- not container/kernel isolation
- not a full network egress sandbox
- if OpenClaw runs under your normal admin-capable user, isolation intent is weakened

## Project Layout

```text
openclaw-windows-hardlock/
  README.md
  LICENSE
  .gitignore
  install.cmd
  clawusage.cmd
  scripts/
    apply-openclaw-hardlock-elevated.ps1
    setup-openclaw-hardlock.ps1
    test-openclaw-hardlock.ps1
    rollback-openclaw-hardlock.ps1
    clawusage.ps1
    clawusage-auto-worker.ps1
    openclaw-usage-monitor.ps1
    make-release-zip.ps1
    prepare-github-repo.ps1
    publish-clawhub.ps1
  skills/
    clawusage/
      SKILL.md
```

## Release and Publishing

### Build release zip

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\make-release-zip.ps1
```

### Prepare standalone GitHub repo (local)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-github-repo.ps1 -Force
```

This creates a clean publish directory with its own `.git` and initial commit, excluding runtime state.

### Publish ClawHub skill

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-clawhub.ps1
```

If not logged in, run:

```powershell
npx clawhub login
```

then retry publish.

## Upstream PR Feasibility (OpenClaw)

Yes, but recommended as a focused proposal:

1. add Windows no-Docker hardening guide (docs-only first)
2. optionally contribute `clawusage` as a community skill package
3. keep core behavior changes minimal; prefer plugin/skill-level integration first

## FAQ

- **Is this equivalent to Docker sandbox?** No.
- **Is this useful on pure Windows?** Yes, strong practical fallback.
- **Why separate user?** ACL boundaries depend on process token.

## License

MIT