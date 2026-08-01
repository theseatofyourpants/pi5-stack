---
title: /stack-status
tags: [skill, agent, ops, preflight, health]
skill_name: stack-status
model: claude-opus-5
file: ~/.claude/agents/stack-status.md
updated: 2026-07-27
---

# /stack-status

Part of [[Operator-Skills]]. **New skill** — the shared preflight that ends every skill reinventing its own health checks.

## Purpose
One-shot health check of the whole stack: C2 backends, network sensors, and every MCP server's backing service. Prints a status board and the exact restart command for anything down. Run after a reboot or at the top of any engagement.

## MCPs it drives
[[mcp-sliver-c2]] (`sliver_version`) · [[mcp-mythic]] (`mythic_is_authenticated`) · [[mcp-greynoise]] (keyless canary) · [[mcp-virustotal]] (config check) — plus Bash probes.

## What it checks
- **C2:** [[Sliver-Server]] daemon (`sliver_version`), [[Mythic-Server]] (`mythic-cli status`, 8 containers)
- **Sensors:** [[Network-Sensors|Suricata]] (`suricata -V` + eve.json activity), Zeek (`zeekctl status` + `/opt/zeek/logs/current/`), bettercap present
- **MCP layer:** reads `mcpServers` from `~/.claude.json`; curls health endpoints for hexstrike (:8888) and kali-server (:5000); fires a keyless GreyNoise canary (`167.94.138.34` → expect Censys)
- **Workspace:** `~/engagements` + detection-library row count

## Output
A status board (● up / ○ down / ◐ degraded) with per-component fix commands, ending in a single `READY FOR ENGAGEMENT: YES/NO` verdict. Read-only except one Mythic login attempt + one keyless GreyNoise lookup.

## Notes
- Privileged fixes are surfaced as commands for the operator to run via `! command` (no passwordless sudo).
- Called first by [[engagement-start]] and [[operation]]; the fastest post-reboot check. Complements [[Reboot-Runbook]].
