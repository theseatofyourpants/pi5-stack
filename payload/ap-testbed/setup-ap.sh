#!/usr/bin/env bash
# setup-ap.sh — stand up the isolated consent-AP testbed.
#
# SAFETY MODEL (read before running):
#   * This script REFUSES to run against the interface that carries your
#     default route (your uplink). On this Pi that is wlan0. Point it at a
#     DEDICATED AP interface (a USB adapter = wlan1, or wlan0 only AFTER you
#     have moved the uplink to eth0).
#   * It never rewrites your uplink's NetworkManager profile.
#   * The AP subnet is a walled garden: clients cannot reach your LAN, and by
#     default cannot reach the internet either (see isolation.sh).
#
# Nothing offensive lives here. This is Layer 1: a safe, isolated AP plus a
# captive CONSENT portal. The watcher (Layer 2) only LOGS until you explicitly
# arm it. The attack trigger (Layer 3) is off until ARM_OFFENSIVE=1 is set.
#
# Usage:  sudo AP_IFACE=wlan1 bash setup-ap.sh
set -euo pipefail

AP_IFACE="${AP_IFACE:-}"
AP_SSID="${AP_SSID:-Open Security Test}"
AP_SUBNET="${AP_SUBNET:-10.66.66}"        # /24, Pi is .1
AP_CHANNEL="${AP_CHANNEL:-36}"            # 5GHz non-DFS (36/40/44/48); use <=11 for 2.4GHz
AP_COUNTRY="${AP_COUNTRY:-US}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# hw_mode follows the band: ch<=14 => 2.4GHz (g), else 5GHz (a)
if [ "$AP_CHANNEL" -le 14 ]; then AP_HWMODE="g"; else AP_HWMODE="a"; fi

die(){ echo "FATAL: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
[ -n "$AP_IFACE" ]    || die "set AP_IFACE=<dedicated interface>, e.g. AP_IFACE=wlan1"

# --- GUARD 1: never touch the uplink interface -------------------------------
UPLINK_IFACE="$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')"
if [ "$AP_IFACE" = "$UPLINK_IFACE" ]; then
  die "AP_IFACE ($AP_IFACE) is your UPLINK (default route). Refusing.
     Fix: attach a USB wifi adapter and use it, OR move uplink to eth0 first."
fi

# --- GUARD 2: interface must actually exist ----------------------------------
[ -e "/sys/class/net/$AP_IFACE" ] || die "interface $AP_IFACE does not exist. Plug in the USB adapter."

# --- GUARD 3: interface must support AP mode ---------------------------------
PHY="$(cat /sys/class/net/$AP_IFACE/phy80211/name 2>/dev/null || true)"
if [ -n "$PHY" ] && ! iw phy "$PHY" info 2>/dev/null | grep -qiE '^\s+\* AP$'; then
  die "$AP_IFACE ($PHY) does not advertise AP mode."
fi

echo "[*] Uplink is '$UPLINK_IFACE' (protected). Building AP on '$AP_IFACE'."

# --- ensure hostapd present --------------------------------------------------
if ! command -v hostapd >/dev/null 2>&1; then
  echo "[*] installing hostapd..."
  apt-get update -qq && apt-get install -y hostapd
fi

# --- take AP_IFACE away from NetworkManager (uplink profile untouched) -------
if command -v nmcli >/dev/null 2>&1; then
  echo "[*] setting $AP_IFACE unmanaged in NetworkManager"
  nmcli device set "$AP_IFACE" managed no || true
fi

# --- static IP on the AP interface -------------------------------------------
ip addr flush dev "$AP_IFACE" || true
ip link set "$AP_IFACE" up
ip addr add "${AP_SUBNET}.1/24" dev "$AP_IFACE"

# --- render configs from templates -------------------------------------------
sed -e "s/__IFACE__/$AP_IFACE/g" -e "s/__SSID__/$AP_SSID/g" -e "s/__CHANNEL__/$AP_CHANNEL/g" \
    -e "s/__HWMODE__/$AP_HWMODE/g" -e "s/__COUNTRY__/$AP_COUNTRY/g" \
    "$HERE/conf/hostapd.conf.template" > /tmp/hostapd-testbed.conf
sed -e "s/__IFACE__/$AP_IFACE/g" -e "s/__SUBNET__/$AP_SUBNET/g" \
    "$HERE/conf/dnsmasq-ap.conf.template" > /tmp/dnsmasq-testbed.conf

# --- firewall isolation (walled garden) --------------------------------------
AP_IFACE="$AP_IFACE" AP_SUBNET="$AP_SUBNET" UPLINK_IFACE="$UPLINK_IFACE" \
  bash "$HERE/isolation.sh"

# --- launch dnsmasq (DHCP + captive DNS) and hostapd -------------------------
pkill -f "dnsmasq-testbed.conf" 2>/dev/null || true
dnsmasq -C /tmp/dnsmasq-testbed.conf
echo "[*] dnsmasq up (DHCP ${AP_SUBNET}.50-150, captive DNS -> ${AP_SUBNET}.1)"

echo "[*] starting hostapd (Ctrl-C to stop; run under systemd for persistence)"
echo "    SSID='$AP_SSID' channel=$AP_CHANNEL  portal=http://${AP_SUBNET}.1:8081"
echo "    Start the consent portal in another shell:  python3 $HERE/consent-portal/portal.py"
exec hostapd /tmp/hostapd-testbed.conf
