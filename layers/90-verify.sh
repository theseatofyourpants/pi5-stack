#!/usr/bin/env bash
# layers/90-verify.sh — health check of the rebuilt stack (stack-status style).
# Hard checks = the always-on core; soft checks = opt-in bits (warn if absent).
set -uo pipefail
source "$STACK_ROOT/lib/common.sh"
export PATH="$HOME/go/bin:$HOME/go-sdk/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

pass=0; fail=0
chk(){  local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; pass=$((pass+1)); else err "$d"; fail=$((fail+1)); fi; }
soft(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else warn "$d — not installed (opt-in)"; fi; }

hr; log "STACK VERIFY"; hr

log "— core —"
chk "operator skills (device-assess)" test -f "$HOME/.claude/agents/device-assess.md"
chk "~/.claude.json mcpServers"        python3 -c "import json;assert json.load(open('$HOME/.claude.json'))['mcpServers']"
chk "hostapd"  command -v hostapd
chk "dnsmasq"  command -v dnsmasq
chk "nmap"     command -v nmap
chk "chromium" bash -lc 'command -v chromium || command -v chromium-browser'
chk "go"       test -x "$HOME/go-sdk/bin/go"

log "— AP testbed + failsafe —"
chk "ap-testbed-admin enabled"  bash -lc 'systemctl is-enabled ap-testbed-admin 2>/dev/null | grep -q enabled'
chk "egress helper installed"   test -x /usr/local/sbin/apt-testbed-authorize
chk "wifi-failsafe enabled"      bash -lc 'systemctl is-enabled wifi-failsafe 2>/dev/null | grep -q enabled'

log "— MCP backends —"
soft "hexstrike backend :8899"   bash -lc 'ss -tln 2>/dev/null | grep -q :8899'
soft "kali-server backend :5000" bash -lc 'ss -tln 2>/dev/null | grep -q :5000'
soft "greynoise MCP source"      test -f "$HOME/greynoise-mcp/server.py"
soft "uv (wstg-pentest)"         test -x "$HOME/.local/bin/uv"

log "— opt-in C2 / sensors (only if you installed them) —"
soft "sliver-server"      test -x "$HOME/.local/bin/sliver-server"
soft "sliver daemon :31337" bash -lc 'ss -tln 2>/dev/null | grep -q :31337'
soft "mythic-cli"         test -x "$HOME/Mythic/mythic-cli"
soft "mythic-mcp"         test -x "$HOME/Mythic-MCP/mythic-mcp"
soft "caido-mcp-server"   test -x "$HOME/.local/bin/caido-mcp-server"
soft "suricata"           bash -lc 'command -v suricata || test -x /usr/local/bin/suricata'
soft "zeek"               bash -lc 'test -x /opt/zeek/bin/zeek'
soft "bettercap"          command -v bettercap

hr
if [ "$fail" -eq 0 ]; then ok "core checks passed ($pass ok)"; else err "$fail core check(s) FAILED ($pass ok)"; fi
hr
[ "$fail" -eq 0 ]
