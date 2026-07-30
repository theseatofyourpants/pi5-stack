#!/usr/bin/env bash
# hotpot-ctl.sh — lifecycle for the hot-pot deception stack. Run as root by
# ap-testbed-hotpot.service (and by the admin toggle via scoped sudo). Idempotent.
#
#   start  — if deception is enabled AND the AP is up: seed tokens (once), bring
#            the Docker stack up, and apply the container-egress firewall invariant.
#   stop   — tear the firewall + stack down.
#   status — compose ps + firewall state.
#
# The firewall invariant (the safety property): hot-pot containers may ANSWER
# probers but may NEVER initiate outbound — no internet, no LAN, no exfil, no
# attacker-URL fetch. This is what keeps the deception layer from being a pivot.
set -uo pipefail

BASE=/home/tsoyp/ap-testbed
HOTPOT="$BASE/hotpot"
COMPOSE="$HOTPOT/docker-compose.yml"
AP_IP=10.66.66.1
NET=172.31.66.0/24           # hot-pot bridge subnet (docker-compose.yml)
LOGS="$BASE/logs"
IFACE=wlan1                  # AP interface the bait lives on
# Dedicated Suricata instance for the hot-pot: its own pidfile + log dir so it
# never collides with a host-wide Suricata. The dashboard reads this eve.json.
SURI_PID=/var/run/suricata/suricata-hotpot.pid
SURI_LOG=/var/log/suricata/hotpot

log() { echo "[hotpot-ctl] $*"; }

apply_egress_block() {
  # Ensure DOCKER-USER exists (it does whenever docker is running).
  iptables -L DOCKER-USER -n >/dev/null 2>&1 || { log "DOCKER-USER absent (docker down?) — skipping fw"; return 0; }
  # idempotent: clear our prior rules, then reinstall in the right order.
  iptables -D DOCKER-USER -s "$NET" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null || true
  iptables -D DOCKER-USER -s "$NET" -j DROP 2>/dev/null || true
  iptables -I DOCKER-USER -s "$NET" -j DROP                                             # (lands below the RETURN)
  iptables -I DOCKER-USER -s "$NET" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
  log "egress-block applied: $NET may reply to probers, never initiate outbound"
}

remove_egress_block() {
  iptables -D DOCKER-USER -s "$NET" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null || true
  iptables -D DOCKER-USER -s "$NET" -j DROP 2>/dev/null || true
  log "egress-block removed"
}

compose() { docker compose --project-directory "$HOTPOT" -f "$COMPOSE" "$@"; }

start_ids() {
  # IDS on the AP interface so prober->bait traffic is alerted on (honeypot = zero
  # legit traffic = ~zero-false-positive). Best-effort: never blocks the bait stack.
  command -v suricata >/dev/null 2>&1 || { log "suricata not installed — skipping hot-pot IDS"; return 0; }
  if [ -f "$SURI_PID" ] && kill -0 "$(cat "$SURI_PID" 2>/dev/null)" 2>/dev/null; then
    log "hot-pot IDS already running (pid $(cat "$SURI_PID"))"; return 0
  fi
  if pgrep -af suricata 2>/dev/null | grep -q -- "-i $IFACE"; then
    log "a suricata is already watching $IFACE — leaving it in place (dashboard reads its eve.json)"; return 0
  fi
  mkdir -p "$SURI_LOG" /var/run/suricata
  log "starting hot-pot IDS: suricata -i $IFACE -> $SURI_LOG/eve.json"
  if ! suricata -c /etc/suricata/suricata.yaml -i "$IFACE" -l "$SURI_LOG" \
        -D --pidfile "$SURI_PID" >/dev/null 2>&1; then
    log "suricata start FAILED — continuing without IDS (check: suricata -c … -i $IFACE)"; return 0
  fi
  for _ in 1 2 3 4 5 6; do [ -f "$SURI_LOG/eve.json" ] && break; sleep 1; done
  # grant the admin console (tsoyp) read now + inherit on log rotation
  setfacl -m u:tsoyp:rx "$SURI_LOG" 2>/dev/null || true
  setfacl -d -m u:tsoyp:r "$SURI_LOG" 2>/dev/null || true
  setfacl -m u:tsoyp:r "$SURI_LOG/eve.json" 2>/dev/null || true
  log "hot-pot IDS up on $IFACE (tsoyp granted read; dashboard Alerts panel will populate)"
}

stop_ids() {
  [ -f "$SURI_PID" ] || return 0
  local p; p="$(cat "$SURI_PID" 2>/dev/null)"
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
    log "stopping hot-pot IDS (pid $p)"
    kill "$p" 2>/dev/null
    for _ in 1 2 3; do kill -0 "$p" 2>/dev/null || break; sleep 1; done
    kill -9 "$p" 2>/dev/null || true
  fi
  rm -f "$SURI_PID"
}

start() {
  if ! python3 "$BASE/lib/store.py" is-deception; then
    log "deception is OFF — not starting the hot-pot (toggle it in the admin console)."; exit 0
  fi
  if ! ip -4 addr show dev wlan1 2>/dev/null | grep -q "$AP_IP"; then
    log "AP IP $AP_IP not present (dongle out / AP down) — will start on next AP bring-up."; exit 0
  fi
  mkdir -p "$LOGS/hotpot" "$LOGS/cowrie"
  chown -R tsoyp:tsoyp "$LOGS/hotpot" "$LOGS/cowrie" 2>/dev/null || true
  if [ ! -s "$BASE/state/hotpot-tokens.json" ]; then
    log "seeding honeytokens (first run)…"
    sudo -u tsoyp python3 "$HOTPOT/seed-tokens.py" || python3 "$HOTPOT/seed-tokens.py" || true
  fi
  # Host sshd usually holds the 0.0.0.0:22 wildcard -> a 10.66.66.1:22 publish
  # would fail to bind. Detect and fall back to 2222 so the stack still comes up.
  if ss -ltn 2>/dev/null | grep -qE '(0\.0\.0\.0|\*|\[::\]):22\b'; then
    export COWRIE_SSH_PORT=2222
    log "host sshd holds :22 — publishing Cowrie SSH on 2222 (free :22 to serve authentic bait; see docs)."
  fi
  log "bringing the deception stack up (build on first run may pull images)…"
  compose up -d --build || { log "compose up FAILED"; exit 1; }
  apply_egress_block
  start_ids
  log "hot-pot UP. bait: 22/23 (cowrie) 445 (smb) 8080 (fake-admin) · collector 8686 — all on $AP_IP only."
}

stop() {
  stop_ids
  remove_egress_block
  log "tearing the deception stack down…"
  compose down 2>/dev/null || true
  log "hot-pot DOWN."
}

status() {
  echo "== deception flag =="; python3 "$BASE/lib/store.py" is-deception && echo "ON" || echo "OFF"
  echo "== compose ps =="; compose ps 2>/dev/null
  echo "== egress-block (DOCKER-USER) =="; iptables -S DOCKER-USER 2>/dev/null | grep "$NET" || echo "(none)"
  echo "== hot-pot IDS =="
  if [ -f "$SURI_PID" ] && kill -0 "$(cat "$SURI_PID" 2>/dev/null)" 2>/dev/null; then
    echo "suricata on $IFACE (pid $(cat "$SURI_PID")) -> $SURI_LOG/eve.json"
  else
    pgrep -af suricata 2>/dev/null | grep -- "-i $IFACE" || echo "(not running)"
  fi
}

case "${1:-}" in
  start)  start ;;
  stop)   stop ;;
  status) status ;;
  *) echo "usage: $0 {start|stop|status}"; exit 2 ;;
esac
