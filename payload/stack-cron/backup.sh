#!/usr/bin/env bash
# Deterministic, UNATTENDED snapshot of the Pi 5 stack's irreplaceable data.
# Mirrors the engagement-backup agent's Step 1, hard-wired to the safe defaults:
# local archive only, MCP secrets REDACTED (+ verified), captured creds OMITTED,
# NO git, NO remote/egress. No LLM, no network — safe to run from a timer.
set -uo pipefail
export HOME="${HOME:-/home/tsoyp}"

TS="$(date +%Y%m%d-%H%M%S)"
DEST="$HOME/backups"
LOGDIR="$HOME/stack-cron/logs"
STAGE="$(mktemp -d)"
mkdir -p "$DEST" "$LOGDIR"
LOG="$LOGDIR/backup-${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== stack backup @ ${TS} ==="

# 1) Redacted MCP config — and HARD-FAIL if any secret survives redaction.
python3 - "$STAGE/claude-mcp-config.redacted.json" <<'PY'
import json, os, sys
d = json.load(open(os.path.expanduser("~/.claude.json")))
ms = d.get("mcpServers", {})
HINTS = ("KEY", "TOKEN", "PASSWORD", "SECRET", "PASS")
for name, cfg in ms.items():
    env = cfg.get("env", {}) or {}
    for k in list(env):
        if any(h in k.upper() for h in HINTS) and env[k]:
            env[k] = "<REDACTED>"
# verify: no secret-hinted value left un-redacted
bad = [f"{n}.{k}" for n, c in ms.items()
       for k, v in (c.get("env", {}) or {}).items()
       if any(h in k.upper() for h in HINTS) and v not in ("", "<REDACTED>")]
if bad:
    sys.stderr.write("ABORT: secrets not redacted: " + ", ".join(bad) + "\n")
    sys.exit(3)
json.dump({"mcpServers": ms}, open(sys.argv[1], "w"), indent=2)
print("redacted config written + verified")
PY

# 2) Irreplaceable trees. Exclude rebuildable junk AND any credential/secret
#    evidence by filename (unattended runs never include captured creds).
for src in "$HOME/engagements" "$HOME/.claude/agents" "$HOME/pi_design"; do
  [ -e "$src" ] && rsync -a \
    --exclude '.venv' --exclude 'venv' --exclude 'node_modules' \
    --exclude '__pycache__' --exclude '*.tar.gz' \
    --exclude '*cred*' --exclude '*password*' --exclude '*secret*' \
    "$src" "$STAGE/"
done
mkdir -p "$STAGE/build-artifacts"
for f in "$HOME/greynoise-mcp/server.py" "$HOME/build-sensors.sh" "$HOME/zeek-install.sh"; do
  [ -f "$f" ] && cp "$f" "$STAGE/build-artifacts/"
done

# 3) Manifest
{
  echo "# Pi 5 stack backup — $TS (unattended; creds omitted; config redacted)"
  echo "host: $(hostname)  kernel: $(uname -r)"
  echo "engagements: $(find "$HOME/engagements" -type f 2>/dev/null | wc -l) files"
  echo "detection rows: $(grep -c '^|' "$HOME/engagements/detection-library/INDEX.md" 2>/dev/null || echo 0)"
  echo "skills: $(ls "$HOME"/.claude/agents/*.md 2>/dev/null | wc -l)"
} > "$STAGE/MANIFEST.txt"

# 4) Archive
ARCHIVE="$DEST/pi5-stack-backup-$TS.tar.gz"
tar -czf "$ARCHIVE" -C "$STAGE" .
rm -rf "$STAGE"
echo "ARCHIVE: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

# 5) Retention: keep the newest 14 archives
ls -1t "$DEST"/pi5-stack-backup-*.tar.gz 2>/dev/null | tail -n +15 | xargs -r rm -f
echo "retention: $(ls -1 "$DEST"/pi5-stack-backup-*.tar.gz 2>/dev/null | wc -l) archives kept in $DEST"
echo "=== backup done ==="
