---
title: /engagement-start
tags: [skill, agent, setup, redteam]
skill_name: engagement-start
model: claude-opus-5
file: ~/.claude/agents/engagement-start.md
updated: 2026-07-27
---

# /engagement-start

Part of [[Operator-Skills]]. Run this first, every engagement.

## Purpose
Full engagement setup: verify backends + sensors are alive, create a Mythic operation, initialize [[mcp-wstg-pentest|WSTG]] tracking, generate a tailored recon plan, and stand up C2 listeners — ending in a written engagement brief.

## MCPs it drives
[[mcp-mythic]] · [[mcp-sliver-c2]] · [[mcp-wstg-pentest]] (+ Bash health checks for [[Network-Sensors]])

## Workflow
1. **Collect params** (one question block): target, scope, engagement type (pentest / red-team / assumed-breach / BAS / phish), duration, objectives, environment context, rules of engagement.
2. **Verify backends alive:** `sliver_version`, `mythic_is_authenticated`; plus Bash checks for Suricata (`systemctl is-active suricata`) and Zeek (`/opt/zeek/bin/zeekctl status`) — offers start commands if down.
3. **Init Mythic op** (Haiku subagent): create + set current operation `{target}-{YYYY-MM-DD}`.
4. **Init WSTG tracking** tailored to engagement type (full WSTG for pentest; post-ex heavy for red-team; ATT&CK IDs for BAS; initial-access for phish).
5. **Generate recon plan** (Opus reasoning — not delegated): prioritized passive→active→targeted phases.
6. **Listener setup:** recommend Sliver transport by environment, or guide Mythic agent/profile choice.
7. **Write brief** to `~/engagements/{op}-brief.md` (includes SURICATA/ZEEK status lines).

## Output
`~/engagements/{operation-name}-brief.md` + console brief box.

## Notes
- Neither C2 backend survives reboot — this skill's health checks catch that. See [[Reboot-Runbook]].
- Feeds directly into [[osint-profile]] (which reuses the scope) and sets the operation that [[debrief]] later summarizes.
