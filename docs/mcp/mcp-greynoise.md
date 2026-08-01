---
title: GreyNoise MCP
tags: [mcp, enrichment, blueteam, greynoise, custom-built]
tool_prefix: "mcp__greynoise__"
transport: stdio
updated: 2026-08-01
---

# GreyNoise MCP

Part of [[MCP-Servers]]. **Custom-built for this stack** — there is no off-the-shelf GreyNoise MCP on npm or PyPI, so it was written locally (a small FastMCP server) following the same pattern as the other local MCPs.

## What it answers
GreyNoise answers the one question VirusTotal can't: **"is this IP scanning the entire internet, or is it targeting *us*?"** — i.e. intent, not just reputation. It's the blind spot that made this the top gap: [[Network-Sensors|Suricata]] fires constantly on internet background radiation, and without GreyNoise every mass-scanner looks like an attack.

## Config (`~/.claude.json`)
```jsonc
"greynoise": {
  "command": "/home/tsoyp/greynoise-mcp/venv/bin/python",
  "args": ["/home/tsoyp/greynoise-mcp/server.py"],
  "env": { "GREYNOISE_API_KEY": "<key>" }   // KEYED as of 2026-08-01
}
```
- Server code: `~/greynoise-mcp/server.py` (FastMCP + httpx, venv alongside)
- **API key now set & validated (2026-08-01)** — the full context/riot/quick/gnql tools are live. (Still works keyless via the Community endpoint as a fallback; free keyed tier needs a *business* email — Gmail doesn't qualify.)

> [!warning] Migrated v2 → v3 (2026-08-01)
> GreyNoise **EOL'd its entire v2 API on 2026-01-01**, so the keyed tools were hitting `410 Gone`. `server.py` was repointed to v3:
> - `context_ip` & `riot_ip` → `GET /v3/ip/{ip}` (v3 unified them — `internet_scanner_intelligence` + `business_service_intelligence` in one response)
> - `quick_ip` → `GET /v3/ip/{ip}?quick=true`
> - `gnql` → `GET /v3/gnql?query=&size=` (GET, **not** POST as the migration-matrix doc wrongly claims)
> - community stays `/v3/community/{ip}`. **Do not revert to `/v2/*`.**

## Tools (prefix `mcp__greynoise__`)
| Tool | Key needed? | Returns |
|------|-------------|---------|
| `greynoise_community_ip(ip)` | No (keyless) | noise, riot, classification, actor name, last_seen |
| `greynoise_context_ip(ip)` | Yes | full context (v3 unified): actor, tags/TTPs, spoofable, VPN/TOR, ASN/org/geo + business-service block |
| `greynoise_riot_ip(ip)` | Yes | known-benign business service (CDN/cloud) lookup |
| `greynoise_quick_ip(ip)` | Yes | fast noise/riot booleans for batching |
| `greynoise_gnql(query, size)` | Yes | GNQL search across the noise dataset (infra hunting) |

Tools that need a key degrade gracefully (`{"error":"no_api_key", ...}`) so a subagent can still proceed on community data.

## Verified behavior
- Keyed GNQL (`classification:malicious`) → HTTP 200 with data → **key authenticated** ✓ (2026-08-01)
- `greynoise_community_ip("167.94.138.34")` → `noise:true, classification:benign, name:Censys` ✓
- `greynoise_community_ip("8.8.8.8")` → `seen:false` (not a scanner) — handled cleanly ✓

## Used by skills
- [[triage-alerts]] — noise-vs-targeted enrichment during sensor correlation, and the VT+GreyNoise verdict matrix for UNKNOWN alerts (a GreyNoise `seen:false` on an internal-host hit = the strongest "aimed at you" signal)
- [[Blue-Team-Tools|ioc-enrich]] — the standalone one-shot verdict that bundles GreyNoise + VT + Huntress
- [[Blue-Team-Tools|threat-hunt]] — infra enrichment + GNQL adjacent-infra pivots during hunts
- [[osint-profile]] — distinguish a target's real infra from noisy shared hosting; RIOT front detection; GNQL adjacent-infra hunting
- [[stack-status]] — used as a liveness canary for the MCP layer

## Related
- [[mcp-virustotal]] (reputation — the complementary signal) · [[Stack-Ops-Skills|mcp-doctor]] (the repair runbook that fixed this) · [[Replication-Guide]] (build steps)
