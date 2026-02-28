# OpenClaw Upstream PR Proposal (Docs-First)

## Goal

Contribute a practical security baseline for **Windows users without Docker/WSL**.

## Why

Many Windows users cannot run Docker sandboxing reliably. A host-level hardening guide (low-privilege user + ACL allowlist) provides a meaningful fallback.

## Proposed Scope (Minimal)

1. Add a docs page:
   - `docs/gateway/sandboxing/windows-no-docker-hardening.md`
2. Include:
   - threat model
   - setup steps (dedicated user + ACL)
   - verify/rollback commands
   - explicit limitations (not container isolation)
3. Optional follow-up:
   - publish `clawusage` as a community skill (not core behavior change)

## Non-Goals

- No breaking config changes
- No forced behavior for existing users
- No kernel/container claims

## Acceptance Criteria

- Guide is reproducible on Windows 10/11 PowerShell
- Users can run apply -> verify -> rollback end-to-end
- Security boundaries and limitations are clearly documented

## Suggested PR Title

`docs(security): add Windows no-Docker hardening guide for OpenClaw`

## Suggested PR Body (Draft)

This PR adds a Windows-specific hardening guide for environments where Docker/WSL sandboxing is unavailable.

It documents a practical fallback:
- run OpenClaw with a dedicated low-privilege local user
- apply NTFS ACL allowlist to workspace/state paths
- validate and rollback with repeatable scripts

This is intentionally docs-first and non-breaking. It does not change runtime defaults and does not claim container-level isolation.

## Repository Reference

Implementation and scripts used for validation:
- https://github.com/fantasyengineercdream/clawusage