# SEAT OPS e-ink panel

A glanceable hardware status board for the Pi 5 red/blue stack, running on a
**Pi Zero 2 W + 2.13″ Waveshare e-ink HAT** (~250×122 mono). It polls the Pi 5
admin console's `/api/panel` endpoint and shows, at a glance:

```
 SEAT OPS                 14:32
 ● Slv  ● Myt  ● Hot  ● IDS
 ─────────────────────────────
 SCANS 1▸   5      PROBERS   9
 TRIPS      1      ALERTS    2
 ! Canary token tripped 203.0.113.7   (inverted bar on a critical event)
```

- **Status dots:** Sliver / Mythic backends up, Hot-pot armed, IDS running.
- **Metrics:** total scans (+running), unique probers, canary token trips, open alerts.
- **Footer:** the latest alert; inverted black bar when it's critical/serious.

It authenticates with a **scoped, read-only panel token** — the Zero never holds
the admin password. All rendering is Pillow + stdlib `urllib`; the only extra
dependency is the Waveshare driver.

## On the Pi 5 (one-time)

The `/api/panel` endpoint and token ship with the admin console. Grab the token:

```bash
cat ~/ap-testbed/state/panel.token      # created on install; else: openssl rand -hex 16 > ~/ap-testbed/state/panel.token
```

Make sure the admin console is reachable from the Zero (it binds `0.0.0.0:8787` on
`wlan0`/Tailscale by default).

## On the Pi Zero 2 W

1. Flash Raspberry Pi OS **Lite** (32/64-bit), boot, connect Wi-Fi, `sudo apt update`.
2. Copy this folder to the Zero (e.g. `scp -r eink-panel pi@zero:~/`).
3. Install:
   ```bash
   cd eink-panel && sudo bash install.sh
   ```
   It installs deps, enables SPI, vendors `waveshare_epd`, and installs the service.
4. Configure:
   ```bash
   sudo nano /etc/eink-panel.conf
   #   PI5_URL      = http://<pi5-ip-or-tailscale>:8787
   #   PANEL_TOKEN  = <the token from the Pi 5>
   #   EPD_DRIVER   = epd2in13_V4   (or _V3 / _V2 — match your HAT)
   ```
5. Preview without hardware, then run for real:
   ```bash
   python3 /opt/eink-panel/panel.py --mock /tmp/panel.png --sample   # writes a PNG
   sudo systemctl start eink-panel
   journalctl -fu eink-panel
   ```

## Config (`/etc/eink-panel.conf`)

| Key | Meaning |
|-----|---------|
| `PI5_URL` | Base URL of the Pi 5 admin console |
| `PANEL_TOKEN` | Scoped read-only token from `~/ap-testbed/state/panel.token` |
| `EPD_DRIVER` | `epd2in13_V4` / `_V3` / `_V2` — must match your HAT revision |
| `POLL_SECONDS` | Refresh interval (default 60; e-ink is slow, don't go tiny) |
| `ROTATE` | `180` to flip if the HAT is mounted upside down |

## Modes / troubleshooting

- `panel.py --mock PATH [--sample]` — render to a PNG (no hardware); `--sample` uses
  canned data. Great for tuning layout.
- `panel.py --once` — one real frame then exit.
- **Blank or garbled screen** → wrong `EPD_DRIVER` for your HAT (try `_V3` / `_V2`).
- **`ImportError: waveshare_epd`** → the vendor step failed; re-run `install.sh` or copy
  `RaspberryPi_JetsonNano/python/lib/waveshare_epd` from the Waveshare e-Paper repo.
- **Bookworm GPIO** → `RPi.GPIO` is replaced by `lgpio`; `install.sh` installs
  `python3-lgpio`/`python3-gpiozero` best-effort. Recent `waveshare_epd` supports it.
- **`Pi 5 unreachable`** on screen → check `PI5_URL`/token and that the admin console
  is up (`/stack-status` on the Pi 5).

## What it shows vs. doesn't

Shows what the admin console owns (testbed/hot-pot metrics + IDS) and a liveness
probe of the C2 backends (Sliver port / Mythic containers). **Live Sliver session /
Mythic callback counts** need the C2 APIs (MCP), which the admin app doesn't have —
a natural follow-on is a small C2-status collector feeding those counts into
`/api/panel`.
