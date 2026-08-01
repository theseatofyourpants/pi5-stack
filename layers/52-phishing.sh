#!/usr/bin/env bash
# layers/52-phishing.sh — phishing initial-access infra (gophish + evilginx) for the
# /phish-sim agent. Opt-in, offensive, INSTALL ONLY (never starts a phishing server).
# evilginx is AiTM (session/MFA-cookie theft) — for AUTHORIZED simulations only.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"

log "installing phishing infra (gophish + evilginx) for /phish-sim…"
bash "$STACK_ROOT/payload/scripts/install-phish-infra.sh" || warn "phish-infra install had issues — see output above"

verify "gophish present"  bash -lc 'command -v gophish'
verify "evilginx present" test -x "$HOME/.local/bin/evilginx"
ok "52-phishing done — engagement infra, start per-engagement only (evilginx binds 443/53/80, collides with the AP testbed)"
