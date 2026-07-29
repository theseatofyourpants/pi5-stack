#!/usr/bin/env bash
# teardown-net.sh — reverse bringup-net.sh. Run as root by ap-testbed-net.service
# (ExecStop) when the target stops (dongle unplugged or manual stop). Removes ONLY
# the testbed's own rules/addresses so nothing lingers to affect Mythic/Docker/etc.
# Idempotent and never fails the stop (always exit 0).
set -uo pipefail
RUN=/run/ap-testbed
IFACE="$(cat "$RUN/iface" 2>/dev/null || true)"
UPLINK="$(cat "$RUN/uplink" 2>/dev/null || true)"
SUBNET="$(cat "$RUN/subnet" 2>/dev/null || echo 10.66.66)"
log(){ echo "[teardown] $*"; }

# Remove the interface-scoped filter rules.
if [ -n "$IFACE" ]; then
  iptables -D INPUT  -i "$IFACE" -j APTESTBED 2>/dev/null || true
  iptables -D FORWARD -i "$IFACE" -o "${UPLINK:-none}" -p tcp -j REJECT --reject-with tcp-reset 2>/dev/null || true
  iptables -D FORWARD -i "$IFACE" -o "${UPLINK:-none}" -j DROP 2>/dev/null || true
  iptables -D FORWARD -i "$IFACE" -o "$IFACE" -j DROP 2>/dev/null || true
  iptables -D FORWARD -i "${UPLINK:-none}" -o "$IFACE" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -i "$IFACE" -o "${UPLINK:-none}" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
  while iptables -t nat -D PREROUTING -i "$IFACE" -p tcp --dport 80 -j REDIRECT --to-ports 8081 2>/dev/null; do :; done
  # egress chain (if EGRESS was on)
  iptables -D FORWARD -i "$IFACE" -j APT_EGRESS 2>/dev/null || true
  iptables -D FORWARD -i "${UPLINK:-none}" -o "$IFACE" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
fi
iptables -F APT_EGRESS 2>/dev/null || true
iptables -X APT_EGRESS 2>/dev/null || true

# Drop the APTESTBED chain itself.
iptables -F APTESTBED 2>/dev/null || true
iptables -X APTESTBED 2>/dev/null || true
# Remove any masquerade we may have added (EGRESS=1 path).
iptables -t nat -D POSTROUTING -s "${SUBNET}.0/24" -o "${UPLINK:-none}" -j MASQUERADE 2>/dev/null || true

# Release the IP and hand the iface back to NM (only if it's still present).
if [ -n "$IFACE" ] && [ -e "/sys/class/net/$IFACE" ]; then
  ip addr flush dev "$IFACE" 2>/dev/null || true
  command -v nmcli >/dev/null 2>&1 && nmcli device set "$IFACE" managed yes 2>/dev/null || true
fi

rm -f "$RUN"/hostapd.conf "$RUN"/dnsmasq.conf "$RUN"/iface "$RUN"/uplink "$RUN"/subnet "$RUN"/dnsmasq.leases 2>/dev/null || true
log "torn down (iface=${IFACE:-none}) — wlan0/failsafe untouched"
exit 0
