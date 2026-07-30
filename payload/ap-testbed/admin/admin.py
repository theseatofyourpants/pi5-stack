#!/usr/bin/env python3
"""AP Testbed admin console — runs always-on on wlan0/tailscale (independent of
the dongle) so you can manage the device allowlist, review scans + live progress,
read HTML/PDF reports, and rename the SSID.

Security: HTTP Basic Auth (password in state/admin.pass), CSRF token on every
mutating POST, strict input validation, report HTML is escaped before render.
Runs as tsoyp. The ONE privileged action (restart hostapd to apply an SSID
change) goes through a narrowly scoped sudoers rule.
"""
import os, sys, hmac, hashlib, subprocess, shutil, tempfile, html as _html
import json, re, time
from functools import wraps

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import store  # noqa: E402

from flask import (Flask, request, redirect, url_for, Response,  # noqa: E402
                   render_template, abort, make_response)

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Real password lives in state/admin.pass. ADMIN_PASS_FILE lets tests point at a
# scratch file so smoke-testing never clobbers the real credential.
PASS_FILE = os.environ.get("ADMIN_PASS_FILE", os.path.join(BASE, "state", "admin.pass"))
BIND = os.environ.get("ADMIN_BIND", "0.0.0.0")
PORT = int(os.environ.get("ADMIN_PORT", "8787"))
HALT = store.HALT

app = Flask(__name__, template_folder="templates")


def _password():
    try:
        return open(PASS_FILE).read().strip()
    except Exception:
        return ""  # no password file => auth always fails (locked)


def _csrf_token():
    return hashlib.sha256(("csrf:" + _password()).encode()).hexdigest()[:32]


def _check_auth(user, pw):
    want = _password()
    return bool(want) and user == "admin" and hmac.compare_digest(pw, want)


def require_auth(f):
    @wraps(f)
    def wrap(*a, **k):
        au = request.authorization
        if not au or not _check_auth(au.username or "", au.password or ""):
            return Response("Authentication required", 401,
                            {"WWW-Authenticate": 'Basic realm="AP Testbed Admin"'})
        return f(*a, **k)
    return wrap


def require_csrf():
    if request.form.get("csrf", "") != _csrf_token():
        abort(400, "bad CSRF token")


@app.context_processor
def _inject():
    return {"csrf_token": _csrf_token()}


# ---- system helpers --------------------------------------------------------
def unit_active(unit):
    try:
        r = subprocess.run(["systemctl", "is-active", unit],
                           capture_output=True, text=True, timeout=5)
        return r.stdout.strip() == "active"
    except Exception:
        return False


def ap_status():
    iface = ""
    try: iface = open("/run/ap-testbed/iface").read().strip()
    except Exception: pass
    return {
        "hostapd": unit_active("ap-testbed-hostapd.service"),
        "portal":  unit_active("ap-testbed-portal.service"),
        "iface":   iface,
        "armed":   store.is_armed(),
        "halt":    os.path.exists(HALT),
        "ssid":    store.load_config().get("ssid", ""),
    }


def _html_to_pdf(doc):
    """Render an HTML string to PDF bytes. Prefers chromium headless (reliable on
    this arm64 host); falls back to weasyprint if chromium is unavailable."""
    for binname in ("chromium", "chromium-browser", "google-chrome"):
        exe = shutil.which(binname)
        if not exe:
            continue
        with tempfile.TemporaryDirectory() as td:
            src = os.path.join(td, "r.html"); out = os.path.join(td, "r.pdf")
            with open(src, "w") as f:
                f.write(doc)
            subprocess.run([exe, "--headless", "--no-sandbox", "--disable-gpu",
                            "--no-pdf-header-footer", "--user-data-dir=" + td,
                            "--print-to-pdf=" + out, "file://" + src],
                           capture_output=True, timeout=90)
            if os.path.exists(out) and os.path.getsize(out) > 0:
                return open(out, "rb").read()
    from weasyprint import HTML  # last resort
    return HTML(string=doc).write_pdf()


def apply_ssid_restart():
    """Restart hostapd so a new SSID takes effect — only if the AP is up.
    Uses the scoped sudoers rule. Safe no-op if the dongle is out."""
    if unit_active("ap-testbed-hostapd.service"):
        try:
            subprocess.run(["sudo", "-n", "systemctl", "restart",
                            "ap-testbed-hostapd.service"], timeout=15)
        except Exception:
            pass


