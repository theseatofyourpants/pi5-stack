#!/usr/bin/env bash
# preflight.sh — base sanity checks before a rebuild. Assumes a FRESH Kali Rolling
# arm64 install (Pi 5). Warnings are non-fatal; only hard blockers stop the run.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"

log "preflight checks…"
BLOCK=0

[ "$(uname -m)" = "aarch64" ] || warn "arch is $(uname -m), not aarch64 — this stack targets Pi 5 arm64"
grep -qiE "kali|debian" /etc/os-release 2>/dev/null || warn "OS isn't Kali/Debian — apt/package steps may differ"

if verify "internet reachable" ping -c1 -W3 1.1.1.1; then :; else BLOCK=1; fi

if [ "$(id -u)" -ne 0 ]; then
  if sudo -n true 2>/dev/null; then ok "sudo available (passwordless)"; else warn "sudo will prompt during install (that's fine)"; fi
fi

avail_mb="$(df -m "$HOME" | awk 'NR==2{print $4}')"
if [ "${avail_mb:-0}" -ge 8000 ]; then ok "disk: ${avail_mb}MB free in \$HOME"; else warn "only ${avail_mb:-?}MB free in \$HOME — a full (--all) build wants ~8GB+"; fi

[ "$BLOCK" -eq 0 ] || die "blocking preflight failure (see above)"
ok "preflight passed"
confirm "Proceed with the rebuild on THIS host ($(hostname))?" || die "aborted by user"
