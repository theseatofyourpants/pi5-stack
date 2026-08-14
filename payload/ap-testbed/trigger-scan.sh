#!/usr/bin/env bash
# trigger-scan.sh — the ONLY place an automated scan is launched.
# Called by the consent portal (device owner clicked consent) OR by watcher.sh
# (a pre-authorized device from the managed allowlist joined).
# Args:  $1 = target IP   $2 = MAC   [$3 = auth hint: consent|allowlist]
#
# Authorization = MAC on the admin allowlist OR consent on record. Offense is
# gated by config.armed AND ARM_OFFENSIVE=1 AND no logs/HALT. Scope is LOCKED to
# the single IP; the scan is low-aggression / non-destructive; per-MAC cooldown.
set -euo pipefail
BASE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
STORE="$BASE/lib/store.py"
LOG="$BASE/logs/scans.log"

# systemd/runuser give us a minimal PATH; restore the user tool dirs so `claude`
# (and any MCP-launched tools it spawns) resolve. HOME is set by systemd (User=)
# and by `runuser -l` (watcher path).
export HOME="${HOME:-$(dirname "$BASE")}"
export PATH="$HOME/.local/bin:$HOME/go/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
# Resolve the claude binary explicitly (absolute path beats PATH surprises).
CLAUDE_BIN="$HOME/.local/bin/claude"
[ -x "$CLAUDE_BIN" ] || CLAUDE_BIN="$(command -v claude || echo claude)"

IP="${1:?target ip}"; MAC="${2:?mac}"; AUTH="${3:-consent}"
mkdir -p "$BASE/logs" "$BASE/state/scans" "$HOME/engagements"
ts(){ date +%FT%T; }
note(){ printf '%s %s\n' "$(ts)" "$*" >> "$LOG"; }

# --- validate inputs (defence vs injection into filenames / the prompt) ------
python3 "$STORE" valid-ip  "$IP"  || { note "bad IP '$IP' — refusing";  exit 0; }
python3 "$STORE" valid-mac "$MAC" || { note "bad MAC '$MAC' — refusing"; exit 0; }

# --- kill switch -------------------------------------------------------------
[ -f "$BASE/logs/HALT" ] && { note "HALT present — refusing ($IP)"; exit 0; }

# --- authorization: managed allowlist OR consent on record -------------------
if python3 "$STORE" is-allowed "$MAC"; then
  AUTH="allowlist"
elif grep -q "\"mac\": \"$MAC\"" "$BASE/logs/allowlist.jsonl" 2>/dev/null; then
  AUTH="consent"
else
  note "NO AUTHORIZATION for $MAC ($IP) — refusing"; exit 0
fi

# --- debounce: one scan per MAC per cooldown ---------------------------------
COOLDOWN="${COOLDOWN:-1800}"
STAMP="$BASE/state/.last-${MAC//:/}"
if [ -f "$STAMP" ] && [ $(( $(date +%s) - $(cat "$STAMP") )) -lt "$COOLDOWN" ]; then
  note "cooldown active for $MAC — skipping"; exit 0
fi
date +%s > "$STAMP"

# --- DISARMED gate — single source of truth: config.armed (admin Settings) + HALT.
# (Do NOT gate on an ARM_OFFENSIVE env var: only the portal service set it, so the
# watcher/allowlist and admin-Retry paths were always wrongly disarmed.)
if ! python3 "$STORE" is-armed; then
  note "AUTHORIZED($AUTH) but DISARMED (config.armed=false or HALT set): would scan $IP ($MAC)"
  exit 0
fi

# --- ARMED: scoped, non-destructive, headless, tracked -----------------------
SID="$(date +%s)-${MAC//:/}"
OUT="$HOME/engagements/auto-${MAC//:/}-$(date +%Y%m%d-%H%M%S).md"
SCANLOG="$BASE/state/scans/$SID.log"
python3 "$STORE" scan-start "$SID" "$MAC" "$IP" "$AUTH" "$OUT" "$$"
note "ARMED scan START id=$SID ip=$IP mac=$MAC auth=$AUTH -> $OUT"

PROMPT="You are running UNATTENDED on an isolated security testbed. Use the Agent tool to \
launch the device-assess agent (subagent_type: device-assess) for a NON-DESTRUCTIVE, \
scope-LOCKED assessment of the SINGLE host ${IP} (device MAC ${MAC}, authorization: ${AUTH}); \
tell it to write the evidence-based report to ${OUT}. Scope is LOCKED to ${IP} — nothing may \
touch any other address, the subnet, or the gateway (10.66.66.1). Low aggression: no brute \
force, no destructive checks, no exploitation. If the device-assess agent is unavailable for \
any reason, perform the assessment yourself — network + service enumeration, device/OS \
fingerprint, device-level vulnerability identification, and a web check if web ports exist — \
and write the report to ${OUT}. Verify ${OUT} exists before finishing. Make autonomous \
decisions; record any ambiguity in the report rather than stopping."

