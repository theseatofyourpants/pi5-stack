#!/usr/bin/env bash
# install-phish-infra.sh — phishing initial-access infra for the /phish-sim agent:
#   * gophish  — Kali package, campaign management + landing pages
#   * evilginx — built from source (Go), AiTM reverse proxy (session/MFA-cookie theft)
# INSTALL ONLY. This never starts a phishing server — both are per-engagement infra,
# launched by the operator during an AUTHORIZED simulation (see the /phish-sim gate).
# Idempotent: re-running just re-installs / re-checks out the pinned evilginx commit.
set -euo pipefail

STACK_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$STACK_ROOT/versions.env" 2>/dev/null || true
export PATH="$HOME/go-sdk/bin:$HOME/go/bin:$PATH"

# 1. gophish (Kali apt package)
if command -v gophish >/dev/null 2>&1; then
  echo "gophish already present: $(command -v gophish)"
else
  echo "installing gophish (apt)…"
  sudo apt-get update -qq && sudo apt-get install -y gophish
fi

# 2. evilginx — build from source at the pinned commit
REPO="${EVILGINX_REPO:-https://github.com/kgretzky/evilginx2.git}"
COMMIT="${EVILGINX_COMMIT:-}"
SRC="$HOME/evilginx2"
command -v go >/dev/null 2>&1 || { echo "ERROR: Go not found (need ~/go-sdk); run 00-core first" >&2; exit 1; }
[ -d "$SRC/.git" ] || git clone "$REPO" "$SRC"
cd "$SRC"
if [ -n "$COMMIT" ]; then
  git fetch --all --quiet || true
  git checkout --quiet "$COMMIT"
fi
make
mkdir -p "$HOME/.local/bin"
install -m0755 ./build/evilginx "$HOME/.local/bin/evilginx"
echo "evilginx installed -> $HOME/.local/bin/evilginx ($(git rev-parse --short HEAD)); phishlets dir: $SRC/phishlets"

echo
echo "phishing infra installed (INSTALL ONLY — nothing started)."
echo "  * per-engagement, authorized-simulation use only (see /phish-sim)."
echo "  * evilginx needs a phishing domain + valid TLS and binds :443/:53/:80 —"
echo "    which COLLIDE with the AP testbed on 10.66.66.1. Don't run them together."
