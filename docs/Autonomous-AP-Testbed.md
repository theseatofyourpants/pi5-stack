---
title: Autonomous AP Testbed
tags: [infra, offensive, wireless, autonomous, consent, testbed]
location: ~/ap-testbed/
status: hotplug-armed-build
updated: 2026-07-28
---

# Autonomous AP Testbed

Part of [[Architecture-Overview]]. A self-contained rig that runs its **own Wi-Fi
AP**, and when an **authorized** device joins and its owner **explicitly consents**
via a captive portal, fires a scoped **non-destructive** scan of *that one device*
and writes a report — chaining into [[web-assess]] and [[Detection-Library]].

Think of it as an *inverted honeypot* used as a **device-security bench**: instead
of passively logging attackers, it actively (but consensually) tests joiners.

## The one design decision that matters
The load-bearing component is **authorization**, not the radio. Two gate modes,
**no allow-all**:
- **Allowlist mode** — only pre-registered device MACs are ever tested (bench of
  your own devices).
- **Consent mode** — a captive portal requires the joiner to click *"I own this
  device and authorize a scan"* before anything runs (conference/demo booth).

> [!warning] Why there is no "allow by default" switch
> Auto-attacking anything that connects means attacking **non-consenting
> strangers** — illegal under CFAA regardless of venue. **DEF CON does not grant
> this**: its Code of Conduct prohibits attacking other attendees' devices, and
> "hostile network" only means *harden your own gear*, not *consent to be
> exploited*. Open Wi-Fi is promiscuous (phones auto-join), so allow-all in a
> crowd is textbook mass-targeting. The consent portal preserves the "anyone can
> walk up and try it" demo spirit **with** real authorization.

## Radio topology (resolved 2026-07-28)
> [!success] Two radios now — clean split
> - **`wlan1`** = USB **MediaTek MT7612U** (`mt76x2u`), AP-mode capable, 5 GHz →
>   dedicated **AP interface**.
> - **`wlan0`** (onboard `brcmfmac`) stays the **uplink** (TSOYP-Home) + default route.
>
> AP defaults to **5 GHz channel 36** (non-DFS; 36/40/44/48 available at 20 dBm —
> the DFS channels 52+ are avoided). `setup-ap.sh` **refuses** to run against the
> default-route interface, so it can never knock the Pi (or Tailscale/SSH) offline
> by accident. See [[Reboot-Runbook]].

## Layers (each independently stoppable)
| Layer | What | Files | Offense? |
|---|---|---|---|
| 1 | Isolated AP + captive **consent portal** | `setup-ap.sh`, `isolation.sh`, `consent-portal/` | none |
| 2 | Join logging | `watcher.sh` (dnsmasq `dhcp-script`) | none (log-only) |
| 3 | **Scan trigger** | `trigger-scan.sh` (launched by portal on consent) | **disarmed** until `ARM_OFFENSIVE=1` |

## Data flow
```
device joins wlanX (open AP)
  → dnsmasq DHCP + captive DNS (all names → 10.66.66.1)
  → watcher.sh logs the join (joins.log)
  → device opens any URL → consent portal splash
  → owner clicks CONSENT → allowlist.jsonl ledger entry
  → portal launches trigger-scan.sh <ip> <mac>
        · kill-switch check (logs/HALT)
        · consent-on-record check (defense in depth)
        · per-MAC cooldown
        · DISARMED gate (ARM_OFFENSIVE) → else headless `claude -p`
        · scope LOCKED to single IP, LOW aggression, non-destructive
  → ~/engagements/auto-<mac>-<ts>.md  → seeds [[detection-engineer]]
```

