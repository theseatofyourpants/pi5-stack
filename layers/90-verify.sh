#!/usr/bin/env bash
# layers/90-verify.sh — full health check of the rebuilt stack (stack-status style)
# STATUS: STUB (scaffold baseline). Real implementation lands in step 2.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"
source "$STACK_ROOT/versions.env" 2>/dev/null || true
warn "layer 90-verify is a STUB — not implemented yet."
log  "will: full health check of the rebuilt stack (stack-status style)"
# TODO(step-2): implement the steps above (with manual stops where noted).
exit 0
