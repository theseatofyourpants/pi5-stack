---
name: stack-restore
description: Restore the Pi 5 stack's data from a backup.sh archive — unpack a ~/backups/pi5-stack-backup-*.tar.gz, diff it against the current state, restore the trees, and re-add the secrets that were redacted at backup time. Use after data loss, on a rebuilt box, or to recover a specific engagement/skill/detection artifact. The recovery half of ~/stack-cron/backup.sh.
---

# stack-restore — recover from a stack backup

Pairs with `~/stack-cron/backup.sh` (deterministic daily snapshot). Backups are **secret-redacted and creds-omitted by design** — a full restore always needs a manual secret re-add at the end.

## 1. Pick the archive & read its manifest first
```bash
ls -1t ~/backups/pi5-stack-backup-*.tar.gz | head
TAR=~/backups/pi5-stack-backup-<TS>.tar.gz
tar -xzOf "$TAR" ./MANIFEST.txt        # what's inside, how many files, when
```

## 2. Extract to a staging dir and DIFF before overwriting
Never blast a backup straight over live data — you could clobber newer work.
```bash
STAGE=$(mktemp -d); tar -xzf "$TAR" -C "$STAGE"; ls -la "$STAGE"
# compare each tree against current before restoring
diff -rq "$STAGE/engagements" ~/engagements 2>/dev/null | head
diff -rq "$STAGE/agents"      ~/.claude/agents 2>/dev/null | head
```
Surface anything where the LIVE copy is newer/richer than the backup and confirm with the operator before overwriting it.

## 3. Restore the trees
```bash
# selective (preferred): copy back only what's needed, e.g. one report or the detection library
rsync -a "$STAGE/engagements/detection-library/" ~/engagements/detection-library/
# full: restore all captured trees (agents = skills, pi_design = vault, build-artifacts)
for t in engagements agents pi_design; do [ -d "$STAGE/$t" ] && rsync -a "$STAGE/$t/" ~/"${t/agents/.claude/agents}"/; done
```
(`build-artifacts/` holds `greynoise-mcp/server.py`, `build-sensors.sh`, `zeek-install.sh` — copy back to their homes if needed.)

## 4. Re-add secrets (they were redacted on backup)
The archived `claude-mcp-config.redacted.json` has `<REDACTED>` where live keys were. Do NOT overwrite your live `~/.claude.json` with it. Instead use it as a structural reference and re-key by hand via `mcp-doctor` (VT `VIRUSTOTAL_API_KEY`, GreyNoise `GREYNOISE_API_KEY`, Mythic `MYTHIC_PASSWORD`, Sliver op config `~/sliver-claude.cfg` — the last never lives in a backup).

## 5. Verify + clean up
Spot-check restored files, run `/stack-status`, then `rm -rf "$STAGE"`. If this was a fresh-box rebuild, the services themselves come from `~/pi5-stack` (bootstrap.sh) — this skill only restores the irreplaceable *data* on top.
