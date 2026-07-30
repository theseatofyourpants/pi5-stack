#!/usr/bin/env python3
"""SEAT OPS e-ink panel — Pi Zero 2 W companion for the Pi 5 red/blue stack.

Polls the Pi 5 admin console's /api/panel endpoint (scoped read-only token) and
renders a glanceable status board on a ~250x122 Waveshare 2.13" e-ink HAT:
C2 backends up/down, hot-pot armed, IDS, and the live testbed metrics.

Modes:
  (default)            run forever, refresh the e-ink every POLL_SECONDS
  --once               fetch + render one frame to the e-ink, then exit
  --mock [PATH]        render to a PNG instead of the e-ink (no hardware needed)
  --sample             use canned data (with --mock) to preview the layout offline

Config: /etc/eink-panel.conf (KEY=VALUE), overridable by env. See panel.conf.example.
Stdlib HTTP (urllib) + Pillow only; the waveshare_epd driver is imported lazily so
--mock works on any machine.
"""
import os, sys, ssl, json, time, importlib, urllib.request
from PIL import Image, ImageDraw, ImageFont

# ---- config ----------------------------------------------------------------
def load_conf():
    conf = {
        "PI5_URL": "http://raspberrypi.local:8787",
        "PANEL_TOKEN": "",
        "EPD_DRIVER": "epd2in13_V4",     # V2 / V3 / V4 — set to your HAT revision
        "POLL_SECONDS": "60",
        "FULL_REFRESH_EVERY": "30",       # full refresh every N cycles to clear ghosting
        "PARTIAL": "0",                   # 1 = try partial refresh (variant-dependent)
        "ROTATE": "0",                    # 180 to flip if your HAT mounts inverted
        "FONT_DIR": "/usr/share/fonts/truetype/dejavu",
    }
    path = os.environ.get("EINK_PANEL_CONF", "/etc/eink-panel.conf")
    try:
        for line in open(path):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    for k in conf:                        # env overrides file
        if k in os.environ:
            conf[k] = os.environ[k]
    return conf


# ---- data ------------------------------------------------------------------
def fetch(conf):
    url = conf["PI5_URL"].rstrip("/") + "/api/panel"
    req = urllib.request.Request(url, headers={"X-Panel-Token": conf["PANEL_TOKEN"]})
    ctx = ssl.create_default_context()
    ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE   # tolerate self-signed
    with urllib.request.urlopen(req, timeout=8, context=ctx) as r:
        return json.loads(r.read().decode())


def sample_data():
    return {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "ssid": "Open Security Test",
            "ap": True, "hotpot": True, "egress": False, "ids": True,
            "sliver": True, "mythic": True, "scans_total": 5, "scans_running": 1,
            "probers": 9, "token_trips": 1, "loot_pulls": 1, "alerts": 2, "findings_hi": 0,
            "last_alert": {"sev": "critical", "kind": "Canary token tripped",
                           "src": "203.0.113.7", "when": "2026-07-30T14:31:02"}}


