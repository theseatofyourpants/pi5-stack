---
title: Blue-Team Tools
tags: [blueteam, defensive, hunt, phishing, enrichment, agent, skill]
updated: 2026-08-01
---

# Blue-Team Tools

Part of [[Operator-Skills]]. Defensive capabilities added 2026-08-01 alongside the offensive expansion — they turn the stack into a real purple-team box. Two are agents (`~/.claude/agents/`), two are skills (`~/.claude/skills/`).

## The agents
| Agent | Role | Uses |
|-------|------|------|
| `threat-hunt` | Hypothesis-driven hunt across [[Network-Sensors|Suricata/Zeek]] logs + [[mcp-huntress|Huntress]]; pivots, enriches, surfaces detection gaps | hexstrike `threat_hunting_assistant`, [[mcp-greynoise]], [[mcp-virustotal]] — **de-conflicts your own C2** ([[mcp-mythic]]/[[mcp-sliver-c2]]) so red-team traffic isn't mistaken for adversary |
| `phish-analyze` | Triage a suspect email — headers/links/attachments → VT/GreyNoise → verdict | the **connected [[mcp-huntress|Gmail]] MCP** (the only consumer of it); analysis-only, never clicks/replies |

## The skills
| Skill | Role |
|-------|------|
| `ioc-enrich` | One-shot verdict for a single IP/hash/domain/URL: [[mcp-virustotal|VT]] (reputation) + [[mcp-greynoise|GreyNoise]] (intent) + [[mcp-huntress|Huntress]] (seen in our env?). The standalone version of what [[triage-alerts]] does across a whole feed |
| `sensor-tune` | [[Network-Sensors|Suricata/Zeek]] FP reduction + rule thresholds + `suricata-update` + coverage-gap check vs the [[Detection-Library]] |

## The purple loop
Offensive [[Post-Exploitation]] / [[web-assess]] / [[phish-sim]] actions become `threat-hunt` hypotheses; gaps found feed [[detection-engineer]] → [[Detection-Library]]; [[triage-alerts]] consumes the cleaner alerts `sensor-tune` produces. `ioc-enrich` is the quick-lookup entry point everything else reuses.

## Related
- [[triage-alerts]] · [[detection-engineer]] · [[Network-Sensors]] · [[Adversarial-Honeypot-Hotpot]] (hot-pot bait feeds these)
