#!/usr/bin/env bash
# stack-watchdog.sh — keep the C2 backends alive between reboots and expose their
# liveness to the admin console / e-ink panel.
#
# Runs as ROOT from stack-watchdog.timer every few minutes. It:
#   * ensures Sliver (systemd) is active AND actually listening on 31337;
#     restarts it if the service wedged (up but not answering);
#   * detects/nudges any Mythic container that fell over (they already carry
#     restart=always, so this is belt-and-suspenders + reporting);
#   * writes state/backends.json so the dashboard/panel can show real status
#     instead of a bare up/down probe.
#
# It NEVER pkills and never touches the prober/hot-pot isolation — pure
# read/heal/report on our own backends.
set -uo pipefail

STATE_DIR=/home/tsoyp/ap-testbed/state
STATUS="$STATE_DIR/backends.json"
SLIVER_PORT=31337
TAG=stack-watchdog

log(){ logger -t "$TAG" -- "$*" 2>/dev/null; echo "[$(date -Is)] $*"; }
listening(){ ss -tlnH "sport = :$1" 2>/dev/null | grep -q ":$1"; }

# ---------- Sliver ----------
sliver_state=down; sliver_action=none
if systemctl is-active --quiet sliver.service; then
  if listening "$SLIVER_PORT"; then
    sliver_state=up
  else
    log "Sliver service active but not listening on $SLIVER_PORT — restarting"
    systemctl restart sliver.service && sliver_action=restarted
    sleep 3; listening "$SLIVER_PORT" && sliver_state=up
  fi
else
  log "Sliver service not active — starting"
  systemctl start sliver.service && sliver_action=started
  sleep 3; listening "$SLIVER_PORT" && sliver_state=up
fi

# ---------- Mythic (docker restart=always; we detect + gently restart exited) ----------
mythic_total=$(docker ps -a --filter 'name=mythic_' --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
mythic_running=$(docker ps --filter 'name=mythic_' --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
mythic_healthy=$(docker ps --filter 'name=mythic_' --filter 'health=healthy' --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
mythic_action=none
exited=$(docker ps -a --filter 'name=mythic_' --filter 'status=exited' --format '{{.Names}}' 2>/dev/null)
if [ -n "$exited" ]; then
  log "Mythic exited containers: $exited — starting"
  for c in $exited; do docker start "$c" >/dev/null 2>&1 && mythic_action=started-exited; done
  mythic_running=$(docker ps --filter 'name=mythic_' --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
fi
mythic_state=down
[ "${mythic_running:-0}" -gt 0 ] && mythic_state=partial
[ "${mythic_total:-0}" -gt 0 ] && [ "${mythic_running:-0}" -ge "${mythic_total:-99}" ] && mythic_state=up

# ---------- publish status ----------
mkdir -p "$STATE_DIR"
cat > "$STATUS.tmp" <<JSON
{
  "ts": "$(date -Is)",
  "sliver": { "state": "$sliver_state", "port": $SLIVER_PORT, "action": "$sliver_action" },
  "mythic": { "state": "$mythic_state", "healthy": ${mythic_healthy:-0}, "running": ${mythic_running:-0}, "total": ${mythic_total:-0}, "action": "$mythic_action" }
}
JSON
mv "$STATUS.tmp" "$STATUS"
chown tsoyp:tsoyp "$STATUS" 2>/dev/null || true
log "sliver=$sliver_state mythic=$mythic_state ($mythic_running/$mythic_total)"
