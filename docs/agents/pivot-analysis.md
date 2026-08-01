---
title: /pivot-analysis
tags: [skill, agent, post-exploitation, pivoting]
skill_name: pivot-analysis
model: claude-opus-5
file: ~/.claude/agents/pivot-analysis.md
updated: 2026-07-27
---

# /pivot-analysis

Part of [[Operator-Skills]]. Turns live implants into a topology map + ready-to-run pivot paths.

## Purpose
Enumerate all active Sliver sessions/beacons and Mythic callbacks, pull network telemetry from each in parallel, build a topology, and surface prioritized pivot paths with exact commands.

## MCPs it drives
[[mcp-sliver-c2]] · [[mcp-mythic]]

## Workflow
1. **Verify + enumerate:** Mythic auth + `sliver_version`; then `sliver_sessions`, `sliver_beacons`, `mythic_get_active_callbacks`. Stop if nothing is active.
2. **Collect network data** (one Haiku subagent per implant, parallel): interfaces/CIDRs (`sliver_ifconfig` or `ifconfig`/`ipconfig` task), connections (`sliver_netstat` / `netstat`/`ss`), processes (flag EDR/AV/high-priv). *OPSEC: stagger Mythic task issuance 2–3s.*
3. **Build topology** (Opus): subnet map, reachable-host inventory, segment/chokepoint analysis, AD indicators (LDAP/Kerberos/SMB/RPC), EDR presence → ASCII map.
4. **Surface pivot paths:** pick mechanism (Sliver TCP pivot / SOCKS / Mythic p2p / port-forward) per segment; give source implant, target, rationale, exact commands, OPSEC notes.
5. **Pivot command sheet** with active-implant table, topology, numbered pivot paths.

## Output
`~/engagements/pivot-{timestamp}.md` + console sheet.

## Notes
- Confirms before executing any pivot that creates a new listener.
- Dead Mythic beacons are noted but don't block. Low-priv implants flagged as poor pivot sources.
