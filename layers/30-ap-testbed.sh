#!/usr/bin/env bash
# layers/30-ap-testbed.sh — deploy + install the autonomous AP testbed to
# ~/ap-testbed and run its installer (systemd units, udev, sudoers, egress helper,
# admin console). The install-testbed.sh paths are hardcoded to ~/ap-testbed, so
# that's where it must live.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"

DEST="$HOME/ap-testbed"
log "deploying AP testbed -> $DEST"
mkdir -p "$DEST"
rsync -a --delete \
  --exclude 'logs/' --exclude 'state/session-auth' --exclude 'state/.last-*' \
  --exclude 'state/scans/' --exclude 'state/admin.pass' \
  "$STACK_ROOT/payload/ap-testbed/" "$DEST/"
chmod +x "$DEST"/*.sh "$DEST"/consent-portal/portal.py "$DEST"/lib/store.py 2>/dev/null || true

# Install systemd units + udev + scoped sudoers + egress helper + admin console.
# Generates a fresh admin password and prints it.
log "running install-testbed.sh…"
as_root bash "$DEST/install-testbed.sh"

stop_for_manual "Plug in the Wi-Fi dongle" \
  "Plug in the MediaTek MT7612U USB Wi-Fi adapter now." \
  "It is the arming switch — udev brings the AP up when it's present," \
  "and tears it down when removed. Your uplink stays on the built-in" \
  "wlan0 and is never touched."

verify "admin service enabled" bash -lc 'systemctl is-enabled ap-testbed-admin 2>/dev/null | grep -q enabled'
verify "egress helper installed" test -x /usr/local/sbin/apt-testbed-authorize
ok "30-ap-testbed done."
log "Admin console: http://<this-host-ip>:8787  (password was printed above)."
log "NOTE: device scans need the MCP backends from layer 20-mcp-core (hexstrike/kali-server)."
