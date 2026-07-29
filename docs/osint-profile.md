---
title: /osint-profile
tags: [skill, agent, recon, osint]
skill_name: osint-profile
model: claude-opus-5
file: ~/.claude/agents/osint-profile.md
updated: 2026-07-27
---

# /osint-profile

Part of [[Operator-Skills]]. Passive→active recon pipeline that builds a target dossier.

## Purpose
Chain OSINT tools in a disciplined passive-to-active sequence — never touching the target until the passive picture is complete — then synthesize a prioritized, operator-ready profile.

## MCPs it drives
[[mcp-hexstrike]] (recon engine) · [[mcp-kali-server]] (Shodan + second recon source) · [[mcp-virustotal]] (infra reputation) · [[mcp-greynoise]] (infra intent — noise/RIOT/GNQL) · bettercap ([[Network-Sensors]]) for wireless

## Workflow
- **Step 0 — Scope intake:** target, engagement-type context, known intel, exclusions, whether physical/wireless is in scope. (Skipped if run from [[engagement-start]].)
- **Phase 0W — Wireless survey** (only if in scope): `sudo bettercap -eval "wifi.recon on; sleep 30; wifi.show; quit"` → SSIDs/BSSIDs, open + WPS networks, corp-named SSIDs.
- **Phase 1 — Passive** (parallel Haiku subagents, no target contact): WHOIS, DNS, Shodan, CT-log subdomains, Wayback/GAU URL corpus. Then Opus review of surface.
- **Phase 2 — Semi-active** (DNS only): active subdomain brute (amass/assetfinder), fierce zone recon, passive tech fingerprint.
- **Phase 3 — Active** (only if permitted): httpx probe all subdomains → pick top 10–15 → hakrawler/paramspider/nuclei tech templates.
- **Phase 3b — VirusTotal + GreyNoise enrichment:** VT `analyze_ip_address`/`analyze_domain` on priority infra → historical-compromise / current-detection flags; GreyNoise `community_ip` (keyless) to separate the target's real infra from noisy shared hosting, flag RIOT (CDN/cloud) fronts, and — with a key — `gnql` to hunt adjacent infra in the target's ASN.
- **Phase 4 — Synthesis** (Opus): infrastructure map, high-value targets *with rationale*, credential attack surface, historical exposure, tech fingerprint, Shodan intel, DNS/SPF observations, and 3–5 recommended first moves.

## Output
`~/engagements/osint-{domain}-{YYYY-MM-DD}.md` + console summary.

## Notes
- Never runs vuln scanning (that's a separate step). Respects bug-bounty scope strictly.
- Related: [[engagement-start]] (supplies scope), [[generate-payload]] (uses environment intel).
