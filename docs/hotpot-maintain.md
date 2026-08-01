---
title: /hotpot-maintain
tags: [skill, agent, blueteam, deception, honeypot, testbed]
skill_name: hotpot-maintain
model: claude-opus-5
file: ~/.claude/agents/hotpot-maintain.md
updated: 2026-08-01
---

# /hotpot-maintain

Part of [[Operator-Skills]]. The keeper/monitor for the [[Adversarial-Honeypot-Hotpot]] deception layer on the [[Autonomous-AP-Testbed]]. **Read / inspect / rotate / report only — it never attacks, scans back, or touches the prober.** (Note added 2026-08-01 to fix a dangling vault link — the agent has existed since the hot-pot was built.)

## What it does
- **Health-check** the bait services (Cowrie SSH/Telnet, the read-only SMB bait share, the fake router-admin page, the honeytoken collector).
- **Assert the isolation safety invariant** — the deception subnet (172.31.66.0/24) can answer probers but can NEVER egress or reach the LAN (DOCKER-USER firewall). This assertion is the whole safety basis of the layer.
- **Rotate / re-seed honeytokens** (`seed-tokens.py`; local collector or canarytokens backend).
- **Roll up captured hostile-recon intel** for the blue-team pipeline.

## Posture
Operator-run, deliberately has **no offensive tooling**. The hard design line: observe & attribute only — it never serves anything that runs on or controls the prober (that would be hack-back, which is declined). Honeytokens are passive phone-home telemetry.

## Feeds
Bait hits → [[Network-Sensors|Suricata]] (dedicated wlan1 instance when armed) + [[Network-Sensors|Zeek]] JA3/JA4/HASSH → [[triage-alerts]] / [[Blue-Team-Tools|threat-hunt]] / [[detection-engineer]] (TTP → Sigma/YARA). Enrichment via [[mcp-greynoise]] / [[mcp-virustotal]].

## Output
`~/engagements/hotpot-{ts}.md`

## Related
- [[Adversarial-Honeypot-Hotpot]] (the layer it tends) · [[Autonomous-AP-Testbed]] · [[Blue-Team-Tools]]
