---
title: Architecture Overview
tags: [architecture, overview, pi5]
updated: 2026-07-27
---

# Architecture Overview

Back to [[00-Index]].

## The one-paragraph version

A Raspberry Pi 5 (arm64, Kali Rolling) runs **Claude Code** as an AI operator. Claude reaches the outside world through **MCP servers** — two offensive C2 backends ([[mcp-sliver-c2|Sliver]], [[mcp-mythic|Mythic]]), a stack of offensive tooling ([[mcp-hexstrike|hexstrike]], [[mcp-kali-server|MCP-Kali-Server]], [[mcp-pentest-ai|pentest-ai]], [[mcp-wstg-pentest|wstg-pentest]], [[mcp-caido|Caido]], [[mcp-playwright|Playwright]]), and blue-team feeds ([[mcp-huntress|Huntress]], [[mcp-virustotal|VirusTotal]], [[mcp-greynoise|GreyNoise]]). On top sit the custom **operator skills** — subagent definitions that chain those MCP tools into repeatable engagement workflows, with a master [[operation]] orchestrator that runs the whole lifecycle. Local **network sensors** ([[Network-Sensors|Suricata + Zeek + bettercap]]) capture the wire so red-team activity can be fed straight back into detection engineering.

## The layer cake

```
┌─────────────────────────────────────────────────────────────┐
│  OPERATOR SKILLS  (~/.claude/agents/*.md)                    │
│  engagement-start · osint-profile · generate-payload ·        │
│  pivot-analysis · triage-alerts · detection-engineer · debrief│
├─────────────────────────────────────────────────────────────┤
│  ORCHESTRATION   Opus 5 (reasoning) + Haiku 4.5 (data fetch)  │
├─────────────────────────────────────────────────────────────┤
│  MCP SERVERS  (~/.claude.json → mcpServers)                  │
│  Offensive:  sliver-c2 · mythic · hexstrike · mcp-kali-server │
│              pentest-ai · wstg-pentest · caido · playwright   │
│  Defensive:  huntress (claude.ai) · virustotal                │
├─────────────────────────────────────────────────────────────┤
│  INFRASTRUCTURE                                              │
│  Sliver daemon · Mythic Docker (8 containers) ·               │
│  Suricata 7.0.10 · Zeek 8.2.1 · bettercap 2.41.5             │
├─────────────────────────────────────────────────────────────┤
│  HOST   Raspberry Pi 5 · arm64 · Kali Rolling · Go 1.26.5     │
└─────────────────────────────────────────────────────────────┘
```

## Orchestration model (the important idea)

Every skill runs on the same pattern:

- **Opus 5** (`claude-opus-5`) is the orchestrator — it does the *reasoning*: interpreting context, making engagement decisions, correlating data, writing the final artifact.
- **Haiku 4.5** (`claude-haiku-4-5-20251001`) subagents do the *fetching* — the API calls, log pulls, and templated formatting that need no strategy.

The rule repeated in every skill: *anything that is primarily an API call, data retrieval, or templated formatting → spawn a Haiku subagent; reserve Opus reasoning for interpretation and writing.* Skills spawn subagents **in parallel** wherever the data sources are independent (e.g. [[debrief]] fans out to five collectors at once).

## The red → blue feedback loop

This is what makes the stack more than a pile of tools. Because the same box runs the offense **and** watches the wire:

1. Red team runs a TTP via [[mcp-sliver-c2|Sliver]] / [[mcp-mythic|Mythic]] (and [[web-assess]] for the web exploitation phase).
2. [[Network-Sensors|Suricata/Zeek]] capture the traffic; [[mcp-huntress|Huntress]] reports what the EDR caught.
3. [[triage-alerts]] correlates "what we did" against "what got detected" — classifying each alert as expected-TP, noise, or genuinely unknown. [[mcp-greynoise|GreyNoise]] answers *is this internet noise or targeted?* and [[mcp-virustotal|VirusTotal]] answers *is it known-bad?* — together they cut the sensor noise so the real signal stands out.
4. [[detection-engineer]] turns each TTP into Sigma + YARA + Suricata rules and files them in the [[Detection-Library]]. [[generate-payload]] can even seed a detection stub *before* the implant deploys.
5. [[debrief]] rolls it all up — attack path **plus** the detection-gap analysis — into a client report.

The [[Detection-Library]] compounds across engagements and becomes a deliverable in its own right.

## Orchestration + operations layer

Three skills sit above/around the lifecycle: [[operation]] (the master conductor that chains every specialist with operator gates), [[stack-status]] (shared preflight — is everything up?), and [[engagement-backup]] (protect the deliverables). See [[Operator-Skills]].

## Data / output conventions

- **Engagement artifacts:** `~/engagements/` (briefs, OSINT profiles, pivot sheets, triage reports, debriefs)
- **Detection library:** `~/engagements/detection-library/{sigma,yara,network}/` + `INDEX.md`
- **Sensor logs:** Suricata `/var/log/suricata/eve.json` · Zeek `/opt/zeek/logs/current/`

## Related

- [[Replication-Guide]] · [[Reboot-Runbook]] · [[Operator-Skills]] · [[MCP-Servers]]
