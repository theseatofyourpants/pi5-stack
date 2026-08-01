---
title: Scheduled Jobs (stack-cron)
tags: [operations, automation, systemd, timers, backup]
updated: 2026-08-01
---

# Scheduled Jobs (stack-cron)

Back to [[00-Index]]. Local timer-driven automation added 2026-08-01 (`~/stack-cron/`). All run **on the Pi** (they need localhost services), driven by systemd timers — not cloud routines.

## The jobs
| Job | Schedule | Cost | What it does |
|-----|----------|------|--------------|
| `stack-status.timer` | boot + daily 09:00 | LLM | headless `/stack-status` health board — catches down backends after reboot |
| `triage-alerts.timer` | every 6h (00/06/12/18) | LLM (4×/day) | headless `/triage-alerts` — Huntress + C2 + sensor correlation → runbook |
| `stack-backup.timer` | daily 03:00 | free | deterministic redacted local backup (see below) |

## How the agent jobs run
`~/stack-cron/run-agent.sh <agent> <timeout> <task>` — mirrors the [[Autonomous-AP-Testbed|trigger-scan.sh]] pattern: absolute `~/.local/bin/claude -p --dangerously-skip-permissions --output-format stream-json`, restored PATH, piped through `~/ap-testbed/lib/stream-filter.py`. Logs to `~/stack-cron/logs/<agent>-latest.log`. Tune the triage interval by editing `OnCalendar=` in `~/stack-cron/systemd/triage-alerts.timer` + `daemon-reload`.

## The backup job
`~/stack-cron/backup.sh` — **no LLM, no egress** (chosen over the [[engagement-backup]] agent for the scheduled path: robust/free/no injection surface). Mirrors the agent's Step 1: redacts MCP secrets (+verifies, hard-fails if any survive), **omits captured creds**, local `~/backups/pi5-stack-backup-<ts>.tar.gz`, keeps 14. Recover with the [[Stack-Ops-Skills|stack-restore]] skill. The interactive [[engagement-backup]] agent stays for on-demand/git/remote.

## Residual risk
Agent jobs run `--dangerously-skip-permissions` (no human to approve). `stack-status` is read-only; `backup.sh` is a plain script; `triage-alerts` reads external Huntress data (mild prompt-injection surface, bounded by that agent's toolset) — same posture accepted for the testbed's headless scans.

## Related
- [[Reboot-Runbook]] · [[stack-status]] · [[triage-alerts]] · [[Stack-Ops-Skills]]
