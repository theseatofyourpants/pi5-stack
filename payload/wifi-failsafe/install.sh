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
