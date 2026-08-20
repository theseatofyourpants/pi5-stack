#!/usr/bin/env bash
# stack-freshness.sh — report how far behind every pin in versions.env has drifted,
# and whether any pin has become unreachable upstream.
#
# Read-only. Queries upstream, changes nothing, never upgrades. The judgement of
# WHETHER to bump belongs to the stack-refresh skill and the operator; this only
# establishes the facts, on a schedule, so "pinned for reproducibility" does not
# quietly become "pinned to something abandoned and vulnerable".
#
# Severity is deliberately tiered, because a job that shouts weekly stops being read:
#   [ALERT] exit 1 — the pin no longer resolves upstream (a rebuild would FAIL), or
#                    a tracked commit pin is older than ALERT_AGE_DAYS.
#   [stale]        — differs from upstream latest, or older than STALE_AGE_DAYS.
#   [float]        — no pin at all; visible so it stays a decision, not an accident.
#   [warn]         — could not be queried (offline, rate limit). Never an alert:
#                    an unreachable API is not a stale dependency.
#
# Usage: tools/stack-freshness.sh [--quiet] [--only VAR]
set -uo pipefail
STACK_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CONF="$STACK_ROOT/freshness.conf"
STALE_AGE_DAYS="${STALE_AGE_DAYS:-180}"
ALERT_AGE_DAYS="${ALERT_AGE_DAYS:-365}"

QUIET=0; ONLY=""
while [ $# -gt 0 ]; do case "$1" in
  --quiet) QUIET=1;;
  --only) ONLY="${2:?}"; shift;;
  -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; shift; done

# shellcheck disable=SC1090
source "$STACK_ROOT/versions.env" 2>/dev/null || { echo "cannot read versions.env" >&2; exit 2; }

LOGDIR="$HOME/stack-cron/logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/stack-freshness-$(date +%Y%m%d-%H%M%S).log"
log() { echo "$*" | tee -a "$LOG"; }
now=$(date +%s)

ALERTS=0; STALE=0; FLOAT=0; WARN=0; OK=0

# gh gives 5000 requests/hour authenticated vs 60 unauthenticated, which matters
# when this runs weekly across fourteen GitHub-hosted pins.
gh_api() {
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh api "$1" 2>/dev/null
  else
    curl -sS --max-time 20 -H 'Accept: application/vnd.github+json' "https://api.github.com/$1" 2>/dev/null
  fi
}
jq_get() { python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
v=d
for k in '$1'.split('.'):
    if k: v=v.get(k) if isinstance(v,dict) else None
print(v if v is not None else '')" 2>/dev/null; }

days_since() { [ -z "$1" ] && { echo ""; return; }
  local t; t=$(date -d "$1" +%s 2>/dev/null) || { echo ""; return; }
  echo $(( (now - t) / 86400 )); }

report() { # <level> <name> <text>
  [ -n "${NOTE:-}" ] && [ "$1" != ok ] && set -- "$1" "$2" "$3 — ${NOTE#\# }"
  case "$1" in
    ALERT) ALERTS=$((ALERTS+1)); log "[ALERT] $2: $3";;
    stale) STALE=$((STALE+1));   log "[stale] $2: $3";;
    float) FLOAT=$((FLOAT+1));   log "[float] $2: $3";;
    warn)  WARN=$((WARN+1));     log "[warn]  $2: $3";;
    ok)    OK=$((OK+1)); [ "$QUIET" -eq 1 ] || log "[ok]    $2: $3";;
  esac
}

log "=== stack-freshness @ $(date -Is) ==="
log "thresholds: stale >${STALE_AGE_DAYS}d, alert >${ALERT_AGE_DAYS}d"
log ""

