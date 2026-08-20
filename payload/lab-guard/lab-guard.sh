#!/usr/bin/env bash
# lab-guard — confine the lab control plane to loopback and the tailnet.
#
# WHY: the offensive backends bind 0.0.0.0 and cannot be told otherwise.
# kali_server.py hardcodes app.run(host="0.0.0.0") and takes no bind argument, and
# both it and hexstrike are third-party clones that layer 20 re-clones on rebuild,
# so a local patch would not survive. Meanwhile both answer HTTP 200 with NO
# AUTHENTICATION and expose arbitrary command execution. On a flat home LAN shared
# with a NAS, laptops and phones, anything that joins the network can drive the
# entire offensive toolchain. Filtering is the only durable fix available.
#
# WHAT: for each guarded port, allow loopback and the tailnet, drop everything else.
#
#   :5000  MCP-Kali-Server   unauthenticated RCE API
#   :8899  hexstrike         unauthenticated tool-orchestration API
#   :31337 sliver-server     operator listener (mTLS, but no reason to face the LAN)
#   :7443  Mythic nginx      C2 admin UI (login, same reasoning)
#
# Deliberately NOT guarded: 22 (ssh, how you get in) and 8787 (AP admin console,
# which authenticates and is meant to be reachable while managing the AP).
#
# Docker-published ports need separate handling: Docker DNATs in PREROUTING and the
# traffic is FORWARDed, never traversing INPUT, so an INPUT rule would silently do
# nothing. Those are filtered in DOCKER-USER against the LAN interface only, which
# leaves container egress and the AP bridge untouched.
#
# Idempotent. Run as root. `lab-guard remove` reverts cleanly.
set -euo pipefail

CHAIN="LABGUARD"
HOST_PORTS="${LAB_GUARD_HOST_PORTS:-5000,8899,31337}"
DOCKER_PORTS="${LAB_GUARD_DOCKER_PORTS:-7443}"
TS_IF="${LAB_GUARD_TS_IF:-tailscale0}"
LAN_IF="${LAB_GUARD_LAN_IF:-$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')}"
DRY=0

usage(){ sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; echo; echo "usage: lab-guard {apply|remove|status} [--dry-run]"; exit 0; }
ACTION="${1:-status}"; shift || true
for a in "$@"; do [ "$a" = "--dry-run" ] && DRY=1; done
case "$ACTION" in -h|--help) usage;; esac
[ "$ACTION" = status ] || [ "$DRY" -eq 1 ] || [ "$(id -u)" -eq 0 ] || { echo "run as root: sudo lab-guard $ACTION" >&2; exit 1; }

run(){ if [ "$DRY" -eq 1 ]; then echo "  + $*"; else "$@"; fi; }
# Deletes that are expected to fail when the rule is not there yet.
try(){ if [ "$DRY" -eq 1 ]; then :; else "$@" 2>/dev/null || true; fi; }

for IPT in iptables ip6tables; do
  command -v "$IPT" >/dev/null 2>&1 || continue

  case "$ACTION" in
    apply)
      echo "[$IPT] guarding $HOST_PORTS (host) + $DOCKER_PORTS (docker) — allow lo + $TS_IF, LAN=$LAN_IF"
      # Chain: create if absent, then flush so re-running never stacks duplicates.
      "$IPT" -n -L "$CHAIN" >/dev/null 2>&1 || try "$IPT" -N "$CHAIN"
      [ "$DRY" -eq 1 ] && echo "  + $IPT -N $CHAIN (if absent); flush"
      try "$IPT" -F "$CHAIN"
      run "$IPT" -A "$CHAIN" -i lo -j ACCEPT
      run "$IPT" -A "$CHAIN" -i "$TS_IF" -j ACCEPT
      run "$IPT" -A "$CHAIN" -j DROP

      # INPUT: host-process ports. Remove any previous jump first so this is idempotent.
      try "$IPT" -D INPUT -p tcp -m multiport --dports "$HOST_PORTS" -j "$CHAIN"
      run "$IPT" -I INPUT 1 -p tcp -m multiport --dports "$HOST_PORTS" -j "$CHAIN"

      # DOCKER-USER: published container ports. Interface-scoped rather than routed
      # through the chain — a dport match in the FORWARD path would also catch
      # container EGRESS to that port number on the internet.
      if [ -n "$LAN_IF" ] && "$IPT" -n -L DOCKER-USER >/dev/null 2>&1; then
        try "$IPT" -D DOCKER-USER -i "$LAN_IF" -p tcp -m multiport --dports "$DOCKER_PORTS" -j DROP
        run "$IPT" -I DOCKER-USER 1 -i "$LAN_IF" -p tcp -m multiport --dports "$DOCKER_PORTS" -j DROP
      elif [ "$(id -u)" -ne 0 ]; then
        # Listing DOCKER-USER needs root, so a rootless --dry-run cannot see it.
        # Say so rather than reporting a chain that is almost certainly present.
        echo "  ? DOCKER-USER not inspectable without root — will be handled on the real run"
      else
        echo "  (no DOCKER-USER chain or no LAN interface — docker ports NOT guarded)"
      fi
      ;;
    remove)
      echo "[$IPT] removing guard"
      try "$IPT" -D INPUT -p tcp -m multiport --dports "$HOST_PORTS" -j "$CHAIN"
      [ -n "$LAN_IF" ] && try "$IPT" -D DOCKER-USER -i "$LAN_IF" -p tcp -m multiport --dports "$DOCKER_PORTS" -j DROP
      try "$IPT" -F "$CHAIN"
      try "$IPT" -X "$CHAIN"
      ;;
    status)
      if "$IPT" -n -L "$CHAIN" >/dev/null 2>&1; then
        echo "[$IPT] $CHAIN active:"
        "$IPT" -n -L "$CHAIN" -v 2>/dev/null | sed 's/^/    /'
      else
        echo "[$IPT] $CHAIN NOT INSTALLED — guarded ports are reachable from the LAN"
      fi
      ;;
    *) usage;;
  esac
done
exit 0
