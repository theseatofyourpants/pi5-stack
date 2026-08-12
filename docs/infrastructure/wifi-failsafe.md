---
title: WiFi Failsafe
tags: [infra, networking, failsafe, captive]
service: wifi-failsafe.service
location: ~/wifi-failsafe/
updated: 2026-08-12
---

# WiFi Failsafe

Part of [[Architecture-Overview]]. Keeps the Pi reachable if it loses Wi-Fi: if
`wlan0` has no connectivity, it stands up its own AP + captive portal so you can
pick a new network from a phone — no monitor/keyboard needed.

## What it does
`~/wifi-failsafe/wifi-failsafe.py` (systemd `wifi-failsafe.service`, runs as root):
1. Every 15s checks `wlan0` connectivity.
2. After 45s disconnected → activates an AP on `wlan0` (SSID `Pi5-Setup-XXXX`,
   subnet `10.42.0.x`) + a Flask captive portal.
3. Portal scans/lists networks and lets you connect to a new one.
4. On success the AP tears down; on failure it restores and shows the error.

> [!warning] The AP profile is explicitly pinned, not `nmcli device wifi hotspot`
> `activate_ap()` builds an explicit NM profile pinned to **2.4 GHz / channel 6 /
> WPA2-PSK / PMF-disabled**. The `wifi hotspot` shortcut leaves band/channel on
> auto, so the Pi's `brcmfmac` radio would start the AP on whatever band it was
> last a *client* on — often a 5 GHz DFS channel it can't run in AP mode, leaving
> clients unable to associate (phone "incorrect password", laptop timeout).

## Config
- `CHECK_INTERVAL=15`, `FALLBACK_TIMEOUT=45`, `PORTAL_PORT=80`, `AP_IFACE=wlan0`,
  `AP_CON_NAME=wifi-failsafe-hotspot`. State in `~/wifi-failsafe/.state.json`.

## Captive-portal detection needs a DNS hijack
The AP runs on **NetworkManager shared mode**, whose dnsmasq reads
`/etc/NetworkManager/dnsmasq-shared.d/`. Phones detect a captive portal by probing
`captive.apple.com` (iOS), `connectivitycheck.gstatic.com` (Android), etc.; the OS
only pops the login sheet when that probe gets an HTTP redirect. The failsafe AP
has **no upstream internet**, so unless those domains are resolved *locally* to the
portal, the probe is forwarded upstream, times out, and no sheet appears — the AP
joins but looks "dead" (the symptom seen while travelling, Aug 2026).

Fix: `install.sh` drops `dnsmasq-shared.d/captive-failsafe.conf` (11
`address=/<probe-domain>/10.42.0.1` lines) into NM's dir and reloads NM. The list
is kept in sync with `CAPTIVE_HOSTS` in `wifi-failsafe.py` (the Flask 302 targets).
This mirrors the [[Autonomous-AP-Testbed]] consent portal's own hijack pattern —
the difference is the testbed runs *its own* dnsmasq, the failsafe piggybacks on
NM's shared-mode one.
> [!note] Hardened 2026-08-12
> Added the DNS hijack + expanded `CAPTIVE_HOSTS` (Android/Firefox/Debian/extra MS
> probes). Applies on next AP activation; `sudo bash ~/wifi-failsafe/install.sh` to
> deploy without a full rebuild. Baked into the rebuild via `layers/40-failsafe.sh`
> → `install.sh`.

## Coexistence with the [[Autonomous-AP-Testbed]]
Different radio (`wlan0` vs `wlan1`), subnet (`10.42.0` vs `10.66.66`), and iptables
scope. The only shared resource is TCP :80.
> [!note] Hardened 2026-07-29
> The failsafe portal now binds **`10.42.0.1:80`** (was `0.0.0.0:80`) so it can't
> collide with the testbed's `10.66.66.1:80` portal when the dongle is plugged in.
> Change takes effect on `sudo systemctl restart wifi-failsafe`.

## Reboot
systemd-enabled — survives reboot (see [[Reboot-Runbook]]). It's the template the
testbed's own udev/systemd bring-up was modelled on.
