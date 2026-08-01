---
title: WiFi Failsafe
tags: [infra, networking, failsafe, captive]
service: wifi-failsafe.service
location: ~/wifi-failsafe/
updated: 2026-07-29
---

# WiFi Failsafe

Part of [[Architecture-Overview]]. Keeps the Pi reachable if it loses Wi-Fi: if
`wlan0` has no connectivity, it stands up its own AP + captive portal so you can
pick a new network from a phone — no monitor/keyboard needed.

## What it does
`~/wifi-failsafe/wifi-failsafe.py` (systemd `wifi-failsafe.service`, runs as root):
1. Every 15s checks `wlan0` connectivity.
2. After 45s disconnected → activates an **NM hotspot** on `wlan0` (SSID `Pi5-Setup-XXXX`,
   subnet `10.42.0.x`) + a Flask captive portal.
3. Portal scans/lists networks and lets you connect to a new one.
4. On success the AP tears down; on failure it restores and shows the error.

## Config
- `CHECK_INTERVAL=15`, `FALLBACK_TIMEOUT=45`, `PORTAL_PORT=80`, `AP_IFACE=wlan0`,
  `AP_CON_NAME=wifi-failsafe-hotspot`. State in `~/wifi-failsafe/.state.json`.

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
