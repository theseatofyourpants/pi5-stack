#!/usr/bin/env bash
# lib-manifest.sh — shared manifest parsing, path mapping and host rendering for
# the day-2 tools (stack-apply, stack-promote, stack-drift).
#
# Every rule about which files are host-specific and how they are rendered lives in
# manifest.conf and is read from here. Nothing in this file hardcodes a path.

STACK_ROOT="${STACK_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST="${MANIFEST:-$STACK_ROOT/manifest.conf}"
PAYLOAD="${PAYLOAD:-$STACK_ROOT/payload}"

MF_RULES=()   # primary rules  "pattern|dest|owner|render|hosts|flags", file order kept
MF_EXTRA=()   # additive rules (leading '+'): a second destination for a placed file
MF_HOSTS=()   # "label|ssh|home|user"

mf_load() {
  [ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; return 1; }
  MF_RULES=(); MF_EXTRA=(); MF_HOSTS=()
  local a b c d e f
  while read -r a b c d e f _; do
    case "$a" in ''|'#'*) continue;; esac
    if [ "$a" = "@host" ]; then
      MF_HOSTS+=("$b|$c|$d|$e")
    elif [ "${a#+}" != "$a" ]; then
      [ -n "${e:-}" ] || { echo "manifest: short additive rule: $a" >&2; return 1; }
      MF_EXTRA+=("${a#+}|$b|$c|$d|$e|${f:--}")
    else
      [ -n "${e:-}" ] || { echo "manifest: short rule: $a" >&2; return 1; }
      MF_RULES+=("$a|$b|$c|$d|$e|${f:--}")
    fi
  done < "$MANIFEST"
  [ ${#MF_RULES[@]} -gt 0 ] || { echo "manifest: no rules parsed" >&2; return 1; }
}

# --- host table --------------------------------------------------------------
mf_host_labels() { local h; for h in "${MF_HOSTS[@]}"; do echo "${h%%|*}"; done; }
mf_host_field() { # <label> <ssh|home|user>
  local h l ssh home user
  for h in "${MF_HOSTS[@]}"; do
    IFS='|' read -r l ssh home user <<< "$h"
    [ "$l" = "$1" ] || continue
    case "$2" in ssh) echo "$ssh";; home) echo "$home";; user) echo "$user";; esac
    return 0
  done
  return 1
}

# --- glob matching -----------------------------------------------------------
# '*' never crosses a '/'; a trailing '/**' matches the whole subtree; a leading
# '**/' matches at any depth. Deliberately hand-rolled: bash's [[ == ]] lets '*'
# cross '/', which would make stack-cron/*.sh silently swallow stack-cron/systemd/.
_mf_seg_match() { # <pattern-without-leading-**/> <path>
  local pat="$1" p="$2" base ps xs
  case "$pat" in
    *'/**') base="${pat%/**}"
            case "$p" in "$base"|"$base"/*) return 0;; *) return 1;; esac;;
  esac
  ps="${pat//[!\/]/}"; xs="${p//[!\/]/}"
  [ "${#ps}" = "${#xs}" ] || return 1
  [[ "$p" == $pat ]]
}
mf_pat_match() { # <pattern> <relpath>
  local pat="$1" p="$2" tail rest
  case "$pat" in
    '**/'*) tail="${pat#'**/'}"
            _mf_seg_match "$tail" "$p" && return 0
            rest="$p"
            while [ "$rest" != "${rest#*/}" ]; do
              rest="${rest#*/}"
              _mf_seg_match "$tail" "$rest" && return 0
            done
            return 1;;
  esac
  _mf_seg_match "$pat" "$p"
}

# Last matching rule wins (see manifest.conf header).
mf_lookup() { # <relpath> -> "pattern|dest|owner|render|hosts|flags", empty if none
  local p="$1" r hit=""
  for r in "${MF_RULES[@]}"; do
    mf_pat_match "${r%%|*}" "$p" && hit="$r"
  done
  [ -n "$hit" ] && echo "$hit"
}

# All additive rules matching a path — extra destinations, never ownership.
mf_extra() { # <relpath> -> zero or more "pattern|dest|owner|render|hosts|flags"
  local p="$1" r
  for r in "${MF_EXTRA[@]}"; do mf_pat_match "${r%%|*}" "$p" && echo "$r"; done
}

# Longest leading run of glob-free segments — the part of the path that DEST replaces.
mf_litdir() { # <pattern>
  local pat="$1" out="" seg rest="$pat"
  while [ -n "$rest" ]; do
    seg="${rest%%/*}"
    case "$seg" in *'*'*) break;; esac
    [ "$rest" = "${rest#*/}" ] && break   # last segment is a filename, not a dir
    out="${out:+$out/}$seg"; rest="${rest#*/}"
  done
  echo "$out"
}

