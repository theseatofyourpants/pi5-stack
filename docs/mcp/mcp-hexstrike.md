---
title: hexstrike MCP
tags: [mcp, offensive, recon, toolkit, hexstrike]
tool_prefix: "mcp__hexstrike__"
transport: stdio
updated: 2026-07-27
---

# hexstrike MCP

Part of [[MCP-Servers]]. The broadest offensive toolbox in the stack.

## What it is
hexstrike-ai (community edition) wraps 150+ security tools plus AI-driven meta-workflows behind one MCP. It's the go-to for recon, web, network, cloud, binary/RE, and payload generation.

## Config (`~/.claude.json`)
```jsonc
"hexstrike": {
  "command": "/home/tsoyp/hexstrike-ai-community-edition/hexstrike-env/bin/python3",
  "args": ["/home/tsoyp/hexstrike-ai-community-edition/hexstrike_mcp.py",
           "--server", "http://localhost:8888"]
}
```
- Python venv + a local hexstrike server on `:8888`

## Tool families (prefix `mcp__hexstrike__`)
- **Recon/OSINT:** `subfinder_scan`, `amass_scan`, `bbot_scan`, `dnsenum_scan`, `whois_lookup`, `httpx_probe`, `waybackurls_discovery`, `gau_discovery`, `detect_technologies_ai`
- **Web:** `nuclei_scan`, `ffuf_scan`, `feroxbuster_scan`, `katana_crawl`, `dalfox_xss_scan`, `sqlmap_scan`, `wpscan_analyze`, `arjun_scan`, `jwt_analyzer`, `graphql_scanner`
- **Network:** `nmap_scan`, `masscan_high_speed`, `rustscan_fast_scan`, `netexec_scan`, `enum4linux_ng_advanced`, `responder_credential_harvest`
- **Binary/RE/pwn:** `ghidra_analysis`, `radare2_analyze`, `gdb_peda_debug`, `pwntools_exploit`, `ropgadget_search`, `angr_symbolic_execution`
- **Cloud/container:** `prowler_scan`, `trivy_scan`, `kube_hunter_scan`, `checkov_iac_scan`
- **AI workflows:** `ai_reconnaissance_workflow`, `ai_vulnerability_assessment`, `ai_generate_attack_suite`, `intelligent_smart_scan`, `bugbounty_comprehensive_assessment`

## Basic usage
```
subfinder_scan(domain) → httpx_probe(hosts) → nuclei_scan(live)
# or let the AI meta-tool drive:
ai_reconnaissance_workflow(target)
```

## Used by skills
- [[osint-profile]] — the recon engine: WHOIS, DNS, CT-log subdomains, tech fingerprinting, param discovery
