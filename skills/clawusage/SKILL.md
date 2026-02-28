---
name: clawusage
description: Run local clawusage monitoring commands from chat. Use when user types `/clawusage ...` or asks to check Codex usage, enable/disable auto idle alerts, or set idle reminder threshold.
user-invocable: true
disable-model-invocation: false
---

# ClawUsage Chat Command

Use local `clawusage` commands and return a compact, easy-to-read English summary.

Command source:

- `.\project\openclaw-windows-hardlock\clawusage.cmd`

Supported arguments:

- `now`
- `status`
- `auto on [minutes]`
- `auto off`
- `auto set <minutes>`

Execution rules:

1. Parse user input after `/clawusage`.
2. If no argument is provided, default to `status`.
3. Run exactly one local command via shell:
   - `& ".\project\openclaw-windows-hardlock\clawusage.cmd" <args>`
4. Do not run unrelated commands.
5. If a field is missing, print `n/a`.

Formatting rules (important):

- Use plain English and short lines.
- Separate `Session`, `Quota`, `Meaning`, and `Local` sections.
- Do not return a single pipe-separated line.
- If quota label is `Day` but reset is far beyond 24h, explicitly say it is a provider label.

Reply format:

```text
ClawUsage
Action: <resolved action>
Status: <ok|error>

Session:
- Model: <...>
- Tokens (session): <...>
- Context: <used>/<max> (<pct>)
- Compactions: <...>
- Reasoning: <...>
- Session key: <...>
- Time: <...>

Quota:
- <label>: <used>% used, <left>% left, resets <time>, time left <duration>
- ...

Meaning:
- Short window (usually 5h) controls near-term throttling.
- `Day` is a provider label; reset timestamp is authoritative.

Local:
- Tokens today: <...>
- Tokens 7d: <...>
```

If command fails, return:

```text
ClawUsage
Action: <resolved action>
Status: error
Details:
<error message>
```