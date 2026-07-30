---
title: Sliver C2 Server
tags: [infrastructure, c2, sliver]
version: "1.7.3"
updated: 2026-07-27
---

# Sliver C2 Server

Back to [[00-Index]]. The backend behind [[mcp-sliver-c2]]. New to C2? Start with the [[C2-Primer]].

## What it is
Sliver v1.7.3 (BishopFox) C2 framework, arm64. Runs as a multiplayer daemon so the MCP operator client can connect over mTLS.

## Install / layout
- Binary: `~/.local/bin/sliver-server` (arm64)
- Operator config: `~/sliver-claude.cfg` (mTLS certs, identity "claude-operator")
- Listens: `127.0.0.1:31337` (multiplayer gRPC/mTLS)

## Start
```bash
nohup ~/.local/bin/sliver-server daemon > /tmp/sliver-server.log 2>&1 &
```
**Does not survive reboot** — restart manually (see [[Reboot-Runbook]]).

## Health check
```bash
~/.local/bin/sliver-server version 2>/dev/null || echo "sliver down"
```

## Consumed by
- [[mcp-sliver-c2]] → skills [[generate-payload]], [[pivot-analysis]], [[triage-alerts]], [[debrief]], [[engagement-start]]

## Related
- [[C2-Primer]] (how C2 works, conceptually) · [[Mythic-Server]] (the other C2 backend) · [[Architecture-Overview]]
