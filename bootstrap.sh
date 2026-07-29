#!/usr/bin/env bash
# bootstrap.sh — rebuild the Pi 5 red/blue stack from scratch (clean-stack, modular).
#
# Usage:
#   ./bootstrap.sh                       default layers (core..failsafe) ~20 min
#   ./bootstrap.sh --all                 + C2 + sensors, ~1–2 hr
#   ./bootstrap.sh --layers 00-core,30-ap-testbed
#   ./bootstrap.sh --from 51-c2-mythic   resume from a layer after a failure
#   ./bootstrap.sh --check               run the verify layer only
#   ./bootstrap.sh --dry-run             print what would run
#
# Idempotent: completed layers are recorded in .bootstrap-state and skipped on
# re-run (delete that file to force a full rebuild). Secrets come from secrets.env
# (git-ignored) or interactive prompts. Clean-stack: no historical data restored.
set -euo pipefail
STACK_ROOT="$(cd "$(dirname "$0")" && pwd)"; export STACK_ROOT
source "$STACK_ROOT/lib/common.sh"

DEFAULT_LAYERS=(00-core 10-skills 20-mcp-core 30-ap-testbed 40-failsafe)
OPTIN_LAYERS=(50-c2-sliver 51-c2-mythic 60-sensors)
FULL_ORDER=(00-core 10-skills 20-mcp-core 30-ap-testbed 40-failsafe 50-c2-sliver 51-c2-mythic 60-sensors 90-verify)

DRY=0; CHECK=0; FROM=""; SELECTED=()

usage(){ sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
while [ $# -gt 0 ]; do case "$1" in
  --all)     SELECTED=("${DEFAULT_LAYERS[@]}" "${OPTIN_LAYERS[@]}");;
  --layers)  IFS=',' read -ra SELECTED <<< "${2:-}"; shift;;
  --from)    FROM="${2:-}"; shift;;
  --check)   CHECK=1;;
  --dry-run) DRY=1;;
  -h|--help) usage;;
  *) die "unknown arg: $1 (try --help)";;
esac; shift; done

# default selection
[ ${#SELECTED[@]} -eq 0 ] && SELECTED=("${DEFAULT_LAYERS[@]}")
# --check overrides everything with just the verify layer
[ "$CHECK" -eq 1 ] && SELECTED=(90-verify)
# --from: run the full ordered list starting at FROM
if [ -n "$FROM" ]; then
  SELECTED=(); hit=0
  for l in "${FULL_ORDER[@]}"; do [ "$l" = "$FROM" ] && hit=1; [ $hit -eq 1 ] && SELECTED+=("$l"); done
  [ ${#SELECTED[@]} -gt 0 ] || die "unknown --from layer: $FROM"
fi

load_secrets
hr; log "pi5-stack rebuild"; log "layers: ${SELECTED[*]}"; hr

if [ "$DRY" -eq 0 ]; then
  bash "$STACK_ROOT/lib/preflight.sh" || die "preflight failed"
fi

for layer in "${SELECTED[@]}"; do
  script="$STACK_ROOT/layers/${layer}.sh"
  [ -f "$script" ] || { warn "no such layer: $layer (skipping)"; continue; }
  if [ "$DRY" -eq 1 ]; then log "[dry-run] would run: $layer"; continue; fi
  if [ "$layer" != "90-verify" ] && [ "$CHECK" -eq 0 ] && layer_is_done "$layer"; then
    ok "layer $layer already done (rm .bootstrap-state to force)"; continue
  fi
  hr; log "== layer $layer =="; hr
  if bash "$script" 2>&1 | tee "$LOG_DIR/${layer}.log"; then
    [ "$layer" != "90-verify" ] && mark_layer_done "$layer"
    ok "layer $layer complete"
  else
    die "layer $layer FAILED — see $LOG_DIR/${layer}.log ; fix, then re-run or './bootstrap.sh --from $layer'"
  fi
done

hr; ok "bootstrap finished. Verify anytime with:  ./bootstrap.sh --check"
