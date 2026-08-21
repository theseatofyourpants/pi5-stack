#!/usr/bin/env bash
# recon-ng-domain <domain> [workspace] — non-interactive domain recon chain.
#
# recon-ng is an interactive console; the only sane way to drive it from an agent is
# a resource file. This wraps that so a caller does not have to hand-roll one.
# Results land in the workspace db; the table dump goes to stdout as CSV.
#
# PASSIVE by default. Nothing here touches the target directly except DNS resolution.
#
# Two messages are NORMAL and not failures:
#   "[!] Source contains no input."  -- the resolve module found nothing left to
#       resolve because every known host already has an IP. Expected on a re-run.
#   an empty certificate_transparency result -- crt.sh read-timeouts often; that is
#       the source being slow, NOT the target having no certificates.
set -uo pipefail
DOMAIN="${1:?usage: recon-ng-domain <domain> [workspace]}"
WS="${2:-stack}"
RC="$(mktemp)"; OUT="$(mktemp -d)"; trap 'rm -rf "$RC" "$OUT"' EXIT

cat > "$RC" <<RCEOF
options set TIMEOUT 30
modules load recon/domains-hosts/hackertarget
options set SOURCE $DOMAIN
run
modules load recon/domains-hosts/certificate_transparency
options set SOURCE $DOMAIN
run
modules load recon/domains-contacts/whois_pocs
options set SOURCE $DOMAIN
run
modules load recon/hosts-hosts/resolve
run
show hosts
show contacts
exit
RCEOF

timeout "${RECON_NG_TIMEOUT:-600}" recon-ng --no-analytics --no-version -w "$WS" -r "$RC" 2>&1 \
  | sed -r 's/\x1B\[[0-9;]*[mK]//g'