def authorize_mac(mac, action):
    """Open (add) or revoke (del) LAN-isolated egress for a MAC via the scoped
    root helper. No-op if egress is off / AP down (helper handles that)."""
    try:
        subprocess.run(["sudo", "-n", "/usr/local/sbin/apt-testbed-authorize", action, mac],
                       capture_output=True, timeout=10)
    except Exception:
        pass


def apply_target_restart():
    """Restart the whole target so a firewall change (egress) is re-applied —
    only if the AP is up. Brief AP blip. Uses the scoped sudoers rule."""
    if unit_active("ap-testbed-hostapd.service"):
        try:
            subprocess.run(["sudo", "-n", "systemctl", "restart",
                            "ap-testbed.target"], timeout=30)
        except Exception:
            pass


def hotpot_restart():
    """Apply a deception on/off change by (re)starting the hot-pot unit via the
    scoped sudoers rule. Safe no-op if the AP is down (the unit self-gates on the
    deception flag + AP presence)."""
    try:
        subprocess.run(["sudo", "-n", "systemctl", "restart",
                        "ap-testbed-hotpot.service"], timeout=180)
    except Exception:
        pass


# ---- dashboard aggregation -------------------------------------------------
SEVERITIES = ["Critical", "High", "Medium", "Low", "Info"]
EVENT_TYPES = ["probe", "cred_attempt", "loot_pull", "token_trip"]
_sev_cache = {}   # report_path -> (mtime, {severity: count})


def _ts_epoch(s):
    try:
        return time.mktime(time.strptime((s or "")[:19], "%Y-%m-%dT%H:%M:%S"))
    except Exception:
        return None


def _parse_severities(path):
    """Approximate finding-severity tally from a device-assess report (markdown).
    Cached by file mtime so polling stays cheap."""
    try:
        mt = os.stat(path).st_mtime
    except OSError:
        return {s: 0 for s in SEVERITIES}
    hit = _sev_cache.get(path)
    if hit and hit[0] == mt:
        return hit[1]
    counts = {s: 0 for s in SEVERITIES}
    try:
        txt = open(path, errors="ignore").read()
    except Exception:
        txt = ""
    # primary: an explicit "Severity: High" / "**Severity:** High" / "| High |"
    for m in re.finditer(r'(?i)severity[^A-Za-z0-9]{0,6}(critical|high|medium|low|info)', txt):
        counts[m.group(1).capitalize()] += 1
    if sum(counts.values()) == 0:   # fallback: finding rows/bullets naming a severity
        for line in txt.splitlines():
            if re.match(r'\s*([-*|>#]|\d+\.)', line):
                m = re.search(r'(?i)\b(critical|high|medium|low|info)\b', line)
                if m:
                    counts[m.group(1).capitalize()] += 1
    _sev_cache[path] = (mt, counts)
    return counts


def _timeline(events, hours=24, buckets=24):
    now = time.time(); start = now - hours * 3600; width = (hours * 3600) / buckets
    grid = [{"t": int(start + i * width), **{t: 0 for t in EVENT_TYPES}} for i in range(buckets)]
    for e in events:
        ep = _ts_epoch(e.get("ts", ""))
        if ep is None or ep < start:
            continue
        idx = min(buckets - 1, max(0, int((ep - start) / width)))
        ty = e.get("type", "probe"); ty = ty if ty in EVENT_TYPES else "probe"
        grid[idx][ty] += 1
    return {"buckets": grid, "types": EVENT_TYPES, "hours": hours}


def _sensor_status():
    """Best-effort Suricata alert feed. Checks the host-wide log and the hot-pot's
    own IDS log (hotpot-ctl.sh runs a dedicated Suricata on the AP interface).
    Graceful if the log isn't readable/present — surfaces the one-line fix."""
    candidates = ["/var/log/suricata/eve.json", "/var/log/suricata/hotpot/eve.json"]
    out = {"available": False, "alert_count": 0, "alerts": [], "note": ""}
    lines = None
    existed_unreadable = None
    for path in candidates:
        try:
            with open(path) as f:
                lines = f.readlines()[-3000:]
            break
        except PermissionError:
            existed_unreadable = path
        except FileNotFoundError:
            pass
        except Exception as ex:
            out["note"] = "sensor read error: %s" % ex
            return out
    if lines is None:
        if existed_unreadable:
            out["note"] = ("suricata log not readable by this user — run:  "
                           "sudo setfacl -m u:tsoyp:r %s" % existed_unreadable)
        else:
            out["note"] = ("suricata eve.json not found — sensor down (arm the hot-pot to "
                           "start IDS on the AP, or see /stack-status)")
        return out
    recent = []
    for ln in lines:
        try:
            j = json.loads(ln)
        except Exception:
            continue
        if j.get("event_type") == "alert":
            a = j.get("alert", {})
            recent.append({"ts": (j.get("timestamp", "") or "")[:19],
                           "sig": a.get("signature", ""), "sev": a.get("severity", 3),
                           "src": j.get("src_ip", ""), "dest": j.get("dest_ip", "")})
    out["available"] = True
    out["alert_count"] = len(recent)
    out["alerts"] = recent[-20:][::-1]
    return out


