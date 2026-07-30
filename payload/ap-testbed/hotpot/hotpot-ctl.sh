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
  log "hot-pot UP. bait: 22/23 (cowrie) 445 (smb) 8080 (fake-admin) · collector 8686 — all on $AP_IP only."
}

stop() {
  remove_egress_block
  log "tearing the deception stack down…"
  compose down 2>/dev/null || true
  log "hot-pot DOWN."
}

status() {
  echo "== deception flag =="; python3 "$BASE/lib/store.py" is-deception && echo "ON" || echo "OFF"
  echo "== compose ps =="; compose ps 2>/dev/null
  echo "== egress-block (DOCKER-USER) =="; iptables -S DOCKER-USER 2>/dev/null | grep "$NET" || echo "(none)"
}

case "${1:-}" in
  start)  start ;;
  stop)   stop ;;
  status) status ;;
  *) echo "usage: $0 {start|stop|status}"; exit 2 ;;
esac
