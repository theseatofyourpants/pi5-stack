#!/usr/bin/env bash
# bringup-net.sh — configure the dongle AP interface + walled-garden firewall.
# Run as root by ap-testbed-net.service (ExecStart). Detects the MT7612U dongle
# by driver, REFUSES the uplink interface, renders hostapd/dnsmasq configs into
# /run/ap-testbed, and applies isolation. hostapd/dnsmasq/portal are separate
# units started by ap-testbed.target after this succeeds.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
STACK_USER="$(stat -c %U "$HERE")"
RUN=/run/ap-testbed

CFG="$HERE/state/config.json"
DONGLE_DRIVER="${DONGLE_DRIVER:-mt76x2u}"
AP_SUBNET="${AP_SUBNET:-10.66.66}"

# Read SSID/channel/country from the config store the admin portal edits.
# Falls back to defaults / env if the file is missing.
EGRESS="${EGRESS:-0}"
if [ -f "$CFG" ]; then
  AP_SSID="${AP_SSID:-$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("ssid",""))' "$CFG" 2>/dev/null)}"
  AP_CHANNEL="${AP_CHANNEL:-$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("channel",""))' "$CFG" 2>/dev/null)}"
  AP_COUNTRY="${AP_COUNTRY:-$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("country",""))' "$CFG" 2>/dev/null)}"
  EGRESS="$(python3 -c 'import json,sys;print(1 if json.load(open(sys.argv[1])).get("egress") else 0)' "$CFG" 2>/dev/null || echo 0)"
fi
AP_SSID="${AP_SSID:-Open Security Test}"
AP_CHANNEL="${AP_CHANNEL:-36}"          # 5GHz non-DFS
AP_COUNTRY="${AP_COUNTRY:-US}"

# Sanitize SSID to a safe 802.11 charset (defence-in-depth vs the sed render):
# letters, digits, space, dash, underscore, dot; max 32 bytes.
AP_SSID="$(printf '%s' "$AP_SSID" | tr -cd 'A-Za-z0-9 ._-' | cut -c1-32)"
[ -n "$AP_SSID" ] || AP_SSID="Open Security Test"

if [ "$AP_CHANNEL" -le 14 ]; then AP_HWMODE=g; else AP_HWMODE=a; fi

log(){ echo "[bringup] $*"; }
die(){ echo "[bringup] FATAL: $*" >&2; exit 1; }

# 1. Detect the dongle interface (poll up to ~15s: USB 'add' can precede the
#    net device being registered).
AP_IFACE=""
for _ in $(seq 1 30); do
  for d in /sys/class/net/*/device/driver; do
    [ -e "$d" ] || continue
    if [ "$(basename "$(readlink -f "$d")")" = "$DONGLE_DRIVER" ]; then
      AP_IFACE="$(echo "$d" | cut -d/ -f5)"; break
    fi
  done
  [ -n "$AP_IFACE" ] && break
  sleep 0.5
done
[ -n "$AP_IFACE" ] || die "dongle interface (driver=$DONGLE_DRIVER) not found"

# 2. GUARD: never touch the uplink (default-route) interface.
UPLINK="$(ip route show default | awk '/default/{print $5; exit}')"
[ "$AP_IFACE" != "$UPLINK" ] || die "detected iface $AP_IFACE IS the uplink — refusing"
log "AP iface=$AP_IFACE  uplink=${UPLINK:-none}  ssid=$AP_SSID  ch=$AP_CHANNEL"

mkdir -p "$RUN"
echo "$AP_IFACE"  > "$RUN/iface"
echo "${UPLINK:-}" > "$RUN/uplink"
echo "$AP_SUBNET" > "$RUN/subnet"

# 3. Take the iface away from NetworkManager and give it a static AP IP.
command -v nmcli >/dev/null 2>&1 && nmcli device set "$AP_IFACE" managed no 2>/dev/null || true
ip addr flush dev "$AP_IFACE" 2>/dev/null || true
ip link set "$AP_IFACE" up
ip addr add "${AP_SUBNET}.1/24" dev "$AP_IFACE"

# 4. Render hostapd + dnsmasq configs into the runtime dir.
sed -e "s/__IFACE__/$AP_IFACE/g" -e "s/__SSID__/$AP_SSID/g" -e "s/__CHANNEL__/$AP_CHANNEL/g" \
    -e "s/__HWMODE__/$AP_HWMODE/g" -e "s/__COUNTRY__/$AP_COUNTRY/g" \
    "$HERE/conf/hostapd.conf.template" > "$RUN/hostapd.conf"
sed -e "s/__IFACE__/$AP_IFACE/g" -e "s/__SUBNET__/$AP_SUBNET/g" -e "s|__AP_DIR__|$HERE|g" \
    "$HERE/conf/dnsmasq-ap.conf.template" > "$RUN/dnsmasq.conf"

# 5. Walled-garden firewall (scoped to $AP_IFACE only — never affects wlan0).
AP_IFACE="$AP_IFACE" AP_SUBNET="$AP_SUBNET" UPLINK_IFACE="${UPLINK:-lo}" PORTAL_PORT=80 \
  EGRESS="$EGRESS" bash "$HERE/isolation.sh"

# Fresh session: reset the this-session consent list (portal appends to it), and
# make it writable by the portal user (bringup runs as root).
SESSION_AUTH="$HERE/state/session-auth"
: > "$SESSION_AUTH" 2>/dev/null || true
chown "$STACK_USER:$STACK_USER" "$SESSION_AUTH" 2>/dev/null || true

# Reconcile orphaned scans: a restart kills any backgrounded scan mid-run, leaving
# its record stuck at 'running'. Mark those whose process is gone as 'interrupted'.
reaped="$(python3 "$HERE/lib/store.py" reap-stale 2>/dev/null || echo 0)"
[ "${reaped:-0}" != "0" ] && log "reaped $reaped orphaned running scan(s)"

# In hybrid egress mode, pre-authorize every allowlisted (persistently trusted)
# device so it gets internet the moment it joins and stays connected for its scan.
if [ "$EGRESS" = "1" ]; then
  AUTH_BIN=/usr/local/sbin/apt-testbed-authorize
  [ -x "$AUTH_BIN" ] || AUTH_BIN="$HERE/apt-authorize.sh"   # fallback for manual/dev
  n=0
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    bash "$AUTH_BIN" add "$m" >/dev/null 2>&1 && n=$((n + 1)) || true
  done < <(python3 "$HERE/lib/store.py" list-allowed-macs 2>/dev/null)
  log "pre-authorized $n allowlist device(s) for egress"
fi

log "network ready on $AP_IFACE (${AP_SUBNET}.1)  egress=$EGRESS"