def _dashboard_payload():
    cfg = store.load_config()
    scans = store.list_scans()
    running = []
    status_counts = {}
    sev_totals = {s: 0 for s in SEVERITIES}
    for s in scans:
        st = s.get("status", "?")
        status_counts[st] = status_counts.get(st, 0) + 1
        if st == "running":
            elapsed = ""
            ep = _ts_epoch(s.get("started", ""))
            if ep:
                elapsed = int(time.time() - ep)
            running.append({"id": s.get("id"), "mac": s.get("mac"), "ip": s.get("ip"),
                            "started": s.get("started"), "elapsed": elapsed})
        if st == "done" and s.get("report_md"):
            for k, v in _parse_severities(s["report_md"]).items():
                sev_totals[k] += v
    recent_scans = [{"id": s.get("id"), "mac": s.get("mac"), "ip": s.get("ip"),
                     "auth": s.get("auth"), "status": s.get("status"),
                     "started": s.get("started")} for s in scans[:10]]

    events = store.list_hotpot_events(limit=3000)
    ev_by_type = {t: 0 for t in EVENT_TYPES}
    sources = {}
    for e in events:
        t = e.get("type", "probe")
        ev_by_type[t] = ev_by_type.get(t, 0) + 1
        src = e.get("src", "?")
        r = sources.setdefault(src, {"src": src, "events": 0, "creds": 0, "loot": 0,
                                     "trips": 0, "probes": 0, "last": ""})
        r["events"] += 1
        if t == "cred_attempt": r["creds"] += 1
        elif t == "loot_pull":  r["loot"] += 1
        elif t == "token_trip": r["trips"] += 1
        elif t == "probe":      r["probes"] += 1
        if e.get("ts", "") > r["last"]:
            r["last"] = e.get("ts", "")
    sources = sorted(sources.values(), key=lambda r: r["last"], reverse=True)

    tokens = store.load_tokens()
    trip_by_token = {}
    for e in events:
        if e.get("type") == "token_trip":
            trip_by_token.setdefault(e.get("token"), []).append(e)
    tok_view = []
    for t in tokens:
        tr = trip_by_token.get(t.get("id"), [])
        tok_view.append({"file": t.get("file"), "kind": t.get("kind"), "backend": t.get("backend"),
                         "beacon": t.get("beacon"), "trips": len(tr),
                         "last": (tr[-1].get("ts") if tr else (t.get("tripped") or "")),
                         "last_src": (tr[-1].get("src") if tr else "")})

    # synthesized alert stream: token trips (critical), loot pulls (serious),
    # credential bursts (warning), + Suricata (best-effort).
    alerts = []
    for e in events:
        if e.get("type") == "token_trip":
            alerts.append({"ts": e.get("ts", ""), "sev": "critical", "kind": "Canary token tripped",
                           "src": e.get("src", ""), "detail": "token %s" % e.get("token", "")})
        elif e.get("type") == "loot_pull":
            alerts.append({"ts": e.get("ts", ""), "sev": "serious", "kind": "Bait loot pulled",
                           "src": e.get("src", ""), "detail": e.get("file", "")})
    for r in sources:
        if r["creds"] >= 10:
            alerts.append({"ts": r["last"], "sev": "warning", "kind": "Credential burst",
                           "src": r["src"], "detail": "%d login attempts" % r["creds"]})
    sensors = _sensor_status()
    for a in sensors["alerts"]:
        sev = "critical" if a["sev"] == 1 else ("serious" if a["sev"] == 2 else "warning")
        alerts.append({"ts": a["ts"], "sev": sev, "kind": "IDS: " + (a["sig"] or "alert"),
                       "src": a["src"], "detail": "%s → %s" % (a["src"], a["dest"])})
    alerts.sort(key=lambda a: a.get("ts", ""), reverse=True)
    alerts = alerts[:30]

    return {
        "st": ap_status(),
        "cfg": {"deception": bool(cfg.get("deception")), "egress": bool(cfg.get("egress")),
                "token_backend": cfg.get("token_backend", "local")},
        "kpi": {"devices": len(store.load_devices()), "scans_total": len(scans),
                "scans_running": len(running), "probers": len(sources),
                "events_total": len(events), "token_trips": ev_by_type.get("token_trip", 0),
                "loot_pulls": ev_by_type.get("loot_pull", 0),
                "findings_hi": sev_totals["Critical"] + sev_totals["High"],
                "alerts": len(alerts)},
        "severity": sev_totals,
        "scan_status": status_counts,
        "events_by_type": ev_by_type,
        "timeline": _timeline(events),
        "sources": sources[:12],
        "tokens": tok_view,
        "alerts": alerts,
        "running": running,
        "recent_scans": recent_scans,
        "sensors": {"available": sensors["available"], "note": sensors["note"],
                    "count": sensors["alert_count"]},
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }


