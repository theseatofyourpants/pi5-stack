# AP Testbed — isolated consent-gated device-security bench

An autonomous rig: it runs its own Wi-Fi AP; when an **authorized** device joins
and its owner **explicitly consents** via a captive portal, it fires a scoped,
non-destructive security scan of *that one device* and writes a report.

It is deliberately **not** an "attack anyone who connects" machine. The consent
click is the authorization record that keeps this inside the CFAA line and any
conference code of conduct. There is no allow-all mode.

## Hardware reality on this Pi
`wlan0` (onboard) is the **uplink** (TSOYP-Home) and carries the default route.
You have **one radio**. To run the AP you need ONE of:
- **A USB Wi-Fi adapter** (AP-mode capable: mt7612u / rtl8812au / rt5370) →
  AP on `wlan1`, uplink stays on `wlan0`.  ← recommended
- **Move the uplink to Ethernet** (plug `eth0` into the router), freeing `wlan0`
  for the AP.

`setup-ap.sh` **refuses** to run against whichever interface holds the default
route, so it cannot knock you off the network by accident.

## Layers (each independently stoppable)
1. **Isolated AP + captive consent portal** — `setup-ap.sh`, `isolation.sh`,
   `consent-portal/`. Safe: no offense, walled garden, no internet egress by default.
2. **Join logging** — `watcher.sh` (dnsmasq dhcp-script). Records who joined. Log-only.
3. **Scan trigger** — `trigger-scan.sh`, launched by the portal *after* consent.
   **DISARMED** until `ARM_OFFENSIVE=1`. Validate the gate in log-only mode first.

## Bring-up (once you have a dedicated AP interface, e.g. wlan1)
```bash
# 1. AP + isolation + hostapd (foreground)
sudo AP_IFACE=wlan1 AP_SSID=consent-testbed bash ~/ap-testbed/setup-ap.sh

# 2. consent portal (another shell, or install the .service)
python3 ~/ap-testbed/consent-portal/portal.py

# 3. watch it work in log-only mode
tail -f ~/ap-testbed/logs/{joins.log,scans.log}
```
Join with a test device → open any URL → the splash pops → click consent →
`scans.log` records "AUTHORIZED but DISARMED: would scan ...". Only after you
trust the gate do you set `ARM_OFFENSIVE=1` in `ap-testbed-portal.service`.

## Safety controls
| Control | Where |
|---|---|
| Won't touch uplink interface | `setup-ap.sh` GUARD 1 |
| Walled garden (no LAN, no internet by default) | `isolation.sh` |
| Consent required before any scan | `consent-portal/portal.py` |
| Offense disarmed by default | `trigger-scan.sh` `ARM_OFFENSIVE` |
| Scope locked to single consented IP | `trigger-scan.sh` prompt |
| Non-destructive / low-aggression | `trigger-scan.sh` prompt |
| Per-device cooldown | `trigger-scan.sh` `COOLDOWN` |
| Global kill switch | `touch ~/ap-testbed/logs/HALT` |
| RF footprint capped (~8 dBm) | `isolation.sh` txpower |

## Kill switch
```bash
touch ~/ap-testbed/logs/HALT      # stops all future scans immediately
```
