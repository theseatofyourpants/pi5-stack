---
title: /triage-alerts
tags: [skill, agent, blueteam, detection, correlation]
skill_name: triage-alerts
model: claude-opus-5
file: ~/.claude/agents/triage-alerts.md
updated: 2026-07-27
---

# /triage-alerts

Part of [[Operator-Skills]]. The blue-team correlation engine — the first half of the [[Architecture-Overview|red→blue loop]].

## Purpose
Pull the Huntress alert feed, correlate it against *known* red-team activity, and classify each alert. The key insight: **you know what offense occurred**, so an alert either confirms your technique got caught (good detection evidence), is expected C2 noise, or — if it matches nothing you did — is a potential third-party threat that gets immediate attention.

## MCPs it drives
[[mcp-huntress]] · [[mcp-mythic]] · [[mcp-sliver-c2]] · [[mcp-virustotal]] · [[mcp-greynoise]] (+ [[Network-Sensors]] logs via Bash)

## Workflow
1. **Phase 1 — 4 parallel Haiku subagents:** (1) Huntress incidents/escalations/signals; (2) Mythic callbacks + recent tasks; (3) Sliver sessions/beacons; (4) local sensors — Suricata `eve.json` alerts + Zeek `conn.log` from `/opt/zeek/logs/current/`.
2. **Phase 1b — Sensor correlation** (Opus): Suricata↔Huntress matches (double-confirmed), Suricata-only (EDR gap), Huntress-only (no-network TTP), Suricata on a non-C2 host (→ UNKNOWN—INVESTIGATE). **GreyNoise enrichment** on every external source IP — keyless — to strip internet-scanner noise: `noise+benign` → dismiss, `seen:false` on an internal hit → the strongest "targeted at us" signal.
3. **Phase 2 — Correlation** (Opus): host match → timestamp overlap (±15 min) → TTP match, then classify:
   - **EXPECTED — TP** (caught our technique) · **EXPECTED — NOISE** (beacon artifact) · **UNKNOWN — INVESTIGATE** (not in our C2 → escalate) · **NOISE — BENIGN** (environmental).
4. **Phase 3 — Runbook:** detection-coverage report (DETECTED/MISSED per technique), **VT + GreyNoise enrichment** of IOCs on UNKNOWN alerts (reputation × intent verdict matrix), and a containment runbook for each UNKNOWN.

## Output
`~/engagements/triage-{YYYY-MM-DD-HHMM}.md` + summary (alerts by class, detection coverage %).

## Notes
- Convert all timestamps to UTC before correlating.
- Any in-scope host in Huntress but absent from C2 inventory → treat as UNKNOWN—INVESTIGATE regardless of how benign it looks.
- Hands undetected TTPs to [[detection-engineer]]; its findings feed [[debrief]] §8.
