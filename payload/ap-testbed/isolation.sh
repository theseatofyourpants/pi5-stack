#!/usr/bin/env bash
# isolation.sh — walled-garden firewall for the consent-testbed AP.
# Called by setup-ap.sh with AP_IFACE, AP_SUBNET, UPLINK_IFACE in env.
#
# Guarantees:
#   1. AP clients CANNOT reach your LAN or the Pi's uplink subnet.
#   2. AP clients CANNOT reach the internet by default (EGRESS=0).
#   3. AP clients CAN reach ONLY the Pi's portal (8081), DHCP, and captive DNS.
#   4. The tested device is reachable FROM the Pi (that's the point) but is
#      boxed off from everything else.
set -euo pipefail

AP_IFACE="${AP_IFACE:?}"; AP_SUBNET="${AP_SUBNET:?}"; UPLINK_IFACE="${UPLINK_IFACE:?}"
EGRESS="${EGRESS:-0}"          # 0 = no internet for clients (default). 1 = NAT egress.
PORTAL_PORT="${PORTAL_PORT:-80}"     # portal binds :80 directly (see below)
CIDR="${AP_SUBNET}.0/24"
CHAIN="APTESTBED"

# Fresh chain
iptables -N "$CHAIN" 2>/dev/null || iptables -F "$CHAIN"

# --- INPUT: what AP clients may send to the Pi itself ------------------------
iptables -D INPUT -i "$AP_IFACE" -j "$CHAIN" 2>/dev/null || true
iptables -A INPUT -i "$AP_IFACE" -j "$CHAIN"
iptables -A "$CHAIN" -p udp --dport 67 -j ACCEPT                       # DHCP
iptables -A "$CHAIN" -p udp --dport 53 -j ACCEPT                       # captive DNS
iptables -A "$CHAIN" -p tcp --dport 53 -j ACCEPT
# The portal binds :80 DIRECTLY (evilportal-style). We do NOT use a nat REDIRECT:
# on this Docker host, REDIRECT/DNAT in nat PREROUTING silently fails to match
# AP-client traffic (Docker/conntrack interaction), so :80 packets were dropped.
# Owning :80 sidesteps NAT entirely and is the known-good captive-portal pattern.
iptables -A "$CHAIN" -p tcp --dport 80 -j ACCEPT                       # consent portal (:80)
iptables -A "$CHAIN" -p tcp --dport 443 -j ACCEPT                      # consent portal HTTPS (captive-API, RFC 8910)
iptables -A "$CHAIN" -p tcp --dport "$PORTAL_PORT" -j ACCEPT           # portal alt-port if used
iptables -A "$CHAIN" -p icmp -j ACCEPT
# DNS-over-TLS (Private DNS, port 853): REJECT with a RST rather than blackhole, so
# a phone on Private DNS=Automatic fails DoT INSTANTLY and falls back to plaintext
# :53 (which we hijack). Silently dropping 853 stalls DNS — the #1 cause of "the
# portal won't show" on modern Android/Samsung.
iptables -A "$CHAIN" -p tcp --dport 853 -j REJECT --reject-with tcp-reset
iptables -A "$CHAIN" -p udp --dport 853 -j REJECT --reject-with icmp-port-unreachable
iptables -A "$CHAIN" -j DROP                                            # nothing else to the Pi

# Clean up any stale REDIRECT rule from earlier attempts (no-op if absent).
while iptables -t nat -D PREROUTING -i "$AP_IFACE" -p tcp --dport 80 -j REDIRECT --to-ports "$PORTAL_PORT" 2>/dev/null; do :; done

# --- FORWARD: block cross-subnet leakage -------------------------------------
# Clients must NOT be forwarded toward the uplink/LAN...
iptables -D FORWARD -i "$AP_IFACE" -o "$UPLINK_IFACE" -j DROP 2>/dev/null || true
if [ "$EGRESS" = "1" ]; then
  echo "[!] EGRESS=1 — HYBRID per-MAC egress (only authorized MACs reach the internet)."
  # Ensure IP forwarding (Docker usually enables this globally already).
  sysctl -qw net.ipv4.ip_forward=1 2>/dev/null || echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
  # APT_EGRESS: first DROP every private destination (home LAN, tailscale CGNAT,
  # docker, link-local) so NO client — even authorized — can reach your networks.
  # Per-MAC ACCEPT rules are appended AFTER these by apt-authorize.sh as devices
  # become authorized (allowlist at bring-up, consent at runtime). Unauthorized
  # traffic falls through the chain and hits the catch-all DROP in FORWARD below.
  iptables -N APT_EGRESS 2>/dev/null || iptables -F APT_EGRESS
  for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16; do
    iptables -A APT_EGRESS -d "$net" -j DROP
  done
  iptables -D FORWARD -i "$AP_IFACE" -j APT_EGRESS 2>/dev/null || true
  iptables -A FORWARD -i "$AP_IFACE" -j APT_EGRESS
  # catch-all for unauthorized devices reaching the INTERNET: REJECT TCP with a RST
  # (so OS captive HTTPS probes fail INSTANTLY and the device falls back to the HTTP
  # probe we hijack -> the sign-in sheet pops fast instead of hanging on a timeout),
  # and drop everything else. (LAN/private destinations were already silently dropped
  # inside APT_EGRESS above.)
  iptables -A FORWARD -i "$AP_IFACE" -o "$UPLINK_IFACE" -p tcp -j REJECT --reject-with tcp-reset
  iptables -A FORWARD -i "$AP_IFACE" -o "$UPLINK_IFACE" -j DROP
  iptables -A FORWARD -i "$UPLINK_IFACE" -o "$AP_IFACE" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -t nat -C POSTROUTING -s "$CIDR" -o "$UPLINK_IFACE" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s "$CIDR" -o "$UPLINK_IFACE" -j MASQUERADE
else
  iptables -A FORWARD -i "$AP_IFACE" -o "$UPLINK_IFACE" -j DROP
fi
# ...and never bridge between AP clients via forward either.
iptables -A FORWARD -i "$AP_IFACE" -o "$AP_IFACE" -j DROP

# --- cap TX power to shrink the RF footprint (best-effort) -------------------
iw dev "$AP_IFACE" set txpower fixed 800 2>/dev/null || true   # 8 dBm

echo "[*] isolation applied on $AP_IFACE ($CIDR). EGRESS=$EGRESS. LAN/uplink blocked."