# ---- routes ----------------------------------------------------------------
@app.route("/")
@require_auth
def dashboard():
    return render_template("dashboard.html", data=_dashboard_payload())


@app.route("/api/dashboard")
@require_auth
def api_dashboard():
    return Response(json.dumps(_dashboard_payload()), mimetype="application/json")


@app.route("/devices", methods=["GET"])
@require_auth
def devices():
    return render_template("devices.html", devices=store.load_devices(), msg=request.args.get("msg", ""))


@app.route("/devices/add", methods=["POST"])
@require_auth
def devices_add():
    require_csrf()
    mac = (request.form.get("mac", "") or "").lower().strip()
    ok, msg = store.add_device(mac, request.form.get("label", ""))
    if ok:
        authorize_mac(mac, "add")   # allowlisted -> gets egress + auto-scan on join
    return redirect(url_for("devices", msg=msg))


@app.route("/devices/remove", methods=["POST"])
@require_auth
def devices_remove():
    require_csrf()
    mac = (request.form.get("mac", "") or "").lower().strip()
    store.remove_device(mac)
    authorize_mac(mac, "del")         # revoke its egress
    store.clear_cooldown(mac)         # ...and fully reset its scan state
    store.remove_session_auth(mac)
    return redirect(url_for("devices", msg="removed"))


@app.route("/devices/reset", methods=["POST"])
@require_auth
def devices_reset():
    """Make a device 'act new': drop its cooldown, session consent, and scan
    records. Stays on the allowlist. Next join triggers a fresh scan."""
    require_csrf()
    mac = (request.form.get("mac", "") or "").lower().strip()
    if not store.valid_mac(mac):
        return redirect(url_for("devices", msg="invalid MAC"))
    store.clear_cooldown(mac)
    store.remove_session_auth(mac)
    store.delete_scans_for_mac(mac)
    return redirect(url_for("devices", msg="reset %s — it will scan fresh on next connect" % mac))


