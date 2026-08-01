---
title: Mythic C2 Server
tags: [infrastructure, c2, mythic, docker]
version: "3.4.0"
updated: 2026-07-27
---

# Mythic C2 Server

Back to [[00-Index]]. The backend behind [[mcp-mythic]]. New to C2? Start with the [[C2-Primer]].

## What it is
Mythic v3.4.0 C2 — a multi-agent, multi-operator framework running as 8 Docker containers, managed by `mythic-cli` (built with [[Replication-Guide|Go 1.26.5]]).

## Install / layout
- CLI: `~/Mythic/mythic-cli`
- Web UI: `https://localhost:7443` — user `mythic_admin` (password stored in `~/.claude.json` / MCP env)
- Agents available: Apollo (Windows .NET), Poseidon (Linux/macOS), Medusa (cross-platform), Scarecrow (evasive Windows)

## Start / status
```bash
cd ~/Mythic && ./mythic-cli start
cd ~/Mythic && ./mythic-cli status
```
**All 8 containers must be up** for [[mcp-mythic]] to work. **Does not survive reboot** — see [[Reboot-Runbook]].

## Consumed by
- [[mcp-mythic]] → skills [[engagement-start]], [[generate-payload]], [[pivot-analysis]], [[triage-alerts]], [[detection-engineer]], [[debrief]]

## Related
- [[C2-Primer]] (how C2 works, conceptually) · [[Sliver-Server]] · [[Architecture-Overview]]
