#!/usr/bin/env bash
# layers/00-core.sh — apt base, Go SDK, pipx, cargo, python libs (flask/markdown/weasyprint), hostapd, dnsmasq, ipset, chromium, tailscale
# STATUS: STUB (scaffold baseline). Real implementation lands in step 2.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"
source "$STACK_ROOT/versions.env" 2>/dev/null || true
warn "layer 00-core is a STUB — not implemented yet."
log  "will: apt base, Go SDK, pipx, cargo, python libs (flask/markdown/weasyprint), hostapd, dnsmasq, ipset, chromium, tailscale"
# TODO(step-2): implement the steps above (with manual stops where noted).
exit 0
