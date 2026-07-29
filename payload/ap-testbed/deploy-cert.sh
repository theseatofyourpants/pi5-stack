#!/usr/bin/env bash
# deploy-cert.sh — certbot --deploy-hook. Copies the Let's Encrypt cert to where the
# consent portal (runs as tsoyp) can read it, then reloads the portal. Runs as root
# (by certbot) on initial issuance AND every auto-renewal.
set -euo pipefail
DOMAIN="${CAPTIVE_DOMAIN:-captive.theseatofyourpants.com}"
SRC="/etc/letsencrypt/live/$DOMAIN"
DEST="/home/tsoyp/ap-testbed/state"
[ -f "$SRC/fullchain.pem" ] || { echo "[deploy-cert] no cert at $SRC — nothing to do"; exit 0; }
cp -f "$SRC/fullchain.pem" "$DEST/portal-cert.pem"
cp -f "$SRC/privkey.pem"   "$DEST/portal-key.pem"
chown tsoyp:tsoyp "$DEST/portal-cert.pem" "$DEST/portal-key.pem"
chmod 640 "$DEST/portal-cert.pem" "$DEST/portal-key.pem"
systemctl restart ap-testbed-portal 2>/dev/null || true
echo "[deploy-cert] installed cert for $DOMAIN -> portal, reloaded"
