#!/bin/bash
# install.sh — run with sudo to install the wifi-failsafe service
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_FILE="$SCRIPT_DIR/wifi-failsafe.service"

echo "[+] Installing wifi-failsafe service..."

# Install service
cp "$SERVICE_FILE" /etc/systemd/system/wifi-failsafe.service
systemctl daemon-reload
systemctl enable wifi-failsafe.service

# Captive-portal DNS hijack for the NM shared-mode failsafe AP. Without this the
# OS captive probes (captive.apple.com etc.) are forwarded upstream and time out
# on the internet-less AP, so iOS never shows the login sheet.
HIJACK_SRC="$SCRIPT_DIR/dnsmasq-shared.d/captive-failsafe.conf"
if [ -f "$HIJACK_SRC" ]; then
    install -d -m0755 /etc/NetworkManager/dnsmasq-shared.d
    install -m0644 "$HIJACK_SRC" /etc/NetworkManager/dnsmasq-shared.d/captive-failsafe.conf
    # NM re-reads dnsmasq-shared.d when it next starts a shared dnsmasq (i.e. next
    # AP activation); reload so it's picked up without waiting for a restart.
    systemctl reload NetworkManager 2>/dev/null || systemctl restart NetworkManager || true
    echo "[+] Installed captive-portal DNS hijack (dnsmasq-shared.d/captive-failsafe.conf)."
fi

echo "[+] Service installed and enabled."
echo ""
echo "    Start now:  sudo systemctl start wifi-failsafe"
echo "    View logs:  sudo journalctl -u wifi-failsafe -f"
echo "    Status:     sudo systemctl status wifi-failsafe"
echo ""

# Show the generated AP credentials
STATE="$SCRIPT_DIR/.state.json"
if [ -f "$STATE" ]; then
    echo "[+] AP credentials (from .state.json):"
    python3 -c "import json; s=json.load(open('$STATE')); print('    SSID:    ', s['ap_ssid']); print('    Password:', s['ap_password'])"
fi
