---
title: GreyNoise MCP
tags: [mcp, enrichment, blueteam, greynoise, custom-built]
tool_prefix: "mcp__greynoise__"
transport: stdio
updated: 2026-07-27
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
  "env": { "GREYNOISE_API_KEY": "" }   // empty = keyless community mode
}
```
- Server code: `~/greynoise-mcp/server.py` (FastMCP + httpx, venv alongside)
- **Works keyless out of the box** via the GreyNoise Community endpoint (rate-limited, no signup).
- Add a `GREYNOISE_API_KEY` to unlock the full context/riot/gnql tools.

## Tools (prefix `mcp__greynoise__`)
| Tool | Key needed? | Returns |
|------|-------------|---------|
| `greynoise_community_ip(ip)` | No (keyless) | noise, riot, classification, actor name, last_seen |
| `greynoise_context_ip(ip)` | Yes | full context: actor, tags/TTPs, spoofable, VPN/TOR, ASN/org/geo |
| `greynoise_riot_ip(ip)` | Yes | known-benign business service (CDN/cloud) lookup |
| `greynoise_quick_ip(ip)` | Yes | fast noise/riot booleans for batching |
| `greynoise_gnql(query, size)` | Yes | GNQL search across the noise dataset (infra hunting) |

Tools that need a key degrade gracefully (`{"error":"no_api_key", ...}`) so a subagent can still proceed on community data.

## Verified behavior
- `greynoise_community_ip("167.94.138.34")` → `noise:true, classification:benign, name:Censys` ✓
- `greynoise_community_ip("8.8.8.8")` → `seen:false` (not a scanner) — handled cleanly ✓

## Used by skills
- [[triage-alerts]] — noise-vs-targeted enrichment during sensor correlation, and the VT+GreyNoise verdict matrix for UNKNOWN alerts (a GreyNoise `seen:false` on an internal-host hit = the strongest "aimed at you" signal)
- [[osint-profile]] — distinguish a target's real infra from noisy shared hosting; RIOT front detection; GNQL adjacent-infra hunting
- [[stack-status]] — used as a keyless liveness canary for the MCP layer

## Related
- [[mcp-virustotal]] (reputation — the complementary signal) · [[Replication-Guide]] (build steps)