# --- optional auto-abort watchdog: kill the scan if the target leaves the AP ---
OUTBASE="$(basename "$OUT")"          # unique token present in the claude argv
ABORT_FLAG="$BASE/state/scans/$SID.aborted"
WATCHDOG_PID=""
if python3 "$STORE" is-auto-abort; then
  AP_IF="$(cat /run/ap-testbed/iface 2>/dev/null || echo wlan1)"
  (
    misses=0
    sleep 45                          # grace period for the device to settle
    while pgrep -f "$OUTBASE" >/dev/null 2>&1; do
      if iw dev "$AP_IF" station dump 2>/dev/null | grep -qiF "$MAC"; then
        misses=0
      else
        misses=$((misses + 1))
      fi
      if [ "$misses" -ge 3 ]; then     # ~90s absent (plus hostapd inactivity lag)
        touch "$ABORT_FLAG"
        pkill -f "$OUTBASE" 2>/dev/null || true
        break
      fi
      sleep 30
    done
  ) &
  WATCHDOG_PID=$!
fi

# --dangerously-skip-permissions: this is UNATTENDED — no human can approve tool
# prompts, so without this every tool (incl. the final report Write) is auto-denied.
# Compensating controls: isolated walled-garden AP, scope LOCKED to one IP in the
# prompt, non-destructive/low-aggression mandate, restricted device-assess toolset,
# runs as non-root tsoyp, HALT kill-switch. (Prompt-injection from a hostile scanned
# device is the residual risk — see the hardening note for locking the toolset down.)
# Stream JSON events through the filter so the admin UI shows live progress.
# pipefail is on, so guard with set +e to read claude's real exit via PIPESTATUS.
set +e
# Scope the scan's claude to the MCP servers the device-assess PIPELINE uses — not
# just device-assess (nmap/SMB/web enum: mcp-kali-server, hexstrike, wstg-pentest) but
# also the web-assess subagent it hands off to for any device with a web surface
# (adds pentest-ai + playwright). This is OS-agnostic: a Windows/Mac/IoT box exercises
# far more of this set (SMB, RDP-adjacent, web apps) than a locked-down phone does.
# Excludes the heavy/irrelevant servers so a scan can't blow its timeout: Mythic (8
# containers) + Sliver (C2, only lateral-move uses them), greynoise/virustotal
# (external OSINT), and caido (x86-laptop-only; web-assess falls back to playwright +
# raw requests without it). --strict-mcp-config makes claude use only this set.
SCAN_MCP="$(mktemp)"; trap 'rm -f "$SCAN_MCP"' EXIT
python3 -c 'import json,sys
keep={"mcp-kali-server","hexstrike","wstg-pentest","pentest-ai","playwright"}
d=json.load(open(sys.argv[1])).get("mcpServers",{})
json.dump({"mcpServers":{k:v for k,v in d.items() if k in keep}}, open(sys.argv[2],"w"))' \
  "$HOME/.claude.json" "$SCAN_MCP" 2>>"$SCANLOG" || cp "$HOME/.claude.json" "$SCAN_MCP"
# -k 30: if claude ignores the SIGTERM at SCAN_TIMEOUT, SIGKILL it 30s later so a
# hung/stuck scan can never keep running (an un-reaped claude orphaned for ~2h and
# exhausted RAM on a small VM). PIPESTATUS[0] still reflects claude's real exit.
timeout -k 30 "${SCAN_TIMEOUT:-900}" "$CLAUDE_BIN" -p --dangerously-skip-permissions \
  --mcp-config "$SCAN_MCP" --strict-mcp-config \
  --output-format stream-json --verbose "$PROMPT" \
  2>>"$SCANLOG" | python3 "$BASE/lib/stream-filter.py" >> "$SCANLOG"
RC=${PIPESTATUS[0]}
set -e
rm -f "$SCAN_MCP"
[ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID" 2>/dev/null || true
# Belt-and-suspenders reap: kill any claude still lingering for THIS scan. Its argv
# carries the unique report token ($OUTBASE), so this targets only this scan's process.
pkill -9 -f "$OUTBASE" 2>/dev/null || true

if [ -f "$ABORT_FLAG" ]; then
  rm -f "$ABORT_FLAG"
  python3 "$STORE" scan-finish "$SID" aborted
  note "ARMED scan ABORTED (target left AP) id=$SID"
elif [ "$RC" -eq 0 ]; then
  python3 "$STORE" scan-finish "$SID" done;  note "ARMED scan DONE id=$SID -> $OUT"
else
  python3 "$STORE" scan-finish "$SID" error; note "ARMED scan ERROR/timeout id=$SID rc=$RC (see $SCANLOG)"
fi
