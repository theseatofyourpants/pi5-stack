---
title: Replication Guide
tags: [replication, setup, arm64, gotchas]
updated: 2026-07-27
---

# Replication Guide

Back to [[00-Index]]. This is the "rebuild it from bare metal" note, with the arm64 landmines called out — several of these cost real hours the first time.

## 0. Host baseline

- Raspberry Pi 5, arm64, **Kali Rolling**
- **Go 1.26.5** (linux/arm64) at `~/go-sdk/` — used to build `mythic-cli` and `mythic-mcp`
- Node.js (via corepack shims at `/usr/share/nodejs/corepack/shims/`) — for npx-based MCPs
- Python venvs per-tool (hexstrike, pentest-ai, kali-server)
- `~/.local/bin/uv` — for the wstg-pentest server
- **No passwordless sudo** — privileged commands are run by the user in-terminal via the `! command` prefix

## 1. C2 backends

### Sliver → [[Sliver-Server]]
- Binary `~/.local/bin/sliver-server` (arm64)
- Daemon: `nohup ~/.local/bin/sliver-server daemon > /tmp/sliver-server.log 2>&1 &`
- Operator profile `~/sliver-claude.cfg` (mTLS certs for "claude-operator"), listens `127.0.0.1:31337`

### Mythic → [[Mythic-Server]]
- `cd ~/Mythic && ./mythic-cli start` (8 Docker containers)
- Web UI `https://localhost:7443`

## 2. MCP servers

All registered in global `~/.claude.json` under `mcpServers`. Per-server detail in [[MCP-Servers]]. Node-based ones (`virustotal`, `playwright`) use the corepack `npx` shim; Python ones use their venv binary; Go ones use the compiled binary.

## 3. Network sensors → [[Network-Sensors]]

> [!warning] arm64 packaging landmines — the ones that actually bit
> - **Suricata:** the Kali arm64 `.deb` is **unusable** — it hard-depends on DPDK libs (`librte-eal26`, `libxdp1`, `libnetfilter-log1`) that don't exist for arm64. **Build from source** (7.0.10) with `--disable-dpdk --disable-ebpf --disable-geoip`. Needs Rust (rustup, not the apt cargo) + `cbindgen`. Version check is `suricata -V` (capital V — `--version` errors).
> - **Zeek:** the Kali `zeek` package depends on `libc6 < 2.38` but the system ships **2.42** → uninstallable. Use the **OpenSUSE OBS `Debian_12` repo** instead (Zeek 8.2.1). Logs land in `/opt/zeek/logs/current/` — **not** `/var/log/zeek/`.
> - **Zeek side effect:** `zeekctl`'s Recommends pulled in **`courier-mta`** (a full mail server) — unwanted attack surface on a pentest box. Remove/mask it.
> - **Docker apt repo:** `download.docker.com` has no `kali-rolling` distribution — a bad `docker.list` silently **poisons every `apt update`**. Point it at `bookworm`.

- Build script: `~/build-sensors.sh` · Zeek installer: `~/zeek-install.sh`
- bettercap 2.41.5 installs cleanly from Kali apt (`/usr/bin/bettercap`)
- After install: `sudo suricata-update` (ET Open, ~45k rules) and `sudo /opt/zeek/bin/zeekctl deploy`

## 4. Operator skills

Drop the seven `*.md` files into `~/.claude/agents/` (see [[Operator-Skills]]). Each carries its own `model`, `tools`, and workflow in YAML frontmatter + body. No install step — Claude Code discovers them.

## 5. Blue-team feeds

- [[mcp-virustotal|VirusTotal MCP]]: `npx -y @burtthecoder/mcp-virustotal`, API key in `~/.claude.json` env (free tier 500/day, 4/min)
- [[mcp-greynoise|GreyNoise MCP]]: **custom-built** — no off-the-shelf package exists. Local FastMCP server at `~/greynoise-mcp/server.py` in its own venv (`python -m venv venv && venv/bin/pip install mcp httpx`). **Keyless by default** via the GreyNoise Community endpoint; add `GREYNOISE_API_KEY` to the `greynoise` env in `~/.claude.json` for context/riot/gnql. Registered:
  ```jsonc
  "greynoise": { "command": "~/greynoise-mcp/venv/bin/python",
                 "args": ["~/greynoise-mcp/server.py"],
                 "env": { "GREYNOISE_API_KEY": "" } }
  ```
- [[mcp-huntress|Huntress]]: a **claude.ai remote connector** (tools namespaced `mcp__claude_ai_Huntress_MCP__*`), not a local `~/.claude.json` entry

## Order of operations for a clean rebuild

1. Host baseline (Go, Node, uv, Python venvs)
2. Fix `docker.list` → `bookworm` **before** anything apt (or every install breaks)
3. Sliver + Mythic backends
4. Sensors (Suricata source build → Zeek OBS → bettercap → remove courier-mta → suricata-update → zeekctl deploy)
5. Register all MCP servers in `~/.claude.json`
6. Drop skills into `~/.claude/agents/`
7. Verify with [[engagement-start]] (it health-checks C2 + sensors on run)

## Related
- [[Architecture-Overview]] · [[Reboot-Runbook]]