## Captive portal: bind :80 directly (do NOT use nat REDIRECT)
> [!warning] REDIRECT/DNAT to a high port silently fails on this Docker host
> First attempt ran the portal on :8081 with `iptables -t nat REDIRECT 80→8081`.
> The rule **matched** (non-zero pkt counter) but the DNAT'd connection never
> completed — no SYN-ACK returned to the client (Docker/conntrack reply-path
> quirk). Fix: the portal **binds :80 directly** (evilportal-style), no NAT in the
> path. `isolation.sh` just `ACCEPT`s :80. Non-root bind via systemd
> `AmbientCapabilities=CAP_NET_BIND_SERVICE` (or `sudo` for a manual run).
> **Validated 2026-07-28** end-to-end on an iPhone (iOS 18.7): join → splash →
> consent → `AUTHORIZED but DISARMED` in scans.log.

## Hot-plug arming (udev + systemd) — the dongle IS the switch
Plug the MT7612U in → the testbed comes up **ARMED**; pull it out → full teardown.
Nothing auto-starts at boot; presence of the dongle is the only trigger.

```
udev (0e8d:7612 add/remove)  →  systemctl start/stop ap-testbed.target
   ap-testbed.target Wants:
     ├─ ap-testbed-net.service      (oneshot) bringup-net.sh → detect dongle iface,
     │        GUARD vs uplink, static 10.66.66.1, render confs, isolation.sh
     │        ExecStop → teardown-net.sh (removes ONLY testbed rules/addrs)
     ├─ ap-testbed-hostapd.service  hostapd /run/ap-testbed/hostapd.conf  (BindsTo net)
     ├─ ap-testbed-dnsmasq.service  dnsmasq -k -C /run/ap-testbed/dnsmasq.conf (BindsTo net)
     └─ ap-testbed-portal.service   portal.py as User=tsoyp, CAP_NET_BIND_SERVICE,
              PORTAL_BIND=10.66.66.1, ARM_OFFENSIVE=1   (BindsTo net)
```
- **iface auto-detected** by driver `mt76x2u`; `bringup-net.sh` still refuses the
  default-route interface. Configs render to `/run/ap-testbed/` (tmpfs).
- **Teardown is surgical**: only the `APTESTBED` chain + `-i <iface>` FORWARD rules
  + the AP IP are removed. `wlan0`, Docker/Mythic, and the failsafe are untouched.
- **Portal runs as `tsoyp`** (not root) so an armed `trigger-scan.sh` → `claude -p`
  runs with the correct HOME/skills/MCP config.
- Install: `sudo bash ~/ap-testbed/install-testbed.sh` (stops any manual instance,
  installs 5 units + udev rule, chowns logs). Files staged in `~/ap-testbed/{systemd,udev}/`.

## Admin console (always-on, wlan0/tailscale)
`ap-testbed-admin.service` runs independently of the dongle so you can manage the
testbed and review history anytime. Flask app (`admin/admin.py`) as `User=tsoyp`
on **:8787**, Basic-Auth (password `state/admin.pass`, generated at install),
CSRF-protected mutations, strict input validation, report HTML escaped before
render. Reachable at `http://<wlan0-ip>:8787` and `http://<tailscale-ip>:8787`.

Features: dashboard (AP status/armed/counts) · **device allowlist CRUD** · consent
ledger view · **scan history + live progress** (polls the per-scan log) · **HTML +
PDF report** views (markdown→HTML via `markdown`, HTML→PDF via **chromium
headless** — weasyprint on this host hits a pydyf mismatch, chromium is primary) ·
**SSID rename** (writes `state/config.json`, restarts hostapd via a narrowly
scoped sudoers rule if the AP is up) · arm/disarm toggle · HALT kill-switch ·
**egress toggle** (config.egress → isolation `EGRESS`; applies via target restart) ·
**auto-abort toggle** (config.auto_abort → trigger-scan watchdog) · **Rescan/Retry**
(clears the per-MAC cooldown + re-triggers a scan now — on Devices per device and
Scans per scan; device must be connected) · **Reset** (drops a device's cooldown +
session consent + scan records so it "acts new"; stays allowlisted) · **Revoke &
wipe** (Consents page: cut egress + clear consent/session/cooldown + delete scan
records AND report files — full per-device purge for post-restart cleanup).

