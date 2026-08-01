---
title: /detection-engineer
tags: [skill, agent, blueteam, detection, sigma, yara]
skill_name: detection-engineer
model: claude-opus-5
file: ~/.claude/agents/detection-engineer.md
updated: 2026-07-27
---

# /detection-engineer

Part of [[Operator-Skills]]. Turns an offensive TTP into production detection logic — the second half of the [[Architecture-Overview|red→blue loop]].

## Purpose
Take a TTP (MITRE ID, tool name, or description of what was run) and generate a Sigma rule, a YARA signature, and network/Suricata indicators; assess whether current tooling would catch it; and append everything to the growing [[Detection-Library]].

## MCPs it drives
[[mcp-mythic]] (ATT&CK lookups + task/artifact data) · [[mcp-huntress]] (coverage check) · [[mcp-wstg-pentest]] (technique context) · [[mcp-virustotal]] (sample behavior → YARA strings) · [[Network-Sensors]] (log validation)

## Workflow
- **Step 0 — Intake:** TTP, execution details (cmdline/process/target/network/file), target OS, did Huntress detect it? (Auto-filled if invoked from [[debrief]] or [[triage-alerts]].)
- **Step 1 — Context** (2 parallel Haiku subagents): MITRE technique detail (data sources, defenses) + VirusTotal sample lookup (behavioral strings, JA3, IOCs).
- **Step 2 — Sigma** (Opus): spec-correct rule with proper logsource, specific conditions, realistic `falsepositives`, level; two variants (high-fidelity + behavioral).
- **Step 3 — YARA** (Opus): disk artifact / memory / network payload strings; specific conditions, not "any of them".
- **Step 4 — Network + Suricata rule** (Opus): IOC list (IPs, domains, URIs, JA3, UAs) + a Suricata rule (SID 9000000+, flow/detection_filter for beacons).
- **Step 4b — Suricata log validation** (Haiku): grep `eve.json` + Zeek `conn.log` to see if it *would* fire / whether an ET rule already caught it.
- **Step 5 — Coverage gap** (Haiku checks Huntress): verdict `COVERED` / `COVERED — EVASION POSSIBLE` / `GAP — {reason}`.
- **Step 6 — Append to library:** write `sigma/`, `yara/`, `network/` files + update `INDEX.md`.

## Output
Files in [[Detection-Library]] (`~/engagements/detection-library/{sigma,yara,network}/` + `INDEX.md`) + console summary.

## Notes
- Quality over quantity; abstract C2 rules to the behavioral pattern so they catch variants, not just this exact Sliver/Mythic build.
- Called standalone or chained from [[triage-alerts]] / [[debrief]].
