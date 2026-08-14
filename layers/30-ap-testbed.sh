#!/usr/bin/env bash
# layers/30-ap-testbed.sh — deploy + install the autonomous AP testbed to
# ~/ap-testbed and run its installer (systemd units, udev, sudoers, egress helper,
# admin console). Also installs certbot for the trusted captive-portal cert and,
# if Docker is present, the hot-pot adversarial deception layer.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"

DEST="$HOME/ap-testbed"
log "deploying AP testbed -> $DEST"
mkdir -p "$DEST"
# Preserve runtime state + secrets on re-runs; app uses defaults if config absent.
rsync -a \
  --exclude 'logs/' --exclude 'state/session-auth' --exclude 'state/.last-*' \
  --exclude 'state/scans/' --exclude 'state/admin.pass' \
  --exclude 'state/portal-cert.pem' --exclude 'state/portal-key.pem' \
  --exclude 'state/config.json' --exclude 'state/devices.json' \
  --exclude 'state/hotpot-tokens.json' --exclude 'state/canarytokens.json' \
  --exclude 'hotpot/smb/share/*' --exclude 'hotpot/tokens/*' \
  "$STACK_ROOT/payload/ap-testbed/" "$DEST/"
chmod +x "$DEST"/*.sh "$DEST"/consent-portal/portal.py "$DEST"/lib/store.py 2>/dev/null || true
chmod +x "$DEST"/hotpot/*.sh "$DEST"/hotpot/seed-tokens.py 2>/dev/null || true

# Install systemd units + udev + scoped sudoers + egress helper + admin console.
log "running install-testbed.sh…"
as_root bash "$DEST/install-testbed.sh"

# certbot for the trusted captive-portal cert (option 114 / RFC 8908 — needed for
# modern Android to auto-pop; a self-signed cert is REJECTED by RFC 8908 clients).
log "installing certbot + Cloudflare DNS plugin…"
as_root apt-get install -y certbot python3-certbot-dns-cloudflare \
  || warn "certbot install failed — captive cert step will need manual setup"

# Hot-pot adversarial deception layer (optional; needs Docker + compose). Installs
# the ap-testbed-hotpot.service unit, extends sudoers, and pre-builds the bait
# containers. Stays OFF (config.deception=false) until armed in the admin console.
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  log "installing hot-pot deception layer…"
  as_root bash "$DEST/install-hotpot.sh" || warn "hot-pot install failed — arm later via admin console"
else
  warn "Docker/compose not found — skipping hot-pot. Install Docker, then: sudo bash $DEST/install-hotpot.sh"
fi

stop_for_manual "Trusted captive-portal cert (optional but recommended)" \
  "For modern Android to AUTO-POP the sign-in sheet, the captive-portal API must be" \
  "served over HTTPS with a PUBLICLY-TRUSTED cert (self-signed is rejected). If you" \
  "control a domain on Cloudflare DNS:" \
  "  1. Cloudflare -> API token (Zone:DNS:Edit for your zone)" \
  "  2. echo 'dns_cloudflare_api_token = <TOKEN>' | sudo tee /root/.secrets/certbot/cloudflare.ini" \
  "     (sudo mkdir -p /root/.secrets/certbot first; then sudo chmod 600 it)" \
  "  3. sudo certbot certonly --dns-cloudflare \\" \
  "       --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \\" \
  "       -d <captive-subdomain> --agree-tos -m <email> --non-interactive \\" \
  "       --deploy-hook $DEST/deploy-cert.sh" \
  "  4. set that subdomain in conf/dnsmasq-ap.conf.template (the address=/…/ hijack" \
  "     and the dhcp-option=114 URL), then restart ap-testbed.target" \
  "Skip (Enter) if you only need iOS / manual-browse / allowlist — the AP still works."

stop_for_manual "Plug in the Wi-Fi dongle" \
  "Plug in the MediaTek MT7612U USB Wi-Fi adapter now." \
  "It is the arming switch — udev brings the AP up when it's present," \
  "and tears it down when removed. Your uplink stays on the built-in" \
  "wlan0 and is never touched."

verify "admin service enabled" bash -lc 'systemctl is-enabled ap-testbed-admin 2>/dev/null | grep -q enabled'
verify "egress helper installed" test -x /usr/local/sbin/apt-testbed-authorize
# The hot-pot unit only exists if Docker was present to install it; on a box without
# Docker (hot-pot intentionally skipped above) this is not a failure.
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  verify "hot-pot unit present" test -f /etc/systemd/system/ap-testbed-hotpot.service
else
  log "hot-pot unit — skipped (Docker not installed; run install-hotpot.sh after adding Docker)"
fi
ok "30-ap-testbed done."
log "Admin console: http://<this-host-ip>:8787  (password was printed above)."
log "NOTE: device scans need the MCP backends from layer 20-mcp-core (hexstrike/kali-server)."
log "NOTE: the hot-pot deception layer is OFF by default — arm it in the admin 'Hot-pot' tab."
