#!/usr/bin/env bash
# watcher.sh — dnsmasq dhcp-script hook (runs as root via the dnsmasq service).
# dnsmasq calls: $1=add|del|old  $2=MAC  $3=IP  $4=hostname
# Logs every join. If the joining MAC is on the ADMIN-MANAGED allowlist, it is
# pre-authorized, so we auto-launch a scan — dropping privileges to tsoyp first
# (via runuser) so claude runs with the right HOME/skills/MCP config.
# Devices NOT on the allowlist are only logged; they can still self-authorize via
# the consent portal.
set -euo pipefail
BASE=/home/tsoyp/ap-testbed
STORE="$BASE/lib/store.py"
LOG="$BASE/logs/joins.log"
ACTION="${1:-}"; MAC="${2:-}"; IP="${3:-}"; HOST="${4:-}"
mkdir -p "$BASE/logs"
printf '%s %-4s mac=%s ip=%s host=%s\n' "$(date +%FT%T)" "$ACTION" "$MAC" "$IP" "$HOST" >> "$LOG"

if [ "$ACTION" = "add" ] && [ -n "$MAC" ] && [ -n "$IP" ]; then
  if python3 "$STORE" is-allowed "$MAC"; then
    if command -v runuser >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
      runuser -l tsoyp -c "'$BASE/trigger-scan.sh' '$IP' '$MAC' allowlist" >/dev/null 2>&1 &
    else
      "$BASE/trigger-scan.sh" "$IP" "$MAC" allowlist >/dev/null 2>&1 &
    fi
  fi
fi
exit 0
