---
title: MCP-Kali-Server
tags: [mcp, offensive, kali, shells, kali-server]
tool_prefix: "mcp__mcp-kali-server__"
transport: stdio
updated: 2026-08-01
---

# MCP-Kali-Server

Part of [[MCP-Servers]].

## What it is
A thin bridge to a running Kali box: run arbitrary commands, drive a curated set of Kali tools, manage reverse shells and SSH sessions, transfer files, and query Shodan.

## Config (`~/.claude.json`)
```jsonc
"mcp-kali-server": {
  "command": "/home/tsoyp/MCP-Kali-Server/venv/bin/python3",
  "args": ["/home/tsoyp/MCP-Kali-Server/mcp-server/mcp_server.py",
           "--server", "http://localhost:5000"]
}
```
- Python venv + kali-server Flask API on `:5000` (liveness at `/health`)
> [!note] Backend is now a systemd unit (2026-08-01)
> The `:5000` Flask backend runs as **`kali-server.service`** (User=tsoyp, enabled, Restart=on-failure) — it survives reboot. Was previously a manual `nohup` that died on reboot (found DOWN 2026-08-01 → systemd-ized like [[Sliver-Server|sliver.service]]). The MCP shows "✔ Connected" from the stdio wrapper alone, so a dead `:5000` only surfaces at tool-call time — see [[Reboot-Runbook]]. (A separate, unused Node kali-MCP container `kali-pentest-mcp` on `:3000` was removed 2026-08-01 — it was never wired into `~/.claude.json`.)

## Tool families (prefix `mcp__mcp-kali-server__`)
- **Raw exec:** `command`, `health`, `system_network_info`
- **Curated tools:** `tools_nmap`, `tools_nuclei`, `tools_gobuster`, `tools_ffuf`(via arjun/httpx), `tools_sqlmap`, `tools_hydra`, `tools_john`, `tools_metasploit`, `tools_wpscan`, `tools_subfinder`, `tools_assetfinder`, `tools_waybackurls`, `tools_enum4linux`, `tools_fierce`
- **Reverse shells:** `reverse_shell_listener_start`, `reverse_shell_generate_payload`, `reverse_shell_send_payload`, `reverse_shell_sessions`, `reverse_shell_status`
- **SSH sessions:** `ssh_session_start`, `ssh_session_command`, `ssh_session_upload_content`, `ssh_session_download_content`
- **Recon intel:** `search_shodan`
- **File transfer:** `kali_upload`, `kali_download`, `target_upload_file`, `target_download_file`

## Basic usage
```
search_shodan("org:target")   → external footprint
tools_nmap(target)            → port/service enum
reverse_shell_listener_start  → catch a callback
```

## Used by skills
- [[osint-profile]] — Shodan search + subfinder/assetfinder/waybackurls as a second recon source alongside [[mcp-hexstrike]]
