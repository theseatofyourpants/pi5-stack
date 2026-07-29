---
title: Caido MCP
tags: [mcp, web, proxy, offensive, caido]
tool_prefix: "mcp__caido__"
transport: stdio
updated: 2026-07-27
---

# Caido MCP

Part of [[MCP-Servers]].

## What it is
MCP **client + CLI** for **Caido**, a web security proxy (Burp-style). It is a real, working community MCP server — `c0tton-fluff/caido-mcp-server` **v4** (Go, statically-linked arm64 binary) — that talks to a running Caido instance over Caido's **GraphQL API**. Exposes **66 tools + 6 read-only resources**: proxy-history search (HTTPQL), request replay, response diff, race-window send, findings, sitemap, scopes, projects, workflows, tamper (match & replace), intercept, environments.

> [!note] It's an API client, not a datastore
> The "API" is Caido's GraphQL API, which this MCP wraps. There is **no neo4j** involved — that's BloodHound's store, a separate (not-yet-installed) tool. Auth headers/cookies are redacted in tool output by default.

## Config (`~/.claude.json`)
```jsonc
"caido": {
  "command": "/home/tsoyp/.local/bin/caido-mcp-server",
  "args": ["serve"],
  "env": { "CAIDO_URL": "http://127.0.0.1:8080" }
}
```
- Binary `~/.local/bin/caido-mcp-server`; source tree `~/caido-mcp-server/`

## Key tools (prefix `mcp__caido__`, tool names prefixed `caido_`)
- **History:** `caido_list_requests` (HTTPQL), `caido_get_request`, `caido_get_sitemap`
- **Replay:** `caido_create_replay_session`, `caido_send_request`, `caido_edit_request`, `caido_batch_send`, `caido_race_window_send`, `caido_diff_responses`, `caido_export_curl`
- **Findings:** `caido_create_finding`, `caido_list_findings`, `caido_export_findings`
- **Scope:** `caido_is_in_scope`, `caido_list_scopes`, `caido_create_scope`
- **Automate/Workflows/Tamper/Intercept/Environments:** full lifecycle tools
- **Resources:** `caido://requests/{id}`, `caido://findings`, `caido://sitemap`, `caido://scopes`, `caido://project`, `caido://replay`

> [!warning] No arm64 Caido binary
> Caido itself has **no arm64 Linux build**, so it can't run on the Pi. Run the Caido desktop app on an x86_64 laptop and point the MCP at it:
> `bash ~/caido-setup.sh http://<laptop-ip>:8080`
> Token is stored in `~/.config/caido-mcp-server/` and persists across restarts (stateless server — see [[Reboot-Runbook]]).

## Basic usage
```
1. Caido running on laptop, proxy configured
2. caido-mcp-server serve (auto by Claude Code)
3. Search proxy history / replay requests / read findings via MCP tools
```

## Used by skills
- [[web-assess]] — the **request-level verification surface**: replay PoCs (`caido_send_request`), differential proof (`caido_edit_request` + `caido_diff_responses`), race-condition proof (`caido_race_window_send`), curl repro into evidence (`caido_export_curl`), and mining proxy history (`caido_list_requests`). Playwright covers the browser/DOM side; Caido covers the raw-request side.

## Notes
- Caido has **no arm64 Linux build** — the app runs on the operator's x86_64 laptop and this MCP points at it via `CAIDO_URL`. Auth once: `bash ~/caido-setup.sh http://<laptop-ip>:8080` (token persists in `~/.config/caido-mcp-server/`). If Caido is unreachable the caido tools error on auth/connection — [[web-assess]] falls back to Playwright + raw requests rather than blocking.
