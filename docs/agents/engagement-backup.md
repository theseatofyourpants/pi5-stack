---
title: /engagement-backup
tags: [skill, agent, ops, backup, data-protection]
skill_name: engagement-backup
model: claude-opus-5
file: ~/.claude/agents/engagement-backup.md
updated: 2026-07-27
---

# /engagement-backup

Part of [[Operator-Skills]]. **New skill** — protects the one thing on the Pi that isn't rebuildable: the work product.

## Purpose
Snapshot the irreplaceable outputs — engagement reports, the [[Detection-Library]], the operator skills, and the [[00-Index|pi_design vault]] — into a timestamped local archive (and optional git repo), with the MCP config **secrets-redacted**. The Pi's services are rebuildable ([[Replication-Guide]]); the data is not.

## MCPs it drives
None — pure Bash/Read/Write/AskUserQuestion.

## What it backs up
- `~/engagements/` + `~/engagements/detection-library/`
- `~/.claude/agents/` (the tuned skills) + `~/pi_design/` (this vault)
- Build artifacts: `greynoise-mcp/server.py`, `build-sensors.sh`, `zeek-install.sh`
- `~/.claude.json` mcpServers — **redacted** (VT/Mythic/GreyNoise secrets → `<REDACTED>`)

## What it never leaks
Sliver mTLS keys, Mythic container secrets, and (by default) captured client credentials. Redaction is **verified** before success is reported — a backup that leaks secrets is worse than none.

## Workflow
- **Step 0:** destination (local `~/backups/` default / git / named remote), include-creds? (default no), scope.
- **Step 1:** build redacted config → rsync the trees (excluding venvs/node_modules) → manifest → tar.gz.
- **Step 2:** optional git snapshot; push only if explicitly authorized **and** the tree greps clean of secrets.
- **Step 3:** report + retention prune suggestion (keep last N, never auto-delete).

## Output
`~/backups/pi5-stack-backup-{TS}.tar.gz` + optional git commit.

## Safety
Any remote push = publishing → explicit confirm; reports/rules may be client-confidential. See [[operation]] (calls this at engagement close).