# Map a repo-relative payload path to its absolute path on a host.
# A DEST with a trailing '/' is a directory and the path below PATH's literal prefix
# is appended; without one, DEST is the exact destination filename — which is how
# apt-authorize.sh lands as /usr/local/sbin/apt-testbed-authorize.
mf_hostpath() { # <relpath> <pattern> <dest> <home>
  local rel="$1" lit dest="$3" home="$4"
  [ "$dest" = "-" ] && return 1
  case "$dest" in '~/'*) dest="$home/${dest#\~/}";; '~'|'~/') dest="$home/";; esac
  case "$dest" in
    */) lit="$(mf_litdir "$2")"; [ -n "$lit" ] && rel="${rel#$lit/}"; echo "${dest}${rel}";;
     *) echo "$dest";;
  esac
}

mf_host_wanted() { # <hosts-field> <label>
  case ",$1," in *",$2,"*) return 0;; esac; return 1
}

# The full deployment map for one host: every repo-owned payload file paired with
# every place it must appear (primary destination plus any additive ones).
# Emits TSV: relpath <tab> host-abs-path <tab> render-mode
mf_map() { # <label> <home>
  local label="$1" home="$2" rel r e pat dest owner render hosts flags hp
  while IFS= read -r rel; do
    r="$(mf_lookup "$rel")"
    if [ -z "$r" ]; then echo "mf_map: no rule for $rel" >&2; continue; fi
    IFS='|' read -r pat dest owner render hosts flags <<< "$r"
    if [ "$owner" = repo ] && [ "$dest" != "-" ] && mf_host_wanted "$hosts" "$label"; then
      hp="$(mf_hostpath "$rel" "$pat" "$dest" "$home")" \
        && printf '%s\t%s\t%s\n' "$rel" "$hp" "$render"
    fi
    [ "$owner" = repo ] || continue
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      IFS='|' read -r pat dest owner render hosts flags <<< "$e"
      [ "$owner" = repo ] && [ "$dest" != "-" ] && mf_host_wanted "$hosts" "$label" || continue
      hp="$(mf_hostpath "$rel" "$pat" "$dest" "$home")" \
        && printf '%s\t%s\t%s\n' "$rel" "$hp" "$render"
    done < <(mf_extra "$rel")
  done < <(cd "$PAYLOAD" && find . -type f -printf '%P\n' | sort)
}

# --- rendering ---------------------------------------------------------------
# The repo copy is the canonical form. 'render' turns it into what a given host
# should hold; 'unrender' turns a host copy back into canonical form. They must be
# exact inverses — stack-promote verifies that round trip before writing.
mf_render() { # <file> <mode> <home> <user> ; canonical -> host
  local f="$1" mode="$2" home="$3" user="$4"
  case "$mode" in
    -)        cat "$f";;
    apdir)    sed -e "s|__AP_DIR__|$home/ap-testbed|g" -e "s|__STACK_USER__|$user|g" "$f";;
    homeuser) sed -e "s#/home/tsoyp#$home#g" -e "s#User=tsoyp#User=$user#g" \
                  -e "s#Group=tsoyp#Group=$user#g" -e "s#tsoyp:tsoyp#$user:$user#g" "$f";;
    *) echo "unknown render mode: $mode" >&2; return 1;;
  esac
}
mf_unrender() { # <file> <mode> <home> <user> ; host -> canonical
  local f="$1" mode="$2" home="$3" user="$4"
  case "$mode" in
    -)        cat "$f";;
    # AP_DIR first: it contains the user string, so replacing the user first would
    # corrupt the longer token.
    apdir)    sed -e "s|$home/ap-testbed|__AP_DIR__|g" -e "s|\\b$user\\b|__STACK_USER__|g" "$f";;
    homeuser) sed -e "s#User=$user#User=tsoyp#g" -e "s#Group=$user#Group=tsoyp#g" \
                  -e "s#$user:$user#tsoyp:tsoyp#g" -e "s#$home#/home/tsoyp#g" "$f";;
    *) echo "unknown render mode: $mode" >&2; return 1;;
  esac
}

# --- host file transfer ------------------------------------------------------
# One tar round trip per host instead of a stat/cat per file: over the tailnet the
# per-file version took minutes.
mf_pull() { # <ssh|-> <destdir> ; absolute host paths on stdin
  local ssh_tgt="$1" out="$2"
  mkdir -p "$out"
  if [ "$ssh_tgt" = "-" ]; then
    sed 's|^/||' | tar -C / -cf - --no-recursion --ignore-failed-read -T - 2>/dev/null \
      | tar -C "$out" -xf - 2>/dev/null
  else
    sed 's|^/||' | ssh -o BatchMode=yes -o ConnectTimeout=15 "$ssh_tgt" \
      "tar -C / -cf - --no-recursion --ignore-failed-read -T - 2>/dev/null" \
      | tar -C "$out" -xf - 2>/dev/null
  fi
  return 0
}
mf_host_up() { # <ssh|->
  [ "$1" = "-" ] && return 0
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$1" true 2>/dev/null
}
