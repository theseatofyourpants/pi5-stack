---
name: mcp-doctor
description: Diagnose and repair a broken, failing, or keyless MCP server in ~/.claude.json — wrong env-var name, missing/invalid API key, deprecated upstream API version, or a down local backend. Use when `claude mcp list` shows "Failed to connect", an MCP's tools error at call time, or a server is running keyless/degraded. Codifies the validate-against-a-live-endpoint check and the restart-to-apply caveat.
---

# mcp-doctor — repair a broken/keyless MCP server

Repair an existing MCP entry. For onboarding a brand-new server, use `add-mcp` instead.

## 0. Reproduce & classify
```bash
claude mcp list 2>/dev/null        # which server is red / needs auth?
```
Classify the failure — they need different fixes:
- **Failed to connect / connection closed** → the launcher (npx/python) is dying on startup. Almost always a **missing or misnamed env var**, or a package/runtime mismatch.
- **Connected but tools error at call time** → the MCP process is fine but its **backend is down** (local HTTP server) or the **key is rejected / the upstream API changed**.
- **Runs keyless / degraded** → key env var is empty.

## 1. See the REAL startup error
Never guess — launch the server exactly as configured and read stderr. `npx` isn't on PATH; use the corepack shim:
```bash
# example for an npx server; sub in the configured command/args
export THE_KEY=$(python3 -c "import json;print(json.load(open('/home/tsoyp/.claude.json'))['mcpServers']['<name>']['env'].get('<KEY>',''))")
timeout 45 /usr/share/nodejs/corepack/shims/npx -y <package> </dev/null 2>&1 | head -20
```
A line like `FOO_API_KEY environment variable is required` while your config sets `BAR_KEY` is the classic **env-var-name mismatch** (this bit us on VirusTotal: config had `VT_API_KEY`, package wanted `VIRUSTOTAL_API_KEY`).

## 2. Validate the key against a LIVE authenticated endpoint
`claude mcp list` saying "Connected" does NOT prove the key works — it only means the stdio wrapper started. Hit an **auth-only** endpoint:
- Prefer an endpoint that 401s on a bad key and 200s on a good one. Community/unauth endpoints prove nothing.
- If it 404/410s, the **upstream API version may be deprecated** — check the vendor's migration docs and repoint the server code (GreyNoise EOL'd its entire v2 API 2026-01-01; the MCP was calling dead `/v2/*` and had to move to `/v3/*`).

## 3. Patch the config (never hand-edit fragile JSON blindly)
```bash
python3 - <<'PY'
import json
p='/home/tsoyp/.claude.json'; d=json.load(open(p))
env=d['mcpServers']['<name>']['env']
env['<CORRECT_KEY_NAME>']=env.pop('<WRONG_KEY_NAME>', '<value>')   # rename / set
json.dump(d,open(p,'w'),indent=2)
print('env keys now:', list(env.keys()))
PY
```

## 4. If it's a down LOCAL backend
Some MCPs are just clients for a local HTTP server (hexstrike :8899, kali-server :5000). Check `ss -tlnp | grep :<port>`; if down, start it — and if it dies on reboot, **systemd-ize it** (see the sliver.service / kali-server.service pattern) rather than nohup.

## 5. Verify + the restart caveat
```bash
claude mcp list 2>/dev/null | grep -i <name>     # should be ✔ Connected
```
> [!IMPORTANT]
> Editing `~/.claude.json` or an MCP server's code does NOT affect the **currently running** Claude Code session — it holds the old connection until Claude Code is **restarted**. Always tell the operator this; local backend services (started via systemd) are the exception and go live immediately.

## 6. Record it
Update the relevant memory note (what was wrong, the fix, and any "don't revert" warning — e.g. "don't downgrade back to the deprecated API"). Reference [[node-toolchain]] for the npm/corepack pin if the failure is npx-runtime-related.
