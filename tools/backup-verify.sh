#!/usr/bin/env bash
# backup-verify.sh — prove the nightly backup can actually be restored.
#
# backup.sh has produced a clean 102MB archive every night for weeks. Not one of
# them had ever been unpacked. An untested backup is a belief, not a control: the
# failure mode is silent by construction, and it is only ever discovered on the day
# it matters. This rehearses the restore against the newest archive.
#
# Checks, in the order that matters:
#   1. an archive exists and is recent          (a backup that stopped running)
#   2. gzip + tar integrity                     (truncated / corrupt archive)
#   3. it actually extracts to disk             (integrity passes, extraction fails)
#   4. every expected top-level artifact present (backup silently narrowed)
#   5. content is non-trivial                   (an empty tree that "restores" fine)
#   6. no secret survived redaction             (the archive is a leak, not a backup)
#
# Read-only with respect to the real stack: it extracts into a temp dir and removes
# it. Never touches ~/backups, never restores over anything.
#
# Usage: tools/backup-verify.sh [--keep] [--archive PATH]
set -uo pipefail
DEST="${BACKUP_DIR:-$HOME/backups}"
LOGDIR="$HOME/stack-cron/logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/backup-verify-$(date +%Y%m%d-%H%M%S).log"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-3}"
MIN_ENGAGEMENT_FILES="${MIN_ENGAGEMENT_FILES:-50}"

KEEP=0; ARCHIVE=""
while [ $# -gt 0 ]; do case "$1" in
  --keep) KEEP=1;;
  --archive) ARCHIVE="${2:?}"; shift;;
  -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; shift; done

log() { echo "$*" | tee -a "$LOG"; }
FAIL=0
fail() { log "[ALERT] $*"; FAIL=$((FAIL+1)); }
ok()   { log "[ok]    $*"; }

TMP="$(mktemp -d)"
cleanup() { [ "$KEEP" -eq 1 ] && { log "kept: $TMP"; return; }; rm -rf "$TMP"; }
trap cleanup EXIT

log "=== backup-verify @ $(date -Is) ==="

# 1. recent archive present
[ -n "$ARCHIVE" ] || ARCHIVE="$(ls -1t "$DEST"/pi5-stack-backup-*.tar.gz 2>/dev/null | head -1)"
if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  fail "no backup archive found in $DEST — the nightly job is not producing output"
  log ""; log "=== ${FAIL} failure(s) ==="; exit 1
fi
age_d=$(( ( $(date +%s) - $(stat -c %Y "$ARCHIVE") ) / 86400 ))
size=$(du -h "$ARCHIVE" | cut -f1)
log "archive: $(basename "$ARCHIVE")  ($size, ${age_d}d old)"
if [ "$age_d" -gt "$MAX_AGE_DAYS" ]; then
  fail "newest backup is ${age_d}d old (>${MAX_AGE_DAYS}d) — stack-backup.timer may be dead"
else ok "recent (<=${MAX_AGE_DAYS}d)"; fi

# 2. integrity — decompress and read every member without extracting
if tar -tzf "$ARCHIVE" >/dev/null 2>&1; then ok "gzip + tar integrity"
else fail "archive is CORRUPT — tar cannot read it"; log ""; log "=== ${FAIL} failure(s) ==="; exit 1; fi

# 3. real extraction. Integrity can pass while extraction fails on permissions,
#    path length, or a device/hardlink the archive cannot recreate.
if tar -xzf "$ARCHIVE" -C "$TMP" 2>>"$LOG"; then ok "extracts cleanly to disk"
else fail "extraction FAILED — see $LOG"; log ""; log "=== ${FAIL} failure(s) ==="; exit 1; fi

# 4. expected artifacts. Guards against the backup silently narrowing — a source
#    path that got renamed and now rsyncs nothing would still archive fine.
for want in MANIFEST.txt claude-mcp-config.redacted.json engagements agents pi_design; do
  if [ -e "$TMP/$want" ]; then ok "present: $want"
  else fail "MISSING from the archive: $want"; fi
done

# 5. non-trivial content
n_eng=$(find "$TMP/engagements" -type f 2>/dev/null | wc -l)
n_agents=$(ls -1 "$TMP/agents"/*.md 2>/dev/null | wc -l)
if [ "$n_eng" -ge "$MIN_ENGAGEMENT_FILES" ]; then ok "engagements: $n_eng files"
else fail "engagements has only $n_eng files (<$MIN_ENGAGEMENT_FILES) — restoring this would lose work"; fi
if [ "$n_agents" -ge 20 ]; then ok "agents: $n_agents definitions"
else fail "agents has only $n_agents definitions (<20)"; fi

# 6. the archive must not itself be a secret leak. backup.sh redacts and self-checks,
#    but that check runs on the data going IN; this one runs on what came OUT.
leak=0
if grep -qE '"(VT_API_KEY|VIRUSTOTAL_API_KEY|GREYNOISE_API_KEY|MYTHIC_PASSWORD)"\s*:\s*"[^"<]' \
     "$TMP/claude-mcp-config.redacted.json" 2>/dev/null; then
  fail "UNREDACTED SECRET in claude-mcp-config.redacted.json"; leak=1
fi
if [ -n "$(find "$TMP" -type f \( -name '*cred*' -o -name '*password*' -o -name 'id_*' \) \
           ! -name '*.md' -print -quit 2>/dev/null)" ]; then
  fail "credential-shaped file present in the archive"; leak=1
fi
[ "$leak" -eq 0 ] && ok "no secrets survived redaction"

log ""
if [ "$FAIL" -eq 0 ]; then
  log "=== restore rehearsal PASSED — $(basename "$ARCHIVE") is restorable ==="
else
  log "=== ${FAIL} failure(s) — the backup is NOT known-good ==="
  log "    walk a real restore with the stack-restore skill before trusting it"
fi
ln -sfn "$LOG" "$LOGDIR/backup-verify-latest.log"
ls -1t "$LOGDIR/backup-verify-"2*.log 2>/dev/null | tail -n +7 | xargs -r rm -f
exit $(( FAIL > 0 ))
