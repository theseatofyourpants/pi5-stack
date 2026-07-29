#!/usr/bin/env bash
# layers/50-c2-sliver.sh — OPT-IN: sliver server + operator certs (manual stop) + sliver-c2 MCP
# STATUS: STUB (scaffold baseline). Real implementation lands in step 2.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"
source "$STACK_ROOT/versions.env" 2>/dev/null || true
warn "layer 50-c2-sliver is a STUB — not implemented yet."
log  "will: OPT-IN: sliver server + operator certs (manual stop) + sliver-c2 MCP"
# TODO(step-2): implement the steps above (with manual stops where noted).
exit 0
