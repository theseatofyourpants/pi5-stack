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


# ---- routes ----------------------------------------------------------------
@app.route("/")
@require_auth
def dashboard():
    scans = store.list_scans()
    running = [s for s in scans if s.get("status") == "running"]
    return render_template("dashboard.html", st=ap_status(),
                           n_devices=len(store.load_devices()),
                           n_scans=len(scans), running=running,
                           recent=scans[:8])


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
