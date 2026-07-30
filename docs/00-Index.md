---
title: Pi 5 Red/Blue Team Stack — Map of Content
tags: [moc, index, pi5, redteam, blueteam]
platform: "Raspberry Pi 5 / Kali Rolling / arm64"
updated: 2026-07-27
---

# 🍓 Pi 5 Red/Blue Team Stack — Map of Content

The home base for the whole build. This vault maps the **AI-orchestrated C2 + detection engineering stack** running on a Raspberry Pi 5 (arm64, Kali Rolling): the MCP servers wired into Claude Code, the custom operator skills that drive them, and the infrastructure they sit on.

> [!info] How to read this vault
> Start with [[Architecture-Overview]] for the big picture, then follow the wikilinks. Every MCP server and every skill has its own atomic note. The [[Replication-Guide]] rebuilds the whole thing from bare metal.

## 🗺️ Core maps

- [[Architecture-Overview]] — how everything fits together (the orchestration model, data flows, the layer cake)
- [[Replication-Guide]] — rebuild from scratch, including the arm64 gotchas that cost real time
- [[Reboot-Runbook]] — what survives a reboot and what to restart by hand

## 🧩 MCP servers

The tool surface Claude Code can call. Index: [[MCP-Servers]]

| Server | Role | Note |
|--------|------|------|
| Sliver C2 | Offensive C2 backend | [[mcp-sliver-c2]] |
| Mythic C2 | Offensive C2 backend | [[mcp-mythic]] |
| Caido | Web proxy / intercept | [[mcp-caido]] |
| VirusTotal | IOC / malware enrichment | [[mcp-virustotal]] |
| GreyNoise | IP intent — noise vs targeted (custom, keyless) | [[mcp-greynoise]] |
| Huntress | Blue-team EDR alert feed | [[mcp-huntress]] |
| hexstrike | 150+ offensive tool wrappers | [[mcp-hexstrike]] |
| MCP-Kali-Server | Kali tool + shell/SSH runner | [[mcp-kali-server]] |
| wstg-pentest | OWASP WSTG methodology engine | [[mcp-wstg-pentest]] |
| pentest-ai | Structured engagement scanner | [[mcp-pentest-ai]] |
| Playwright | Browser automation | [[mcp-playwright]] |

## 🤖 Operator skills

Custom `~/.claude/agents/*.md` orchestrators. Index: [[Operator-Skills]]

| Skill | Phase | Note |
|-------|-------|------|
| `/operation` | **Master orchestrator** | [[operation]] |
| `/stack-status` | Preflight / health | [[stack-status]] |
| `/engagement-start` | Setup | [[engagement-start]] |
| `/osint-profile` | Recon | [[osint-profile]] |
| `/web-assess` | Exploitation | [[web-assess]] |
| `/generate-payload` | Weaponization | [[generate-payload]] |
| `/pivot-analysis` | Post-exploitation | [[pivot-analysis]] |
| `/triage-alerts` | Blue-team correlation | [[triage-alerts]] |
| `/detection-engineer` | Detection eng | [[detection-engineer]] |
| `/debrief` | Reporting | [[debrief]] |
| `/engagement-backup` | Data protection | [[engagement-backup]] |
| `/device-assess` | Unattended device scan (testbed) | [[device-assess]] |
| `/hotpot-maintain` | Deception-layer keeper (testbed) | [[hotpot-maintain]] |

## 🏗️ Infrastructure

- [[C2-Primer]] — **how Sliver & Mythic actually work** (session vs beacon, listeners, agents, pivoting) — start here if C2 is new
- [[Sliver-Server]] — Sliver daemon + operator config
- [[Mythic-Server]] — Mythic Docker stack
- [[Network-Sensors]] — Suricata + Zeek + bettercap
- [[Detection-Library]] — the growing Sigma/YARA/network rule corpus
- [[Autonomous-AP-Testbed]] — dongle-triggered consent-gated AP that scans devices that opt in (hybrid captive + per-MAC egress)
- [[Adversarial-Honeypot-Hotpot]] — deception layer on the same AP: fake bait services + honeytokens that observe & attribute unbidden probers (no compromise of the prober)
- [[wifi-failsafe]] — fallback AP + captive portal on wlan0 when the Pi loses Wi-Fi

## 🔑 Fast facts

- **Host:** Raspberry Pi 5, arm64, Kali Rolling, no passwordless sudo (privileged cmds run via `! ` prefix in the terminal)
- **MCP config:** global `~/.claude.json` → `mcpServers`
- **Skills:** `~/.claude/agents/`
- **Engagement output:** `~/engagements/`
- **Orchestration model:** Opus 5 reasons, Haiku 4.5 subagents fetch data — see [[Architecture-Overview]]