# ---- rendering -------------------------------------------------------------
def _font(conf, size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    for p in (os.path.join(conf["FONT_DIR"], name), "/usr/share/fonts/truetype/dejavu/" + name):
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            pass
    return ImageFont.load_default()


def _dot(draw, x, y, on, r=4):
    if on:
        draw.ellipse((x, y, x + 2 * r, y + 2 * r), fill=0)
    else:
        draw.ellipse((x, y, x + 2 * r, y + 2 * r), outline=0)


def _clip(s, n):
    s = s or ""
    return s if len(s) <= n else s[:n - 1] + "…"


def render(data, conf, size=(250, 122)):
    """Return a 1-bit PIL image of the panel. 0=black, 255=white."""
    W, H = size
    img = Image.new("1", (W, H), 255)
    d = ImageDraw.Draw(img)
    f_hdr = _font(conf, 14, bold=True)
    f_lbl = _font(conf, 10)
    f_big = _font(conf, 21, bold=True)
    f_sm = _font(conf, 9)

    off = data is None
    dd = data or {}

    # header (0..16)
    d.text((3, 0), "SEAT OPS", font=f_hdr, fill=0)
    clock = time.strftime("%H:%M")
    tw = d.textlength(clock, font=f_sm)
    d.text((W - tw - 3, 3), clock, font=f_sm, fill=0)
    d.line((0, 17, W, 17), fill=0)

    if off:
        d.text((3, 44), "Pi 5 unreachable", font=f_hdr, fill=0)
        d.text((3, 66), "retrying…", font=f_lbl, fill=0)
        return img

    # status glyphs row (19..33): Sliver / Mythic / Hot-pot / IDS
    row = [("Slv", dd.get("sliver")), ("Myt", dd.get("mythic")),
           ("Hot", dd.get("hotpot")), ("IDS", dd.get("ids"))]
    x = 4
    for lbl, on in row:
        _dot(d, x, 21, bool(on), r=3)
        d.text((x + 10, 19), lbl, font=f_sm, fill=0)
        x += 62
    d.line((0, 34, W, 34), fill=0)

    # 2x2 metric grid (rows at y=37 and y=69; label + big number per cell)
    run = dd.get("scans_running", 0)
    cells = [("SCANS" + (" %d▸" % run if run else ""), dd.get("scans_total", 0)),
             ("PROBERS", dd.get("probers", 0)),
             ("TRIPS", dd.get("token_trips", 0)),
             ("ALERTS", dd.get("alerts", 0))]
    cx = [6, 130]; cy = [37, 69]
    for i, (lbl, val) in enumerate(cells):
        x = cx[i % 2]; y = cy[i // 2]
        d.text((x, y), lbl, font=f_lbl, fill=0)
        d.text((x, y + 9), str(val), font=f_big, fill=0)

    # footer (bar at 102..121): latest alert, inverted if critical/serious
    la = dd.get("last_alert")
    fy = 103
    if la:
        line = "! %s  %s" % (_clip(la.get("kind", ""), 20), la.get("src", ""))
        if la.get("sev") in ("critical", "serious"):
            d.rectangle((0, 101, W, H), fill=0)
            d.text((3, fy), _clip(line, 42), font=f_sm, fill=255)
        else:
            d.line((0, 101, W, 101), fill=0)
            d.text((3, fy), _clip(line, 42), font=f_sm, fill=0)
    else:
        d.line((0, 101, W, 101), fill=0)
        d.text((3, fy), "no alerts — quiet", font=f_sm, fill=0)

    if str(conf.get("ROTATE", "0")) == "180":
        img = img.rotate(180)
    return img


# ---- e-ink driver ----------------------------------------------------------
def epd_open(conf):
    mod = importlib.import_module("waveshare_epd." + conf["EPD_DRIVER"])
    epd = mod.EPD()
    try:
        epd.init()                        # V3/V4 signature
    except TypeError:
        epd.init(epd.FULL_UPDATE)         # V2 signature
    epd.Clear(0xFF)
    return epd


def epd_show(epd, img):
    # landscape image is W×H = 250×122; the driver's getbuffer handles orientation.
    epd.display(epd.getbuffer(img))


# ---- main ------------------------------------------------------------------
def main():
    args = sys.argv[1:]
    conf = load_conf()

    if "--mock" in args:
        path = "panel.png"
        i = args.index("--mock")
        if i + 1 < len(args) and not args[i + 1].startswith("-"):
            path = args[i + 1]
        data = sample_data() if "--sample" in args else _safe_fetch(conf)
        img = render(data, conf)
        img.save(path)
        print("wrote", path)
        return

    epd = epd_open(conf)
    once = "--once" in args
    n = 0
    try:
        while True:
            img = render(_safe_fetch(conf), conf)
            epd_show(epd, img)
            n += 1
            if once:
                break
            time.sleep(int(conf["POLL_SECONDS"]))
    except KeyboardInterrupt:
        pass
    finally:
        try:
            epd.sleep()
        except Exception:
            pass


def _safe_fetch(conf):
    try:
        return fetch(conf)
    except Exception as e:
        sys.stderr.write("fetch failed: %s\n" % e)
        return None


if __name__ == "__main__":
    main()
