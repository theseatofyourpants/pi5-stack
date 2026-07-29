#!/usr/bin/env bash
# install-testbed.sh — install the dongle-triggered systemd + udev machinery.
# Run with sudo. Idempotent. Also stops/cleans any MANUAL testbed left running.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo: ! sudo bash ~/ap-testbed/install-testbed.sh"; exit 1; }
HERE=/home/tsoyp/ap-testbed

echo "[*] Stopping any MANUAL testbed processes (from earlier hand bring-up)..."
pkill -f "consent-portal/portal.py"        2>/dev/null || true
pkill -f "dnsmasq-testbed.conf"            2>/dev/null || true
pkill -f "/run/ap-testbed/dnsmasq.conf"    2>/dev/null || true
pkill -f "hostapd-testbed.conf"            2>/dev/null || true
pkill -f "hostapd /run/ap-testbed"         2>/dev/null || true

echo "[*] Flushing any hand-applied testbed iptables (APTESTBED chain, stray REDIRECT)..."
for IF in wlan1 wlan2 wlan3; do iptables -D INPUT -i "$IF" -j APTESTBED 2>/dev/null || true; done
iptables -F APTESTBED 2>/dev/null || true
iptables -X APTESTBED 2>/dev/null || true
for IF in wlan1 wlan2 wlan3; do
  while iptables -t nat -D PREROUTING -i "$IF" -p tcp --dport 80 -j REDIRECT --to-ports 8081 2>/dev/null; do :; done
done

echo "[*] Fixing ownership (portal + admin run as tsoyp)..."
mkdir -p "$HERE/logs" "$HERE/state/scans"
chown -R tsoyp:tsoyp "$HERE/logs" "$HERE/state"

echo "[*] Ensuring admin console password..."
if [ ! -s "$HERE/state/admin.pass" ]; then
  umask 077
  openssl rand -base64 18 > "$HERE/state/admin.pass"
  chown tsoyp:tsoyp "$HERE/state/admin.pass"; chmod 600 "$HERE/state/admin.pass"
  NEWPASS=1
fi

echo "[*] Installing systemd units..."
install -m0644 "$HERE"/systemd/ap-testbed.target            /etc/systemd/system/
install -m0644 "$HERE"/systemd/ap-testbed-net.service       /etc/systemd/system/
install -m0644 "$HERE"/systemd/ap-testbed-hostapd.service   /etc/systemd/system/
install -m0644 "$HERE"/systemd/ap-testbed-dnsmasq.service   /etc/systemd/system/
install -m0644 "$HERE"/systemd/ap-testbed-portal.service    /etc/systemd/system/
install -m0644 "$HERE"/systemd/ap-testbed-admin.service     /etc/systemd/system/

echo "[*] Installing udev rule..."
install -m0644 "$HERE"/udev/99-ap-testbed.rules /etc/udev/rules.d/

echo "[*] Installing per-MAC egress helper (root-owned, outside tsoyp's home)..."
install -m0755 -o root -g root "$HERE"/apt-authorize.sh /usr/local/sbin/apt-testbed-authorize

echo "[*] Installing scoped sudoers rule (validated)..."
if visudo -cf "$HERE/sudoers.d-ap-testbed" >/dev/null 2>&1; then
  install -m0440 -o root -g root "$HERE/sudoers.d-ap-testbed" /etc/sudoers.d/ap-testbed
else
  echo "    !! sudoers file failed validation — NOT installed (SSID-apply will need manual restart)"
fi

echo "[*] Reloading systemd + udev..."
systemctl daemon-reload
udevadm control --reload

echo "[*] Enabling + (re)starting the always-on admin console..."
systemctl enable ap-testbed-admin.service
systemctl restart ap-testbed-admin.service

WLAN0_IP="$(ip -brief addr show wlan0 2>/dev/null | awk '{print $3}' | cut -d/ -f1)"
TS_IP="$(ip -brief addr show tailscale0 2>/dev/null | awk '{print $3}' | cut -d/ -f1)"

echo
echo "=================================================================="
echo " Installed. The dongle is the arming switch:"
echo "   plug in  -> ap-testbed.target starts (ARMED)"
echo "   unplug   -> stops + full teardown (wlan0/failsafe untouched)"
echo
echo " Admin console (always-on):"
echo "   http://${WLAN0_IP:-<wlan0-ip>}:8787   (LAN)"
[ -n "$TS_IP" ] && echo "   http://${TS_IP}:8787   (tailscale)"
echo "   login: admin  /  password:"
if [ "${NEWPASS:-0}" = "1" ]; then echo "     $(cat "$HERE/state/admin.pass")"; else echo "     (unchanged — see $HERE/state/admin.pass)"; fi
echo
echo " Test the AP bring-up now (dongle already in):"
echo "   sudo systemctl start ap-testbed.target"
echo "   journalctl -fu ap-testbed-net -u ap-testbed-hostapd -u ap-testbed-dnsmasq -u ap-testbed-portal"
echo " Then test the switch: unplug the dongle (stops), replug (starts)."
echo "=================================================================="
