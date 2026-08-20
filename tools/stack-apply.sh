#!/usr/bin/env bash
# stack-apply.sh — push repo-owned payload files to a host, rendered for that host.
#
# This is the piece the stack was missing. The only existing way to get a repo file
# onto a live box was to run a bootstrap layer, and layers also apt-install and
# re-clone live repos — which is why they are documented as fresh-box-only, and why
# a portability refactor sat in the repo for days without ever reaching the Pi.
#
# Files only. Never apt, never git clone, never a schema change. systemd units are
# reloaded, but services are NOT restarted unless you ask: on the Pi, restarting the
# AP stack drops the network you are talking to it over.
#
# Usage:
#   tools/stack-apply.sh --host pi                    dry run, everything (default)
#   tools/stack-apply.sh --host pi --apply            actually write
#   tools/stack-apply.sh --host vm --apply ap-testbed limit to a payload subtree
#   tools/stack-apply.sh --host pi --apply --restart  also daemon-reload + restart
set -uo pipefail
STACK_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
source "$STACK_ROOT/tools/lib-manifest.sh"

WANT_HOST=""; DO=0; RESTART=0; FILTERS=()
while [ $# -gt 0 ]; do case "$1" in
  --host) WANT_HOST="${2:?}"; shift;;
  --apply) DO=1;;
  --restart) RESTART=1;;
  -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  -*) echo "unknown arg: $1" >&2; exit 2;;
  *) FILTERS+=("$1");;
esac; shift; done
[ -n "$WANT_HOST" ] || { echo "--host is required (pi|vm|all)" >&2; exit 2; }

mf_load || exit 1
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ "$DO" -eq 1 ] || echo "DRY RUN — nothing will be written. Add --apply to commit changes."

in_filter() { # empty filter list = everything
  [ ${#FILTERS[@]} -eq 0 ] && return 0
  local f; for f in "${FILTERS[@]}"; do case "$1" in "$f"|"$f"/*) return 0;; esac; done
  return 1
}

# Write stdin to a path on a host, creating parent dirs, with the repo file's mode.
# A syntactically invalid file under /etc/sudoers.d costs you sudo on that box, so
# it is validated with visudo before it is allowed anywhere near the destination —
# the same guard install-testbed.sh applies.
put_file() { # <ssh|-> <destpath> <mode> <need_sudo>
  local tgt="$1" dest="$2" mode="$3" sudo_="$4" S=""
  [ "$sudo_" = 1 ] && S="sudo "
  case "$dest" in
    /etc/sudoers.d/*|/etc/sudoers)
      # sudo silently IGNORES a sudoers file that is not 0440, so a mode mistake
      # produces a rule that looks installed and does nothing. Refuse rather than
      # install something inert.
      if [ "$mode" != 0440 ]; then
        echo "  !! REFUSED: $dest must be mode 0440, manifest says $mode" >&2
        return 1
      fi
      cat > "$TMP/sudoers.check"
      if ! visudo -cf "$TMP/sudoers.check" >/dev/null 2>&1; then
        echo "  !! REFUSED: $dest failed visudo validation — not written" >&2
        return 1
      fi
      exec < "$TMP/sudoers.check";;
  esac
  if [ "$tgt" = "-" ]; then
    ${S}install -D -m "$mode" /dev/stdin "$dest"
  else
    ssh -o BatchMode=yes "$tgt" "${S}install -D -m $mode /dev/stdin '$dest'"
  fi
}

TOTAL=0; CHANGED=0; UNITS=0
for LABEL in $(mf_host_labels); do
  [ "$WANT_HOST" = all ] || [ "$WANT_HOST" = "$LABEL" ] || continue
  SSH_TGT="$(mf_host_field "$LABEL" ssh)"
  HOME_D="$(mf_host_field "$LABEL" home)"
  USER_N="$(mf_host_field "$LABEL" user)"
  echo; echo "--- $LABEL ($HOME_D) ---"
  if ! mf_host_up "$SSH_TGT"; then echo "[warn]  $LABEL unreachable — skipped"; continue; fi

  MAP="$TMP/map.$LABEL"
  mf_map "$LABEL" "$HOME_D" 2>/dev/null | while IFS=$'\t' read -r rel hp render mode; do
    in_filter "$rel" && printf '%s\t%s\t%s\t%s\n' "$rel" "$hp" "$render" "$mode"
  done > "$MAP"

  TREE="$TMP/tree.$LABEL"; cut -f2 "$MAP" | mf_pull "$SSH_TGT" "$TREE"

  while IFS=$'\t' read -r rel hp render mode; do
    TOTAL=$((TOTAL+1))
    repo_f="$PAYLOAD/$rel"; host_f="$TREE/${hp#/}"
    mf_render "$repo_f" "$render" "$HOME_D" "$USER_N" > "$TMP/want" || continue

    # Root-only files never make it into the unprivileged pull. Try a privileged
    # read before assuming they are absent, or we rewrite them on every single run.
    verb="update"
    if [ ! -f "$host_f" ]; then
      if mf_read_priv "$SSH_TGT" "$hp" > "$TMP/priv" 2>/dev/null && [ -s "$TMP/priv" ]; then
        host_f="$TMP/priv"
      else
        verb="create"
      fi
    fi
    # Content alone is not enough: a sudoers file with the right text and the wrong
    # mode is inert, and comparing only bytes would report it as already applied.
    if [ -f "$host_f" ] && cmp -s "$TMP/want" "$host_f"; then
      [ "$mode" = "-" ] && continue
      [ "$(stat -c %a "$host_f")" = "$mode" ] && continue
      verb="chmod "
    fi

    # Only fall back to the repo file's mode when the manifest does not specify one.
    [ "$mode" = "-" ] && mode="$(stat -c %a "$repo_f")"
    need_sudo=0; case "$hp" in "$HOME_D"/*) ;; *) need_sudo=1;; esac
    case "$hp" in /etc/systemd/system/*) UNITS=$((UNITS+1));; esac

    if [ "$DO" -eq 1 ]; then
      if put_file "$SSH_TGT" "$hp" "$mode" "$need_sudo" < "$TMP/want"; then
        echo "[$verb] $hp"; CHANGED=$((CHANGED+1))
      else
        echo "[FAIL]   $hp"
      fi
    else
      echo "[$verb] $hp"
      [ -f "$host_f" ] && diff "$host_f" "$TMP/want" | grep '^[<>]' | head -4 | sed 's/^/          /'
      CHANGED=$((CHANGED+1))
    fi
  done < "$MAP"

  if [ "$UNITS" -gt 0 ]; then
    if [ "$DO" -eq 1 ] && [ "$RESTART" -eq 1 ]; then
      if [ "$SSH_TGT" = "-" ]; then sudo systemctl daemon-reload
      else ssh -o BatchMode=yes "$SSH_TGT" "sudo systemctl daemon-reload"; fi
      echo "[reload] systemd daemon-reload done"
    elif [ "$UNITS" -gt 0 ]; then
      echo "[note]   $UNITS systemd unit(s) touched — run: sudo systemctl daemon-reload"
    fi
  fi
done

echo
if [ "$DO" -eq 1 ]; then echo "=== applied $CHANGED of $TOTAL tracked file(s) ==="
else echo "=== $CHANGED of $TOTAL tracked file(s) would change — re-run with --apply ==="; fi
exit 0
