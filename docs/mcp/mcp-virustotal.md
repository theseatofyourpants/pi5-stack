---
title: VirusTotal MCP
tags: [mcp, enrichment, blueteam, virustotal]
tool_prefix: "mcp__virustotal__"
transport: stdio
updated: 2026-08-01
---

# VirusTotal MCP

Part of [[MCP-Servers]]. The IOC/malware enrichment layer for the blue-team workflows.

## What it is
MCP wrapper for the VirusTotal API — reputation and behavior lookups for files, URLs, domains, and IPs.

## Config (`~/.claude.json`)
```jsonc
"virustotal": {
  "command": "/usr/share/nodejs/corepack/shims/npx",
  "args": ["-y", "@burtthecoder/mcp-virustotal"],
  "env": { "VIRUSTOTAL_API_KEY": "<key>" }
}
```
- Source: `@burtthecoder/mcp-virustotal` (Node, via npx)
> [!warning] Env-var name (fixed 2026-08-01)
> The package reads **`VIRUSTOTAL_API_KEY`**, not `VT_API_KEY`. The config previously set the wrong name, so the server died on startup ("Failed to connect") with a valid key sitting right there. If VT ever shows "Failed to connect", check the env-var name first — see [[Stack-Ops-Skills|mcp-doctor]]. (npm is pinned via corepack to 11.19.0 on node 22 — a mismatched npm can also break npx servers.)
- **Free tier limits: 500 lookups/day, 4/min** → skills batch calls and stay under 4/min.

## Tools (prefix `mcp__virustotal__`)
- `analyze_file` — hash reputation (detection ratio, threat family, first/last seen)
- `analyze_url` · `analyze_domain` · `analyze_ip_address` — infra reputation
- `get_file_behavior` — sandbox behavioral report (strings, network IOCs, JA3)

## Basic usage
```
analyze_file("<sha256>")     → 45/70 detections, "Mimikatz"
analyze_ip_address("1.2.3.4")→ prior malicious history?
get_file_behavior("<hash>")  → JA3 / dropped files for YARA candidates
```

## Used by skills
- [[triage-alerts]] — enrich IOCs on UNKNOWN alerts (a 40/70 hash → immediate containment)
- [[detection-engineer]] — sample lookup → high-fidelity YARA strings + network IOCs
- [[debrief]] — credential/payload hash enrichment (is our hash already in breach DBs?)
- [[osint-profile]] — target IP/domain reputation + historical-compromise flags
