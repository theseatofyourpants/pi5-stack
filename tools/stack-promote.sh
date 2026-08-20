#!/usr/bin/env bash
# stack-promote.sh — pull a live host's version of a file back into the repo.
#
# The direction you actually work in. The Pi is where things get written and fixed
# first, so "the Pi is the source of truth" needs to be a supported operation rather
# than a note in a handoff doc that the next rebuild quietly overwrites.
#
# Un-renders the host copy back to canonical repo form and VERIFIES the round trip
# (render(unrender(host)) must reproduce the host file byte for byte) before writing
# anything. If the round trip fails, the substitution is lossy for that file and the
# promote is refused rather than silently committing a corrupted template.
#
# Never commits. Review the diff, then use the pi5-stack-sync skill to land it.
#
# Usage:
#   tools/stack-promote.sh --host pi ap-testbed/consent-portal/portal.py
#   tools/stack-promote.sh --host pi --apply ap-testbed/watcher.sh
#   tools/stack-promote.sh --host pi --apply ap-testbed        whole subtree
set -uo pipefail
STACK_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
source "$STACK_ROOT/tools/lib-manifest.sh"

LABEL=""; DO=0; FORCE=0; TARGETS=()
while [ $# -gt 0 ]; do case "$1" in
  --host) LABEL="${2:?}"; shift;;
  --apply) DO=1;;
  --force) FORCE=1;;
  -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  -*) echo "unknown arg: $1" >&2; exit 2;;
  *) TARGETS+=("$1");;
esac; shift; done
[ -n "$LABEL" ] || { echo "--host is required (pi|vm)" >&2; exit 2; }
[ ${#TARGETS[@]} -gt 0 ] || { echo "give at least one payload-relative path" >&2; exit 2; }

mf_load || exit 1
SSH_TGT="$(mf_host_field "$LABEL" ssh)" || { echo "unknown host: $LABEL" >&2; exit 2; }
HOME_D="$(mf_host_field "$LABEL" home)"
USER_N="$(mf_host_field "$LABEL" user)"
mf_host_up "$SSH_TGT" || { echo "$LABEL unreachable" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ "$DO" -eq 1 ] || echo "DRY RUN — nothing will be written to the repo. Add --apply to write."
echo "promoting from $LABEL ($HOME_D)"

in_target() { local t; for t in "${TARGETS[@]}"; do case "$1" in "$t"|"$t"/*) return 0;; esac; done; return 1; }

# Only the primary destination is promotable: /etc copies are derived artifacts that
# install-testbed.sh regenerates, so treating one as canonical would invert the flow.
SEL="$TMP/sel"; : > "$SEL"
while IFS= read -r rel; do
  in_target "$rel" || continue
  r="$(mf_lookup "$rel")"; [ -n "$r" ] || { echo "[skip]  no manifest rule: $rel"; continue; }
  IFS='|' read -r pat dest owner render hosts flags <<< "$r"
  if [ "$owner" != repo ]; then echo "[skip]  host-owned runtime state: $rel"; continue; fi
  if [ "$dest" = "-" ]; then echo "[skip]  not deployed to any host: $rel"; continue; fi
  if ! mf_host_wanted "$hosts" "$LABEL"; then echo "[skip]  not carried by $LABEL: $rel"; continue; fi
  hp="$(mf_hostpath "$rel" "$pat" "$dest" "$HOME_D")" || continue
  printf '%s\t%s\t%s\n' "$rel" "$hp" "$render" >> "$SEL"
done < <(cd "$PAYLOAD" && find . -type f -printf '%P\n' | sort)

# Files that exist on the host but not in the repo yet — the "I wrote a new tool on
# the Pi" case, which is the main reason this command exists.
for t in "${TARGETS[@]}"; do
  [ -e "$PAYLOAD/$t" ] && continue
  r="$(mf_lookup "$t")"; [ -n "$r" ] || { echo "[skip]  new file has no manifest rule: $t"; continue; }
  IFS='|' read -r pat dest owner render hosts flags <<< "$r"
  [ "$owner" = repo ] && [ "$dest" != "-" ] || continue
  hp="$(mf_hostpath "$t" "$pat" "$dest" "$HOME_D")" || continue
  printf '%s\t%s\t%s\n' "$t" "$hp" "$render" >> "$SEL"
done

[ -s "$SEL" ] || { echo "nothing matched"; exit 0; }
TREE="$TMP/tree"; cut -f2 "$SEL" | mf_pull "$SSH_TGT" "$TREE"

N=0; SKIP=0
while IFS=$'\t' read -r rel hp render; do
  host_f="$TREE/${hp#/}"; repo_f="$PAYLOAD/$rel"
  [ -f "$host_f" ] || { echo "[skip]  not present or unreadable on $LABEL: $hp"; SKIP=$((SKIP+1)); continue; }

  mf_unrender "$host_f" "$render" "$HOME_D" "$USER_N" > "$TMP/canon" || continue
  mf_render   "$TMP/canon" "$render" "$HOME_D" "$USER_N" > "$TMP/back" || continue
  if ! cmp -s "$TMP/back" "$host_f"; then
    echo "[REFUSE] $rel — un-render is lossy for this file (round trip did not reproduce it)"
    echo "         the host copy contains text the substitution cannot safely reverse."
    diff "$host_f" "$TMP/back" | head -6 | sed 's/^/         /'
    [ "$FORCE" -eq 1 ] || { SKIP=$((SKIP+1)); continue; }
    echo "         --force given, promoting anyway"
  fi

  if [ -f "$repo_f" ] && cmp -s "$repo_f" "$TMP/canon"; then continue; fi
  echo "[promote] $rel   <- $hp"
  if [ -f "$repo_f" ]; then diff "$repo_f" "$TMP/canon" | grep '^[<>]' | head -6 | sed 's/^/          /'
  else echo "          (new file, $(wc -l < "$TMP/canon") lines)"; fi
  if [ "$DO" -eq 1 ]; then
    install -D -m "$(stat -c %a "$host_f")" "$TMP/canon" "$repo_f"
  fi
  N=$((N+1))
done < "$SEL"

echo
if [ "$DO" -eq 1 ]; then
  echo "=== promoted $N file(s) into $PAYLOAD ($SKIP skipped) ==="
  echo "    review:  cd $STACK_ROOT && git diff"
  echo "    land it: use the pi5-stack-sync skill (secret-scan gate, then commit)"
else
  echo "=== $N file(s) would be promoted ($SKIP skipped) — re-run with --apply ==="
fi
exit 0