> [!note] Armed state is config-only (fixed 2026-07-29)
> `trigger-scan.sh` gates arming on `config.armed` (the Settings toggle) + HALT —
> NOT an `ARM_OFFENSIVE` env var. The env var was only set on the portal service,
> so the watcher/allowlist and admin-Retry paths were wrongly always-disarmed while
> the consent path worked. Now all launch paths behave identically. The bug failed
> *safe* (didn't scan when it should have); it never scanned an unauthorized device.

State store `lib/store.py` (shared by admin + shell scripts): `state/config.json`
(ssid/channel/country/armed), `state/devices.json` (managed allowlist),
`state/scans/<id>.{json,log}`, consent ledger `logs/allowlist.jsonl`.

## Scan orchestration → [[device-assess]] (NOT /web-assess directly, NOT /operation)
`trigger-scan.sh` invokes the **`/device-assess`** skill (`~/.claude/agents/device-assess.md`):
an unattended, scope-LOCKED, non-destructive orchestrator that does network + service
enumeration, device/OS fingerprint, and device-level vuln ID (nmap/nuclei/enum via
kali-server + hexstrike), then delegates to [[web-assess]] **only if web ports exist**.
`/operation` is deliberately NOT used — it's interactive + includes weaponization/
post-ex/C2, wrong for auto-firing on a connecting device. Streaming progress via
`lib/stream-filter.py` (stream-json → readable lines) into the per-scan log.

> [!warning] Headless permissions
> Unattended `claude -p` has no human to approve tool prompts, so `trigger-scan.sh`
> runs it with **`--dangerously-skip-permissions`** (else even the report `Write` is
> auto-denied). Guardrails then come from the design (scope-lock, non-destructive,
> isolation, non-root, HALT) not the permission layer. Residual: prompt-injection
> from a hostile scanned device — mitigate by locking [[device-assess]]'s toolset.

Optional **auto-abort** (config.auto_abort): a watchdog polls `iw station dump` for
the target MAC; if it leaves the AP for ~90s (plus hostapd inactivity lag) the scan
is killed and marked `aborted`. Optional **egress** (config.egress): NAT'd internet
for clients (still LAN-isolated) so devices don't auto-leave mid-scan.

## Hybrid captive portal + per-MAC egress
The proper captive design: authorized devices get LAN-isolated internet (and stay
connected through a scan) while unauthorized devices are walled off and see the
consent portal.
- **DNS** (`conf/dnsmasq-ap.conf.template`): REAL upstream resolution (1.1.1.1/
  8.8.8.8) for everyone + hijack of ONLY the OS captive-probe hostnames → portal.
- **Portal is MAC-aware** (`portal.py`): a probe from an **authorized** MAC gets an
  OS "success" reply (204 / Apple-Success / NCSI text) so its captive UI never
  re-pops; an **unauthorized** MAC gets the consent splash so the captive assistant
  opens.
- **Per-MAC egress** (`isolation.sh` `APT_EGRESS` chain, EGRESS=1): DROP all private
  nets (LAN isolation), then one `-m mac --mac-source <mac> ACCEPT` per authorized
  MAC; unauthorized traffic hits a catch-all FORWARD DROP. Stock iptables — **no
  ipset** (not installed).
- **Authorize/revoke** (`apt-authorize.sh` → installed root-owned at
  `/usr/local/sbin/apt-testbed-authorize`, NOT in tsoyp's home → no privesc): the
  portal calls it on consent, the admin console on allowlist add/remove, and
  bring-up pre-authorizes allowlist MACs. Auth state = allowlist ∪ session-consents
  (`state/session-auth`, reset each bring-up).
- **Egress toggle** now means: **ON** = hybrid per-MAC internet; **OFF** = pure
  walled garden (captive portal still works, nobody egresses).

## Branding
Operator identity **"Security by The Seat of Your Pants"** + site
`https://who.theseatofyourpants.com` appear on the client-facing pages (consent
splash, granted screen, `status.test` report) and the admin console header. The
Wi-Fi SSID stays **Open Security Test** (the network name, editable in Settings).

## Per-device status page (`status.test`)
dnsmasq also hijacks `status.test` / `report.test` → the portal. The portal serves a
**MAC-scoped** status page: a device sees only *its own* scan — live streaming
progress while running (auto-refresh 5s), the full report rendered inline when done
(markdown→HTML, escaped anti-XSS). The consent/granted screen links to it with an
"open in your real browser (Safari/Chrome), not the captive sheet" hint. Always
reachable at `http://10.66.66.1` too.

## Two authorization paths (both gated by ARM + HALT + cooldown + scope-lock)
1. **Consent** (captive portal): any device → tap consent → scan. (opt-in/demo)
2. **Allowlist** (admin-managed): a pre-authorized MAC joins → `watcher.sh`
   auto-scans it on connect, dropping root→tsoyp via `runuser`. (own bench devices)
`trigger-scan.sh` authorizes if MAC is on the allowlist **or** has consent on record.

SSID default is now **`Open Security Test`** (was consent-testbed).

## Coexistence with [[wifi-failsafe]]
Different radio (`wlan1` vs `wlan0`), different subnet (`10.66.66` vs `10.42.0`),
different iptables scope (`APTESTBED` is `-i wlan1` only). The **only** shared
resource is TCP :80. Testbed portal binds `10.66.66.1:80` specifically (not
`0.0.0.0`), so it never answers on `wlan0`. Residual edge: failsafe binds
`0.0.0.0:80` and only starts its portal when `wlan0` is down 45s+ — if that
happens while the dongle is in, the binds collide. **Recommended 1-line failsafe
hardening**: bind its Flask app to `10.42.0.1` instead of `0.0.0.0`.

## Isolation guarantees (`isolation.sh`)
- AP clients **cannot** reach the LAN or the uplink subnet (protects you).
- AP clients get **no internet** by default (`EGRESS=0`) (protects everyone else).
- Client-to-client blocked (`ap_isolate=1` + FORWARD drop).
- TX power capped ~8 dBm to shrink the RF footprint.
- Only DHCP, captive DNS, and the portal (:8081) are reachable on the Pi.

## Safety controls
- Uplink interface protected — `setup-ap.sh` GUARD 1
- Consent required before any scan — `consent-portal/portal.py`
- Offense disarmed by default — `trigger-scan.sh` `ARM_OFFENSIVE`
- Scope locked to single consented IP; low-aggression/non-destructive prompt
- Per-device cooldown; global kill switch `touch ~/ap-testbed/logs/HALT`

## Bring-up
See `~/ap-testbed/README.md`. Short form once a dedicated AP iface exists:
```bash
sudo AP_IFACE=wlan1 bash ~/ap-testbed/setup-ap.sh
python3 ~/ap-testbed/consent-portal/portal.py
tail -f ~/ap-testbed/logs/joins.log ~/ap-testbed/logs/scans.log   # log-only first
```

## Status
**Scaffolded, syntax-validated, radio present — ready to bring up.** MT7612U on
`wlan1` qualified (AP mode + 5 GHz ch36). Next: `sudo AP_IFACE=wlan1 bash
~/ap-testbed/setup-ap.sh` (apt-installs hostapd on first run). Validate in
**log-only** mode (`ARM_OFFENSIVE` unset) before arming Layer 3. Layer 3 reuses
[[web-assess]] under an unattended, scope-locked prompt.

## Related
[[Architecture-Overview]] · [[web-assess]] · [[osint-profile]] · [[Network-Sensors]]
(Suricata/Zeek can watch the AP bridge) · [[Detection-Library]] · [[Reboot-Runbook]]
