---
title: attack-surface-monitor
tags: [skill, offensive, blue, recon, monitoring, scheduled]
skill_name: attack-surface-monitor
file: ~/.claude/skills/attack-surface-monitor/SKILL.md
updated: 2026-08-14
---

# attack-surface-monitor

Part of [[Operator-Skills]]. Turns the recon layer into a **sensor**: on a cron (via the
**schedule** skill) it re-enumerates an *authorized* external scope (`bbot` +
`shodan`/`censys` + `httpx` + `nuclei`), diffs against a saved baseline, and reports
**only the delta** — new subdomains, newly-exposed hosts/ports/services, fresh vuln
findings — rather than a full re-scan wall.

State under `~/engagements/asm/<scope>/`. Passive/light-touch, hard-scoped to a domain/
ASN allowlist. First run sets the baseline; later runs report what changed. New exposures
escalate to [[Blue-Team-Tools|threat-hunt]] / [[detection-engineer]]. Sits in the
red→blue loop as continuous external monitoring.
