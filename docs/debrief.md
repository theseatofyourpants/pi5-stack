---
title: /debrief
tags: [skill, agent, reporting, blueteam]
skill_name: debrief
model: claude-opus-5
file: ~/.claude/agents/debrief.md
updated: 2026-07-27
---

# /debrief

Part of [[Operator-Skills]]. End-of-engagement report synthesizer — the closing move of the [[Architecture-Overview|red→blue loop]].

## Purpose
Collect all engagement data from every backend and sensor, then synthesize a professional security assessment report: executive summary, attack-path narrative, technical findings, credential exposure, MITRE coverage, **detection-engineering gaps**, and a prioritized remediation roadmap.

## MCPs it drives
[[mcp-mythic]] · [[mcp-sliver-c2]] · [[mcp-wstg-pentest]] · [[mcp-virustotal]] (+ [[Network-Sensors]] logs)

## Workflow
- **Phase 1 — 5 parallel Haiku collectors:** (1) WSTG findings/coverage/summary; (2) Mythic op data — callbacks, credentials, artifacts, downloads, screenshots, ATT&CK map, hosts; (3) Sliver sessions/beacons/hosts/builds; (4) **VirusTotal** enrichment of credential + payload hashes; (5) **local sensor evidence** — Suricata alerts from `eve.json` + Zeek logs from `/opt/zeek/logs/current/`. Also reads any brief/pivot files in `~/engagements/`.
- **Phase 2 — Synthesis** (Opus): writes for two audiences (execs + engineers), no filler.

## Report sections
1. Cover · 2. Executive summary (CISO-quotable risk statement) · 3. Scope & methodology · 4. Attack-path narrative (timeline) · 5. Technical findings (severity-ordered, CVSS, concrete remediation) · 6. Credential/data exposure (**incl. VT hash status column**) · 7. MITRE ATT&CK coverage by tactic · 8. **Detection-engineering gaps** (cross-ref Huntress + Suricata + ATT&CK; recommends `/detection-engineer` per top gap; references [[Detection-Library]] INDEX) · 9. Recommendations (7/30/90-day + strategic) · 10. Appendix (systems, output paths, implant build hashes).

## Output
`~/engagements/{operation-name}-debrief-{YYYY-MM-DD}.md` + console summary.

## Notes
- Client-facing tone — no slang, dates as YYYY-MM-DD.
- Section 8 is where the whole loop pays off: it reconciles what the red team did against what the blue tooling saw, and points at the [[Detection-Library]] as a standalone deliverable.
