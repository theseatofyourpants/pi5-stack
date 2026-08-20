#!/usr/bin/env bash
# stack-drift.sh — report divergence between the repo payload and every live host.
#
# Replaces the ap-testbed-only detector that carried its own hardcoded exclude list
# and render rule. All of that now comes from manifest.conf, so this tool, apply and
# promote cannot disagree about which files are host-specific.
#
# A host file is IN SYNC if it is EITHER byte-identical to the repo copy, OR
# byte-identical to the repo copy rendered for that host. Both are legitimate:
# the repo holds the canonical form, hosts may hold a rendered instance.
#
# Read-only. Never writes to the repo or to a host. Exits 1 if drift is found so
# systemd surfaces it in `systemctl --failed`.
set -uo pipefail
STACK_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
source "$STACK_ROOT/tools/lib-manifest.sh"

WANT_HOST=all; VERBOSE=0
while [ $# -gt 0 ]; do case "$1" in
  --host) WANT_HOST="${2:?}"; shift;;
  --verbose|-v) VERBOSE=1;;
  -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; shift; done

LOGDIR="$HOME/stack-cron/logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/stack-drift-$(date +%Y%m%d-%H%M%S).log"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
log() { echo "$*" | tee -a "$LOG"; }

mf_load || exit 1
log "=== stack-drift @ $(date -Is) ==="
log "repo: $PAYLOAD   manifest: $(basename "$MANIFEST") (${#MF_RULES[@]} rules)"

DRIFT=0; SKIPPED=0

for LABEL in $(mf_host_labels); do
  [ "$WANT_HOST" = all ] || [ "$WANT_HOST" = "$LABEL" ] || continue
  SSH_TGT="$(mf_host_field "$LABEL" ssh)"
  HOME_D="$(mf_host_field "$LABEL" home)"
  USER_N="$(mf_host_field "$LABEL" user)"
  log ""
  log "--- $LABEL ($HOME_D) ---"

  if ! mf_host_up "$SSH_TGT"; then
    log "[warn]  $LABEL unreachable — skipped (normal when the MacBook is off)"
    SKIPPED=$((SKIPPED+1)); continue
  fi

  # Every file this host should carry, and where — including the second
  # destinations install-testbed.sh renders into /etc. One tar pulls them all;
  # a stat-per-file over the tailnet took minutes.
  MAP="$TMP/map.$LABEL"
  mf_map "$LABEL" "$HOME_D" > "$MAP" 2>>"$LOG"
  log "        $(wc -l < "$MAP") tracked path(s)"

  TREE="$TMP/tree.$LABEL"
  cut -f2 "$MAP" | mf_pull "$SSH_TGT" "$TREE"

  # A file the tar did not yield is either genuinely absent or present but
  # unreadable by this unprivileged job (/etc/sudoers.d is 0440 root:root). Those
  # are very different facts, and calling the second one drift would make the job
  # cry wolf every single day. Probe the gap before classifying it.
  MISSING="$TMP/missing.$LABEL"; : > "$MISSING"
  while IFS=$'\t' read -r rel hp render; do
    [ -f "$TREE/${hp#/}" ] || echo "$hp" >> "$MISSING"
  done < "$MAP"
  EXISTS="$TMP/exists.$LABEL"; : > "$EXISTS"
  if [ -s "$MISSING" ]; then
    if [ "$SSH_TGT" = "-" ]; then
      while IFS= read -r p; do [ -e "$p" ] && echo "$p"; done < "$MISSING" > "$EXISTS"
    else
      ssh -o BatchMode=yes -o ConnectTimeout=15 "$SSH_TGT" \
        'while IFS= read -r p; do [ -e "$p" ] && echo "$p"; done' < "$MISSING" > "$EXISTS"
    fi
  fi

  host_drift=0
  while IFS=$'\t' read -r rel hp render; do
    repo_f="$PAYLOAD/$rel"; host_f="$TREE/${hp#/}"
    if [ ! -f "$host_f" ]; then
      if grep -qxF "$hp" "$EXISTS"; then
        log "[warn]  $LABEL unreadable (needs root, not checked): $hp"
      else
        log "[DRIFT] $LABEL missing: $hp   (from $rel)"
        host_drift=$((host_drift+1))
      fi
      continue
    fi
    cmp -s "$repo_f" "$host_f" && continue
    mf_render "$repo_f" "$render" "$HOME_D" "$USER_N" > "$TMP/rendered" 2>/dev/null
    cmp -s "$TMP/rendered" "$host_f" && continue

    # Diff against the RAW repo copy, not the rendered one: renderer scripts carry
    # the placeholder strings in their own source as sed patterns, so rendering them
    # corrupts the text and makes the diff read as nonsense.
    n="$(diff "$repo_f" "$host_f" 2>/dev/null | grep -c '^[<>]')"
    log "[DRIFT] $LABEL differs: $hp ($n changed line(s), '<' = repo, '>' = host)"
    [ "${hp##*/}" = "${rel##*/}" ] || log "          (from $rel)"
    diff "$repo_f" "$host_f" 2>/dev/null | grep '^[<>]' \
      | head -$([ "$VERBOSE" -eq 1 ] && echo 40 || echo 4) | sed 's/^/          /' | tee -a "$LOG"
    host_drift=$((host_drift+1))
  done < "$MAP"

  # Host files the repo has no rule for = no rebuild coverage. Only for directories
  # flagged as exclusively repo-owned; ~/.claude/agents and /etc/systemd/system also
  # hold things that legitimately are not ours.
  while IFS=$'\t' read -r pat dest flags; do
    root="$(mf_hostpath "" "$pat" "$dest" "$HOME_D")"; root="${root%/}"
    lit="$(mf_litdir "$pat")"
    if [ "$SSH_TGT" = "-" ]; then found="$(find "$root" -type f -printf '%P\n' 2>/dev/null)"
    else found="$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$SSH_TGT" \
                    "find $root -type f -printf '%P\\n' 2>/dev/null")"; fi
    while IFS= read -r sub; do
      [ -n "$sub" ] || continue
      rel="${lit:+$lit/}$sub"
      r="$(mf_lookup "$rel")"; IFS='|' read -r _ _ owner _ _ _ <<< "$r"
      [ "$owner" = host ] && continue            # runtime state, expected
      [ -f "$PAYLOAD/$rel" ] && continue         # tracked
      log "[DRIFT] $LABEL untracked (no rebuild coverage): $rel"
      host_drift=$((host_drift+1))
    done <<< "$found"
  done < <(awk -F'|' '$6=="untracked"{print $1"\t"$2"\t"$6}' <(printf '%s\n' "${MF_RULES[@]}"))

  if [ "$host_drift" -eq 0 ]; then log "[ok]    $LABEL in sync with repo"
  else log "[ok]    $LABEL: $host_drift file(s) drifted"; DRIFT=$((DRIFT+host_drift)); fi
done

log ""
log "=== done: ${DRIFT} drifted file(s), ${SKIPPED} host(s) skipped ==="
[ "$DRIFT" -gt 0 ] && log "    fix with: $STACK_ROOT/tools/stack-apply.sh --host <h>   (repo -> host)"
[ "$DRIFT" -gt 0 ] && log "    or keep the host's version: $STACK_ROOT/tools/stack-promote.sh --host <h> <path>"
ln -sfn "$LOG" "$LOGDIR/stack-drift-latest.log"
ls -1t "$LOGDIR/stack-drift-"2*.log 2>/dev/null | tail -n +21 | xargs -r rm -f
[ "$DRIFT" -gt 0 ] && exit 1
exit 0
