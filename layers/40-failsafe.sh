#!/usr/bin/env bash
# layers/40-failsafe.sh — install the wifi-failsafe service (wlan0 fallback AP +
# captive portal when the Pi loses Wi-Fi). Needs python3-flask from 00-core.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"

# The failsafe manages the built-in client radio (wlan0) as a fallback AP. A VM has
# no built-in radio, so there is nothing to fail over — self-skip. (The VM's uplink
# is the host vNIC, always up.) Pass a USB Wi-Fi as wlan0 only to dev-test this code.
if ! have_builtin_wifi; then
  log "40-failsafe: no built-in Wi-Fi radio (profile=$PROFILE) — skipping failsafe install"
  exit 0
fi

DEST="$HOME/wifi-failsafe"
log "deploying wifi-failsafe -> $DEST"
mkdir -p "$DEST"
rsync -a --exclude '.state.json' "$STACK_ROOT/payload/wifi-failsafe/" "$DEST/"

if [ -x "$DEST/install.sh" ]; then
  as_root bash "$DEST/install.sh"
else
  as_root install -m0644 "$DEST/wifi-failsafe.service" /etc/systemd/system/
  as_root systemctl daemon-reload
  as_root systemctl enable wifi-failsafe.service
fi

# Hardened bind (10.42.0.1 not 0.0.0.0) is already in the payload source; no action.
verify "wifi-failsafe enabled" bash -lc 'systemctl is-enabled wifi-failsafe 2>/dev/null | grep -q enabled'
verify "flask available (portal dep)" python3 -c "import flask"
ok "40-failsafe done. It activates only if wlan0 loses connectivity for ~45s."
