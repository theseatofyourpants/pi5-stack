---
title: Sliver C2 MCP
tags: [mcp, c2, offensive, sliver]
tool_prefix: "mcp__sliver-c2__"
transport: stdio
updated: 2026-07-27
---

# Sliver C2 MCP

Part of [[MCP-Servers]]. Backend: [[Sliver-Server]].

## What it is
MCP wrapper around the Sliver C2 framework (BishopFox). Gives Claude programmatic control of the Sliver operator client — listeners, implant sessions/beacons, filesystem and process ops on implants, and pivoting.

## Config (`~/.claude.json`)
```jsonc
"sliver-c2": {
  "command": "/usr/bin/node",
  "args": [
    "/home/tsoyp/sec-sliver-c2-mcp/dist/index.js",
    "--operator-config", "/home/tsoyp/sliver-claude.cfg"
  ]
}
```
- Source: `schwarztim/sec-sliver-c2-mcp` (Node.js)
- Operator config `~/sliver-claude.cfg` (mTLS "claude-operator") → connects to daemon on `127.0.0.1:31337`
- **Requires the [[Sliver-Server]] daemon to be running.**

## Key tools (prefix `mcp__sliver-c2__`)
- **Recon/state:** `sliver_version`, `sliver_sessions`, `sliver_beacons`, `sliver_hosts`, `sliver_operators`
- **Listeners:** `sliver_start_https`, `sliver_start_mtls`, `sliver_start_dns`, `sliver_start_http`, `sliver_start_wg`, `sliver_kill_listener`
- **On-implant:** `sliver_ifconfig`, `sliver_netstat`, `sliver_ps`, `sliver_ls`, `sliver_cd`, `sliver_pwd`, `sliver_execute`, `sliver_shell`, `sliver_download`, `sliver_upload`, `sliver_screenshot`, `sliver_creds`
- **Pivoting:** `sliver_pivot_listeners`, `sliver_pivot_start_tcp`
- **Builds:** `sliver_implant_builds`, `sliver_implant_profiles`

## Basic usage
```
1. Ensure daemon up (see [[Reboot-Runbook]])
2. sliver_version            → confirm connectivity
3. sliver_start_https(...)   → stand up a listener
4. (implant calls back)
5. sliver_sessions / sliver_beacons → enumerate
```

## Used by skills
[[generate-payload]] · [[pivot-analysis]] · [[triage-alerts]] · [[debrief]] · [[engagement-start]]