while read -r VAR KIND SRC NOTE; do
  case "$VAR" in ''|'#'*) continue;; esac
  [ -n "$ONLY" ] && [ "$ONLY" != "$VAR" ] && continue
  pinned="${!VAR:-}"

  case "$KIND" in
    gh-commit)
      # Does the pinned commit still exist? A force-push or a deleted repo silently
      # breaks the rebuild, and nothing else in the stack would notice.
      info="$(gh_api "repos/$SRC/commits/$pinned")"
      pin_date="$(printf '%s' "$info" | jq_get 'commit.committer.date')"
      if [ -z "$pin_date" ]; then
        if [ -n "$(gh_api "repos/$SRC" | jq_get 'full_name')" ]; then
          report ALERT "$VAR" "pinned commit $pinned NO LONGER EXISTS in $SRC — a rebuild would fail"
        elif [ -n "$(gh_api 'rate_limit' | jq_get 'rate.limit')" ]; then
          # GitHub answers, but this repo does not: it was deleted, renamed or made
          # private. The rebuild clones from it, so this is broken TODAY — and it is
          # worth separating from "the Pi is offline", which is not a finding at all.
          report ALERT "$VAR" "repo $SRC IS GONE (deleted/renamed/private) — the rebuild clones from it"
        else
          report warn "$VAR" "cannot reach github — not checked (offline or rate-limited)"
        fi
        continue
      fi
      age="$(days_since "$pin_date")"
      behind="$(gh_api "repos/$SRC/compare/$pinned...HEAD" | jq_get 'ahead_by')"
      short="${pinned:0:7}"
      # Age alone is NOT staleness. A pin that is 247 days old and zero commits
      # behind is simply tracking an upstream nobody has touched — there is nothing
      # to bump, and reporting it weekly trains the reader to ignore the whole job.
      # Worth saying out loud though, because an unmaintained dependency is its own
      # kind of risk, just not one a version bump fixes.
      if [ "${behind:-0}" -eq 0 ] 2>/dev/null; then
        if [ -n "$age" ] && [ "$age" -gt "$STALE_AGE_DAYS" ]; then
          report ok "$VAR" "$short is upstream HEAD — but $SRC has had no commit in ${age}d (unmaintained?)"
        else
          report ok "$VAR" "$short is upstream HEAD (${age}d)  [$SRC]"
        fi
      else
        msg="$short is ${behind} commits behind HEAD, pinned ${age}d ago  [$SRC]"
        if [ -n "$age" ] && [ "$age" -gt "$ALERT_AGE_DAYS" ]; then report ALERT "$VAR" "$msg"
        else report stale "$VAR" "$msg"; fi
      fi
      ;;
    gh-release)
      latest="$(gh_api "repos/$SRC/releases/latest" | jq_get 'tag_name')"
      if [ -z "$latest" ]; then report warn "$VAR" "cannot read latest release of $SRC — not checked"; continue; fi
      # Tag schemes vary too much between projects to compare numerically; report
      # both and let a human decide which is actually newer.
      if [ "$pinned" = "$latest" ]; then report ok "$VAR" "$pinned == latest  [$SRC]"
      else report stale "$VAR" "pinned $pinned, upstream latest $latest  [$SRC]"; fi
      ;;
    pypi)
      latest="$(curl -sS --max-time 20 "https://pypi.org/pypi/$SRC/json" | jq_get 'info.version')"
      reqpy="$(curl -sS --max-time 20 "https://pypi.org/pypi/$SRC/json" | jq_get 'info.requires_python')"
      if [ -z "$latest" ]; then report warn "$VAR" "cannot read PyPI for $SRC — not checked"; continue; fi
      cur="${pinned##*==}"
      if [ "$cur" = "$latest" ]; then report ok "$VAR" "$cur == latest  [python $reqpy]"
      else report stale "$VAR" "pinned $cur, PyPI latest $latest  [latest needs python $reqpy]"; fi
      ;;
    npm)
      latest="$(curl -sS --max-time 20 "https://registry.npmjs.org/$SRC/latest" | jq_get 'version')"
      if [ -z "$latest" ]; then report warn "$VAR" "cannot read npm for $SRC — not checked"; continue; fi
      if [ "$pinned" = "$latest" ]; then report ok "$VAR" "$pinned == latest"
      else report ok "$VAR" "pinned $pinned, latest $latest — HELD BACK deliberately (node 22 compat)"; fi
      ;;
    dockerhub)
      img="${SRC%%:*}"; tag="${SRC##*:}"
      tok="$(curl -sS --max-time 20 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$img:pull" | jq_get 'token')"
      cur=""
      [ -n "$tok" ] && cur="$(curl -sS --max-time 20 -o /dev/null -D - \
        -H "Authorization: Bearer $tok" \
        -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
        "https://registry-1.docker.io/v2/$img/manifests/$tag" 2>/dev/null \
        | tr -d '\r' | awk -F': ' '/^[Dd]ocker-[Cc]ontent-[Dd]igest/{print $2}')"
      if [ -z "$cur" ]; then report warn "$VAR" "cannot read Docker Hub for $SRC — not checked"; continue; fi
      if [ "$pinned" = "$cur" ]; then report ok "$VAR" "digest matches $SRC"
      else report stale "$VAR" "pinned ${pinned:0:19}…, $SRC is now ${cur:0:19}…"; fi
      ;;
    golang)
      latest="$(curl -sS --max-time 20 'https://go.dev/dl/?mode=json' \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["version"])' 2>/dev/null)"
      if [ -z "$latest" ]; then report warn "$VAR" "cannot read go.dev — not checked"; continue; fi
      latest="${latest#go}"
      if [ "$pinned" = "$latest" ]; then report ok "$VAR" "$pinned == latest"
      else report stale "$VAR" "pinned $pinned, latest go$latest"; fi
      ;;
    selfupdate)
      report ok "$VAR" "'$pinned' — Claude Code self-updates in place; pin only for reproducible rebuilds"
      ;;
    unpinned)
      latest="$(curl -sS --max-time 20 "https://registry.npmjs.org/$SRC/latest" | jq_get 'version')"
      report float "$SRC" "NO PIN — resolves to latest at spawn time (currently ${latest:-unknown})"
      ;;
    *) report warn "$VAR" "unknown KIND '$KIND' in freshness.conf";;
  esac
done < "$CONF"

log ""
log "=== ${ALERTS} alert(s), ${STALE} stale, ${FLOAT} unpinned, ${WARN} unchecked, ${OK} current ==="
[ "$((ALERTS+STALE))" -gt 0 ] && log "    walk them with the stack-refresh skill (one pin at a time, verify between)"
ln -sfn "$LOG" "$LOGDIR/stack-freshness-latest.log"
ls -1t "$LOGDIR/stack-freshness-"2*.log 2>/dev/null | tail -n +13 | xargs -r rm -f
[ "$ALERTS" -gt 0 ] && exit 1
exit 0
