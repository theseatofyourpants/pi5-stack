#!/usr/bin/env bash
# stack-drift.sh — detect divergence of the ap-testbed payload across the three copies:
#   repo  ~/pi5-stack/payload/ap-testbed   (rebuild source)
#   Pi    ~/ap-testbed                      (live, this box)
#   VM    ~/ap-testbed on kalivm            (live, over the tailnet)
#
# Why: on 2026-08-17 all three were simultaneously out of sync in DIFFERENT directions —
# the Pi's deploy-cert.sh was behind the repo, the VM was behind on 14 identity strings,
# and a portability refactor (__AP_DIR__/__STACK_USER__ rendering in bringup-net.sh and
# install-testbed.sh) had landed in repo+VM but never reached the Pi. Every one of those
# was found by hand, by accident. This job finds them on a schedule instead.
#
# THE COMPARISON RULE (this is the whole trick):
# The repo holds host-agnostic templates; hosts may hold either the same template (and
# render at runtime) or a pre-rendered instance. Both are legitimate. So a host file is
# considered IN SYNC if it is EITHER
#   (a) byte-identical to the repo copy, OR
#   (b) byte-identical to the repo copy rendered with that host's AP_DIR / STACK_USER.
# Anything else is real drift — different content, not a different rendering.
#
# Read-only. Never writes to the repo or either host. Exits 1 if drift is found so
# systemd surfaces it via `systemctl --failed`.
set -uo pipefail

REPO="${REPO_DIR:-$HOME/pi5-stack/payload/ap-testbed}"
VM_SSH="${VM_SSH:-kalivm@100.90.116.22}"

# host label | AP_DIR | STACK_USER | ssh target ('-' = local)
HOSTS=(
  "Pi|/home/tsoyp/ap-testbed|tsoyp|-"
  "VM|/home/kalivm/ap-testbed|kalivm|$VM_SSH"
)

# Never compared: runtime state, secrets, logs, caches — and the hot-pot bait share and
# honeytokens, which are deliberately rotated/reseeded at runtime by hotpot-maintain. The
# repo carries only .gitkeep placeholders for those dirs; comparing their contents would
# report the deception layer working as designed as if it were drift.
EXCLUDE_RE='^(state/|logs/|hotpot/smb/share/|hotpot/tokens/|.*__pycache__/|.*\.pyc$|.*\.log$|.*\.leases$)'

BASE="$HOME/stack-cron"; LOGDIR="$BASE/logs"; mkdir -p "$LOGDIR"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGDIR/stack-drift-${TS}.log"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

DRIFT=0; SKIPPED=0; CHECKED=0

log() { echo "$*" | tee -a "$LOG"; }

log "=== stack-drift @ $(date -Is) ==="
log "repo: $REPO"

if [ ! -d "$REPO" ]; then
  log "[ALERT] repo payload dir not found: $REPO"
  exit 1
fi

# Files to track = everything in the repo payload, minus excludes.
mapfile -t FILES < <(cd "$REPO" && find . -type f -printf '%P\n' | grep -Ev "$EXCLUDE_RE" | sort)
log "tracking ${#FILES[@]} file(s)"

render() {  # render <src> <ap_dir> <stack_user>
  sed -e "s|__AP_DIR__|$2|g" -e "s|__STACK_USER__|$3|g" "$1"
}

for entry in "${HOSTS[@]}"; do
  IFS='|' read -r LABEL AP_DIR STACK_USER SSH_TGT <<< "$entry"
  log ""
  log "--- $LABEL ($AP_DIR) ---"

  # Pull the whole host tree once; per-file ssh would be unusably slow over the tailnet.
  HOST_TREE="$TMP/$LABEL"; mkdir -p "$HOST_TREE"
  if [ "$SSH_TGT" = "-" ]; then
    if [ ! -d "$AP_DIR" ]; then log "[warn]  $LABEL: $AP_DIR not present — skipped"; SKIPPED=$((SKIPPED+1)); continue; fi
    tar -C "$AP_DIR" -cf - . 2>/dev/null | tar -C "$HOST_TREE" -xf - 2>/dev/null
  else
    # VM is frequently powered off — unreachable is a warning, never drift.
    if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_TGT" "test -d $AP_DIR" 2>/dev/null; then
      log "[warn]  $LABEL unreachable or $AP_DIR missing — skipped (normal when the MacBook is off)"
      SKIPPED=$((SKIPPED+1)); continue
    fi
    ssh -o BatchMode=yes -o ConnectTimeout=15 "$SSH_TGT" "tar -C $AP_DIR -cf - . 2>/dev/null" \
      | tar -C "$HOST_TREE" -xf - 2>/dev/null
  fi

  host_drift=0
  for f in "${FILES[@]}"; do
    CHECKED=$((CHECKED+1))
    repo_f="$REPO/$f"; host_f="$HOST_TREE/$f"

    if [ ! -f "$host_f" ]; then
      log "[DRIFT] $LABEL missing: $f"
      host_drift=$((host_drift+1)); continue
    fi

    # (a) byte-identical to the repo?
    cmp -s "$repo_f" "$host_f" && continue
    # (b) identical to the repo rendered for this host?
    render "$repo_f" "$AP_DIR" "$STACK_USER" > "$TMP/rendered" 2>/dev/null
    cmp -s "$TMP/rendered" "$host_f" && continue

    # Real content difference. Diff against the RAW repo copy, not the rendered one:
    # renderer scripts contain the placeholder strings as sed patterns in their own source,
    # so rendering them corrupts the text and makes the diff misleading.
    nlines="$(diff "$repo_f" "$host_f" 2>/dev/null | grep -c '^[<>]')"
    log "[DRIFT] $LABEL differs: $f (${nlines} changed line(s), '<' = repo, '>' = host)"
    diff "$repo_f" "$host_f" 2>/dev/null | grep '^[<>]' | head -4 | sed 's/^/          /' | tee -a "$LOG"
    host_drift=$((host_drift+1))
  done

  # Files present on the host but absent from the repo = no rebuild coverage.
  while IFS= read -r hf; do
    [ -z "$hf" ] && continue
    [ -f "$REPO/$hf" ] || { log "[DRIFT] $LABEL has untracked file (no rebuild coverage): $hf"; host_drift=$((host_drift+1)); }
  done < <(cd "$HOST_TREE" && find . -type f -printf '%P\n' 2>/dev/null | grep -Ev "$EXCLUDE_RE" | sort)

  if [ "$host_drift" -eq 0 ]; then
    log "[ok]    $LABEL in sync with repo"
  else
    log "[ok]    $LABEL: $host_drift file(s) drifted"
    DRIFT=$((DRIFT+host_drift))
  fi
done

log ""
log "=== done: ${DRIFT} drifted file(s), ${SKIPPED} host(s) skipped ==="
ln -sfn "$LOG" "$LOGDIR/stack-drift-latest.log"
ls -1t "$LOGDIR/stack-drift-"2*.log 2>/dev/null | tail -n +21 | xargs -r rm -f

[ "$DRIFT" -gt 0 ] && exit 1
exit 0
