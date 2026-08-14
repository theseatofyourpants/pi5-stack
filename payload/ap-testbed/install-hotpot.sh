#!/usr/bin/env bash
# install-hotpot.sh — install the hot-pot deception layer onto the testbed.
# Run with sudo. Idempotent. Assumes the base testbed is already installed
# (install-testbed.sh) and Docker is present (tsoyp in the docker group).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo: ! sudo bash ~/ap-testbed/install-hotpot.sh"; exit 1; }
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
STACK_USER="$(stat -c %U "$HERE")"
# Render __AP_DIR__/__STACK_USER__ placeholders in a payload file to stdout.
render(){ sed -e "s|__AP_DIR__|$HERE|g" -e "s|__STACK_USER__|$STACK_USER|g" "$1"; }

echo "[*] Checking Docker…"
command -v docker >/dev/null || { echo "  !! docker not found — install Docker first"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "  !! 'docker compose' plugin missing"; exit 1; }

echo "[*] Making hot-pot scripts executable…"
chmod +x "$HERE"/hotpot/hotpot-ctl.sh "$HERE"/hotpot/seed-tokens.py

echo "[*] Seeding honeytokens (as $STACK_USER)…"
sudo -u "$STACK_USER" python3 "$HERE/hotpot/seed-tokens.py" || echo "  (seed skipped/failed — check token_backend)"
chown -R "$STACK_USER:$STACK_USER" "$HERE/hotpot/smb/share" "$HERE/hotpot/tokens" 2>/dev/null || true
mkdir -p "$HERE/logs/hotpot" "$HERE/logs/cowrie"
chown -R "$STACK_USER:$STACK_USER" "$HERE/logs/hotpot" "$HERE/logs/cowrie"

echo "[*] Installing systemd units (hot-pot service + updated target)…"
render "$HERE/systemd/ap-testbed-hotpot.service" > /etc/systemd/system/ap-testbed-hotpot.service
chmod 0644 /etc/systemd/system/ap-testbed-hotpot.service
install -m0644 "$HERE"/systemd/ap-testbed.target         /etc/systemd/system/

echo "[*] Reinstalling scoped sudoers (now includes the hot-pot unit)…"
tmp_sudoers="$(mktemp)"; render "$HERE/sudoers.d-ap-testbed" > "$tmp_sudoers"
if visudo -cf "$tmp_sudoers" >/dev/null 2>&1; then
  install -m0440 -o root -g root "$tmp_sudoers" /etc/sudoers.d/ap-testbed
else
  echo "  !! sudoers failed validation — NOT installed (admin toggle will need manual start)"
fi
rm -f "$tmp_sudoers"

echo "[*] Pre-building container images (first build pulls base images)…"
sudo -u "$STACK_USER" docker compose --project-directory "$HERE/hotpot" -f "$HERE/hotpot/docker-compose.yml" build || \
  echo "  (build deferred — hotpot-ctl.sh will build on first start)"

echo "[*] Reloading systemd…"
systemctl daemon-reload

cat <<EOF

==================================================================
 Hot-pot installed. It is OFF by default (config.deception=false).

 To arm the deception layer:
   1. Enable it:  admin console -> Settings -> "Adversarial honeypot"
      (or:  python3 $HERE/lib/store.py  … set deception=true via the UI)
   2. Plug the dongle (or: sudo systemctl start ap-testbed.target)
      -> ap-testbed-hotpot.service brings the stack up ONLY when deception is on.

 Bait (all bound to the AP gateway 10.66.66.1 ONLY):
   22/23  Cowrie SSH/Telnet      445   SMB share "IT-Backups"
   8080   fake admin login       8686  honeytoken collector

 Safety invariant (enforced by hotpot-ctl.sh): containers may answer probers
 but can NEVER initiate outbound — no internet, no LAN, no exfil.

 Maintain / monitor it with the  /hotpot-maintain  skill.
 Manual controls:
   sudo systemctl start|stop ap-testbed-hotpot.service
   $HERE/hotpot/hotpot-ctl.sh status
==================================================================
EOF