@app.route("/rescan", methods=["POST"])
@require_auth
def rescan():
    """Force a scan now (also used to retry an errored/aborted scan). Clears the
    cooldown and re-triggers if the device is currently connected."""
    require_csrf()
    mac = (request.form.get("mac", "") or "").lower().strip()
    if not store.valid_mac(mac):
        return redirect(url_for("scans", msg="invalid MAC"))
    if not store.is_authorized(mac):
        return redirect(url_for("scans", msg="%s isn't authorized (session consent gets cleared on restart). Add it on the Devices page for persistent auth, then Rescan." % mac))
    if not store.is_armed():
        return redirect(url_for("scans", msg="scanning is disarmed — enable it in Settings, then Rescan"))
    store.clear_cooldown(mac)
    ip = store.lease_ip_for_mac(mac)
    if not ip:
        return redirect(url_for("scans", msg="%s isn't connected right now — reconnect it, then Rescan" % mac))
    try:
        subprocess.Popen([os.path.join(BASE, "trigger-scan.sh"), ip, mac, "allowlist"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    return redirect(url_for("scans", msg="rescan started for %s (%s)" % (mac, ip)))


@app.route("/consents")
@require_auth
def consents():
    return render_template("consents.html", consents=store.list_consents(), msg=request.args.get("msg", ""))


@app.route("/revoke", methods=["POST"])
@require_auth
def revoke():
    """Revoke & wipe a device: cut its egress, clear consent + session + cooldown,
    and delete its scan records and report files. For post-restart cleanup."""
    require_csrf()
    mac = (request.form.get("mac", "") or "").lower().strip()
    if not store.valid_mac(mac):
        return redirect(url_for("consents", msg="invalid MAC"))
    authorize_mac(mac, "del")     # cut egress now
    store.purge_device(mac)       # consent, session, cooldown, scans, reports
    return redirect(url_for("consents", msg="revoked & wiped %s — consent, session, scans and reports cleared" % mac))


@app.route("/scans")
@require_auth
def scans():
    return render_template("scans.html", scans=store.list_scans(), msg=request.args.get("msg", ""))


@app.route("/scans/<sid>")
@require_auth
def scan_detail(sid):
    rec = store.get_scan(sid)
    if not rec:
        abort(404)
    return render_template("scan_detail.html", s=rec, log=store.scan_log(sid))


@app.route("/scans/<sid>/log")
@require_auth
def scan_log_raw(sid):
    if not store.valid_sid(sid):
        abort(404)
    rec = store.get_scan(sid) or {}
    return Response("[%s]\n%s" % (rec.get("status", "?"), store.scan_log(sid)),
                    mimetype="text/plain")


def _render_report_html(sid):
    rec = store.get_scan(sid)
    if not rec:
        return None, None
    path = rec.get("report_md", "")
    # constrain to the engagements dir (no traversal / arbitrary file read)
    rp = os.path.realpath(path)
    if not rp.startswith(os.path.realpath(store.ENGAGEMENTS) + os.sep):
        return rec, "<p><em>Report path outside engagements — refused.</em></p>"
    try:
        raw = open(rp).read()
    except Exception:
        return rec, "<p><em>Report not found yet (scan may still be running).</em></p>"
    import markdown
    # Escape HTML in the (semi-trusted) report BEFORE markdown so any payload
    # captured from a scanned device renders as text, never executes.
    safe = raw.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    body = markdown.markdown(safe, extensions=["fenced_code", "tables", "sane_lists"])
    return rec, body


@app.route("/report/<sid>")
@require_auth
def report_html(sid):
    rec, body = _render_report_html(sid)
    if rec is None:
        abort(404)
    return render_template("report.html", s=rec, body=body)


@app.route("/report/<sid>.pdf")
@require_auth
def report_pdf(sid):
    rec, body = _render_report_html(sid)
    if rec is None:
        abort(404)
    doc = """<!doctype html><html><head><meta charset="utf-8"><style>
      body{font:12px/1.5 -apple-system,Segoe UI,sans-serif;color:#111;margin:2.2cm 2cm}
      h1,h2,h3{color:#0b2c3d} h1{border-bottom:2px solid #0b2c3d;padding-bottom:4px}
      code,pre{font-family:ui-monospace,Menlo,monospace} pre{background:#f4f6f8;padding:10px;border-radius:6px;white-space:pre-wrap;word-break:break-word}
      table{border-collapse:collapse;width:100%%} th,td{border:1px solid #ccd;padding:5px 8px;text-align:left;font-size:11px}
      .meta{color:#556;font-size:10px;margin-bottom:14px}
    </style></head><body>
    <div class="meta">AP Testbed scan %s &middot; device %s &middot; %s &rarr; %s</div>%s
    </body></html>""" % (
        _html.escape(rec.get("id", "")), _html.escape(rec.get("mac", "")),
        _html.escape(rec.get("ip", "")), _html.escape(rec.get("started", "")), body)
    try:
        pdf = _html_to_pdf(doc)
    except Exception as e:
        return Response("PDF generation failed: %s" % e, 500, mimetype="text/plain")
    resp = make_response(pdf)
    resp.headers["Content-Type"] = "application/pdf"
    resp.headers["Content-Disposition"] = 'inline; filename="scan-%s.pdf"' % rec.get("id", "report")
    return resp


@app.route("/settings")
@require_auth
def settings():
    return render_template("settings.html", cfg=store.load_config(), st=ap_status(),
                           msg=request.args.get("msg", ""))


@app.route("/settings/ssid", methods=["POST"])
@require_auth
def settings_ssid():
    require_csrf()
    ssid = (request.form.get("ssid", "") or "").strip()
    if not store.valid_ssid(ssid):
        return redirect(url_for("settings", msg="invalid SSID (1-32 chars: letters, digits, space . _ -)"))
    cfg = store.load_config(); cfg["ssid"] = ssid; store.save_config(cfg)
    apply_ssid_restart()
    return redirect(url_for("settings", msg="SSID saved" + (" & applied" if unit_active("ap-testbed-hostapd.service") else " (applies on next dongle plug)")))


@app.route("/settings/arm", methods=["POST"])
@require_auth
def settings_arm():
    require_csrf()
    cfg = store.load_config()
    cfg["armed"] = (request.form.get("armed") == "1")
    store.save_config(cfg)
    return redirect(url_for("settings", msg="armed=%s" % cfg["armed"]))


@app.route("/settings/egress", methods=["POST"])
@require_auth
def settings_egress():
    require_csrf()
    cfg = store.load_config()
    cfg["egress"] = (request.form.get("egress") == "1")
    store.save_config(cfg)
    if unit_active("ap-testbed-hostapd.service"):
        apply_target_restart()
        note = " & applied (AP restarted)"
    else:
        note = " (applies on next dongle plug)"
    return redirect(url_for("settings", msg="egress=%s%s" % (cfg["egress"], note)))


@app.route("/settings/auto_abort", methods=["POST"])
@require_auth
def settings_auto_abort():
    require_csrf()
    cfg = store.load_config()
    cfg["auto_abort"] = (request.form.get("auto_abort") == "1")
    store.save_config(cfg)
    return redirect(url_for("settings", msg="auto-abort=%s" % cfg["auto_abort"]))


@app.route("/hotpot")
@require_auth
def hotpot():
    """Adversarial deception layer: status, live hostile-recon feed, per-source
    rollup, and the deployed honeytokens. Read-only view — arming is in Settings
    (mirrored here as a toggle for convenience)."""
    events = store.list_hotpot_events()
    rollup = {}
    for e in events:
        src = e.get("src", "?")
        r = rollup.setdefault(src, {"src": src, "events": 0, "creds": 0, "loot": 0,
                                    "trips": 0, "probes": 0, "last": ""})
        r["events"] += 1
        t = e.get("type", "")
        if   t == "cred_attempt": r["creds"] += 1
        elif t == "loot_pull":    r["loot"] += 1
        elif t == "token_trip":   r["trips"] += 1
        elif t == "probe":        r["probes"] += 1
        if e.get("ts", "") > r["last"]:
            r["last"] = e.get("ts", "")
    rollup = sorted(rollup.values(), key=lambda r: r["last"], reverse=True)
    return render_template("hotpot.html", cfg=store.load_config(), st=ap_status(),
                           events=events[:200], rollup=rollup,
                           tokens=store.load_tokens(), backends=store.TOKEN_BACKENDS,
                           hotpot_up=unit_active("ap-testbed-hotpot.service"),
                           msg=request.args.get("msg", ""))


@app.route("/settings/deception", methods=["POST"])
@require_auth
def settings_deception():
    require_csrf()
    cfg = store.load_config()
    cfg["deception"] = (request.form.get("deception") == "1")
    store.save_config(cfg)
    if unit_active("ap-testbed-hostapd.service"):
        hotpot_restart()
        note = " & applied (AP up)"
    else:
        note = " (starts on next dongle plug)"
    return redirect(url_for("hotpot", msg="deception=%s%s" % (cfg["deception"], note)))


@app.route("/settings/token_backend", methods=["POST"])
@require_auth
def settings_token_backend():
    require_csrf()
    b = (request.form.get("token_backend", "") or "").strip()
    if b not in store.TOKEN_BACKENDS:
        return redirect(url_for("hotpot", msg="invalid token backend"))
    cfg = store.load_config(); cfg["token_backend"] = b; store.save_config(cfg)
    return redirect(url_for("hotpot", msg="token backend = %s — re-seed to apply "
                            "(hotpot/seed-tokens.py, or /hotpot-maintain rotate)" % b))


@app.route("/settings/halt", methods=["POST"])
@require_auth
def settings_halt():
    require_csrf()
    if request.form.get("halt") == "1":
        open(HALT, "w").write("halted via admin\n")
    else:
        try: os.remove(HALT)
        except FileNotFoundError: pass
    return redirect(url_for("settings", msg="kill-switch updated"))


if __name__ == "__main__":
    app.run(host=BIND, port=PORT, debug=False, use_reloader=False)
