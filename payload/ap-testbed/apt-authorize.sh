#!/usr/bin/env bash
# apt-authorize.sh — add/remove a single MAC's egress ACCEPT rule in APT_EGRESS.
# Runs as ROOT via a narrowly scoped sudoers rule (called by the portal on consent
# and by the admin console on allowlist add/remove). Validates the MAC; touches
# ONLY the APT_EGRESS chain; never anything else.
#   apt-authorize.sh add <mac>   # open LAN-isolated internet egress for this MAC
#   apt-authorize.sh del <mac>   # revoke it
set -euo pipefail
ACTION="${1:-}"
MAC="$(printf '%s' "${2:-}" | tr 'A-Z' 'a-z')"
RUN=/run/ap-testbed
UPLINK="$(cat "$RUN/uplink" 2>/dev/null || true)"

printf '%s' "$MAC" | grep -qE '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$' || { echo "invalid MAC"; exit 2; }
[ -n "$UPLINK" ] || { echo "no uplink (AP down)"; exit 3; }
# APT_EGRESS only exists when egress is enabled; in walled-garden mode this is a
# harmless no-op (consent + scan still happen, device just stays offline).
iptables -L APT_EGRESS -n >/dev/null 2>&1 || { echo "egress off (APT_EGRESS absent)"; exit 0; }

RULE=(-m mac --mac-source "$MAC" -o "$UPLINK" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT)
case "$ACTION" in
  add) iptables -C APT_EGRESS "${RULE[@]}" 2>/dev/null || iptables -A APT_EGRESS "${RULE[@]}"; echo "authorized $MAC" ;;
  del) while iptables -C APT_EGRESS "${RULE[@]}" 2>/dev/null; do iptables -D APT_EGRESS "${RULE[@]}"; done; echo "deauthorized $MAC" ;;
  *)   echo "usage: apt-authorize.sh add|del <mac>"; exit 1 ;;
esac
