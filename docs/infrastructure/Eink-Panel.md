---
title: E-ink Ops Panel (Pi Zero 2 W companion)
tags: [infrastructure, hardware, eink, pi-zero, dashboard, monitoring]
platform: "Raspberry Pi Zero 2 W + 2.13\" Waveshare e-ink HAT"
updated: 2026-07-30
---

# 🖥️ E-ink Ops Panel — Pi Zero 2 W companion

Back to [[00-Index]]. A low-power hardware satellite for the Pi 5 stack: a
**Pi Zero 2 W + 2.13″ Waveshare e-ink HAT** (~250×122 mono) showing a glanceable
status board so the headless Pi 5 can be read at a glance without opening a browser.
Companion to the [[Autonomous-AP-Testbed|admin console]] + operations dashboard.

## What it shows
- **Status dots:** Sliver / Mythic backends up · Hot-pot armed · IDS running.
- **Metrics:** total scans (+ running), unique probers, canary token trips, open alerts.
- **Footer:** the latest alert; inverted black bar on a critical/serious event.

Live Sliver **session** / Mythic **callback** counts need the C2 MCP APIs (which the
admin app doesn't have), so those show as up/down glyphs. Wiring true counts via a
small C2-status collector is the natural follow-on. See [[C2-Primer]].

## How it works
- **Pi 5 side:** the admin console (`admin.py`) exposes **`/api/panel`** — a compact
  JSON subset of `/api/dashboard` plus a best-effort C2 liveness probe (Sliver =
  `127.0.0.1:31337` listening; Mythic = a `mythic_*` container running). Auth is a
  **scoped read-only token** in `state/panel.token` (`?token=` or `X-Panel-Token`),
  so the Zero never holds the admin password; Basic-Auth still works as a fallback.
- **Zero side:** `panel.py` polls `/api/panel` over Wi-Fi and renders to the e-ink
  with Pillow. Stdlib `urllib` for HTTP (no `requests`); the Waveshare `waveshare_epd`
  driver is the only extra dep. A `--mock PATH [--sample]` mode renders to a PNG so the
  layout is testable without hardware (used to verify the layout during the build).

## Layout (250×122)
```
 SEAT OPS                 14:32
 ● Slv  ● Myt  ● Hot  ● IDS
 ─────────────────────────────
 SCANS 1▸  5      PROBERS   9
 TRIPS     1      ALERTS    2
 ! Canary token tripped 203.0.113.7
```

## Where it lives
- **Repo:** `pi5-stack/payload/eink-panel/` — `panel.py`, `panel.conf.example`,
  `eink-panel.service`, `install.sh`, `README.md`.
- **Pi 5 endpoint:** `payload/ap-testbed/admin/admin.py` → `/api/panel`, `_panel_payload`,
  `_c2_status`, `_panel_token`.
- **Secrets (never committed):** `state/panel.token` (Pi 5), `/etc/eink-panel.conf` (Zero).

## Setup (summary — full steps in the package README)
1. Pi 5: `cat ~/ap-testbed/state/panel.token`; ensure the admin console is reachable.
2. Zero: flash Pi OS Lite → copy `eink-panel/` over → `sudo bash install.sh`.
3. Edit `/etc/eink-panel.conf` (`PI5_URL`, `PANEL_TOKEN`, `EPD_DRIVER` = your HAT rev).
4. `python3 /opt/eink-panel/panel.py --mock /tmp/p.png --sample` to preview, then
   `sudo systemctl start eink-panel`.

## Status
Pi 5 `/api/panel` endpoint built + tested (token/Basic-Auth/401 paths, live data).
Zero-side render verified via `--mock` (layout screenshot). The **hardware path**
(Waveshare `epd` init/display) is written to the standard driver API but **needs
on-device testing** — pick `EPD_DRIVER` to match the HAT revision (V2/V3/V4).

## Related
- [[Autonomous-AP-Testbed]] — the admin console + dashboard this mirrors
- [[Adversarial-Honeypot-Hotpot]] — where probers/trips/alerts come from
- [[Network-Sensors]] — the IDS whose status the panel shows · [[Architecture-Overview]]
