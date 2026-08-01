---
name: add-mcp
description: Onboard a brand-new MCP server into the Pi 5 stack end to end — install it, add the entry to ~/.claude.json, wire in its API key, validate it against a live endpoint, and record it in memory. Use when adding a new MCP integration (npx, python venv, or a local-backend client). The greenfield sibling of mcp-doctor.
---

# add-mcp — onboard a new MCP server

## 1. Decide the launcher shape
Three patterns already in use on this box — match one:
- **npx** (no install): `command: /usr/share/nodejs/corepack/shims/npx`, `args: ["-y","<package>"]`. npm is pinned via corepack — see [[node-toolchain]]; don't let it drift.
- **python venv**: clone repo, `python3 -m venv venv && venv/bin/pip install -r requirements.txt`, point `command` at `<repo>/venv/bin/python` + the server script.
- **local-backend client**: the MCP is a thin client for a local HTTP server (like hexstrike/kali-server). Install BOTH; run the backend as a **systemd unit** (sliver.service / kali-server.service pattern) so it survives reboot.

## 2. Find the exact env-var name the package reads
Before writing config, confirm what the server actually expects (grep its source / README for `os.environ` / `process.env`). A wrong name = silent "required env var" death at startup — the #1 onboarding failure. Don't assume the obvious name.

## 3. Add the entry
```bash
python3 - <<'PY'
import json
p='/home/tsoyp/.claude.json'; d=json.load(open(p))
d['mcpServers']['<name>']={
  "command": "<command>", "args": [ ... ],
  "env": { "<EXACT_KEY_NAME>": "<value>" }
}
json.dump(d,open(p,'w'),indent=2); print('added <name>')
PY
```

## 4. Validate BEFORE trusting it
- Launch it exactly as configured and read stderr (see mcp-doctor step 1) — confirm it prints "running on stdio" cleanly.
- Hit an **authenticated** endpoint to prove the key works (not just an unauth/community one).
- `claude mcp list | grep <name>` → ✔ Connected.

## 5. Wire it into the operators that should use it
An MCP nobody calls is dead weight. Add its tools to the relevant agents/skills (e.g. a reputation source → `ioc-enrich` + `triage-alerts`; a recon source → `osint-profile`). Note the pi5-stack rebuild repo (`~/pi5-stack/payload/claude.json.tmpl`, layer `20-mcp-core`) if this should survive a fresh-box rebuild.

## 6. Record + restart caveat
Add a memory note (server, purpose, key location, validation method). Remind the operator: the new server is only live for tool calls **after Claude Code restarts**.
