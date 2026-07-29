#!/usr/bin/env python3
"""
wifi-failsafe: Monitor WiFi connectivity and fall back to a secure AP + captive portal.

Flow:
  1. Every CHECK_INTERVAL seconds, verify wlan0 is connected.
  2. If disconnected for FALLBACK_TIMEOUT seconds, activate AP hotspot + start portal.
  3. Portal lets you scan, select, and connect to a new network.
  4. On successful connection, AP tears down automatically.
  5. On failed connection, AP restores and portal shows the error.
"""

import os
import re
import json
import time
import signal
import logging
import secrets
import subprocess
import threading
from pathlib import Path
from flask import Flask, render_template, request, jsonify

# ── Configuration ──────────────────────────────────────────────────────────────

CHECK_INTERVAL   = 15       # seconds between connectivity checks
FALLBACK_TIMEOUT = 45       # seconds without connection before activating AP
PORTAL_PORT      = 80       # must be 80 for captive portal detection; use 8080 if not root
AP_IFACE         = "wlan0"
AP_CON_NAME      = "wifi-failsafe-hotspot"
STATE_FILE       = Path(__file__).parent / ".state.json"

# ── Helpers (defined before State so they're available at instantiation) ───────

def _run(cmd, **kw):
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    kw.setdefault("timeout", 30)
    return subprocess.run(cmd, **kw)

def _get_mac():
    try:
        return Path(f"/sys/class/net/{AP_IFACE}/address").read_text().strip().replace(":", "")
    except Exception:
        return ""

# ── State ──────────────────────────────────────────────────────────────────────

class State:
    def __init__(self):
        self._lock = threading.Lock()
        self._data = self._load()

    def _load(self):
        if STATE_FILE.exists():
            try:
                return json.loads(STATE_FILE.read_text())
            except Exception:
                pass
        # First-run defaults
        mac = _get_mac()
        suffix = mac[-4:] if mac else secrets.token_hex(2)
        pwd = secrets.token_urlsafe(12)
        data = {"ap_ssid": f"Pi5-Setup-{suffix}", "ap_password": pwd, "mode": "client"}
        self._save(data)
        return data

    def _save(self, data=None):
        if data is None:
            data = self._data
        STATE_FILE.write_text(json.dumps(data, indent=2))

    def get(self, key, default=None):
        with self._lock:
            return self._data.get(key, default)

    def set(self, key, value):
        with self._lock:
            self._data[key] = value
            self._save()

state = State()
connect_status = {"state": "idle", "message": ""}   # shared across threads (lock not needed for simple str)

# ── Network helpers ────────────────────────────────────────────────────────────

def is_connected():
    """Return True if wlan0 has an active IP (i.e., is a connected client)."""
    r = _run(["nmcli", "-t", "-f", "DEVICE,STATE", "device"])
    for line in r.stdout.splitlines():
        if line.startswith(f"{AP_IFACE}:connected"):
            # Exclude the case where we ourselves are the AP
            r2 = _run(["nmcli", "-t", "-f", "NAME", "connection", "show", "--active"])
            if AP_CON_NAME in r2.stdout:
                return False   # we're the AP, not a client
            return True
    return False

def scan_networks():
    """Return list of dicts with ssid, signal, secured."""
    _run(["nmcli", "device", "wifi", "rescan"], timeout=10)
    time.sleep(2)
    r = _run(["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list"])
    seen, nets = set(), []
    for line in r.stdout.splitlines():
        parts = line.split(":", 2)
        if len(parts) < 3:
            continue
        ssid, signal, security = parts[0].strip(), parts[1].strip(), parts[2].strip()
        if not ssid or ssid == state.get("ap_ssid") or ssid in seen:
            continue
        seen.add(ssid)
        nets.append({
            "ssid": ssid,
            "signal": int(signal) if signal.isdigit() else 0,
            "secured": bool(security and security != "--"),
        })
    nets.sort(key=lambda n: n["signal"], reverse=True)
    return nets

def activate_ap():
    """Bring up the NM hotspot."""
    ssid = state.get("ap_ssid")
    pwd  = state.get("ap_password")
    logging.info("Activating AP: %s", ssid)
    # Delete stale profile if it exists
    _run(["nmcli", "connection", "delete", AP_CON_NAME])
    r = _run([
        "nmcli", "device", "wifi", "hotspot",
        "ifname", AP_IFACE,
        "con-name", AP_CON_NAME,
        "ssid", ssid,
        "password", pwd,
    ], timeout=20)
    if r.returncode != 0:
        logging.error("AP activate failed: %s", r.stderr)
        return False
    state.set("mode", "ap")
    logging.info("AP active — connect to '%s' (pw: %s)", ssid, pwd)
    return True

def deactivate_ap():
    """Tear down the AP hotspot."""
    logging.info("Deactivating AP")
    _run(["nmcli", "connection", "delete", AP_CON_NAME])
    state.set("mode", "client")

def connect_to_network(ssid, password):
    """
    Background: tear down AP, attempt connection, restore AP on failure.
    Updates connect_status dict.
    """
    global connect_status
    connect_status = {"state": "connecting", "message": f"Connecting to {ssid}…"}
    deactivate_ap()
    time.sleep(2)

    cmd = ["nmcli", "device", "wifi", "connect", ssid]
    if password:
        cmd += ["password", password]
    r = _run(cmd, timeout=30)

    if r.returncode == 0 and is_connected():
        connect_status = {"state": "success", "message": f"Connected to {ssid}"}
        logging.info("Connected to %s — AP mode deactivated", ssid)
        # Monitor loop will notice we're connected and stop the portal
    else:
        err = r.stderr.strip() or "Connection failed"
        connect_status = {"state": "error", "message": err}
        logging.warning("Failed to connect to %s: %s", ssid, err)
        activate_ap()

# ── Flask portal ───────────────────────────────────────────────────────────────

app = Flask(__name__, template_folder="templates", static_folder="static")
app.logger.disabled = True
log = logging.getLogger("werkzeug")
log.setLevel(logging.ERROR)

# Captive portal detection — redirect Apple/Android/Windows probes to the portal
CAPTIVE_HOSTS = {
    "captive.apple.com", "www.apple.com",
    "connectivitycheck.gstatic.com", "clients3.google.com",
    "www.msftconnecttest.com", "www.msftncsi.com",
}

@app.before_request
def captive_redirect():
    host = request.host.split(":")[0]
    if host in CAPTIVE_HOSTS:
        from flask import redirect
        return redirect(f"http://10.42.0.1:{PORTAL_PORT}/", 302)

@app.route("/")
def index():
    return render_template("index.html",
        ssid=state.get("ap_ssid"),
        password=state.get("ap_password"),
    )

@app.route("/api/scan")
def api_scan():
    return jsonify(scan_networks())

@app.route("/api/status")
def api_status():
    return jsonify({
        "connect": connect_status,
        "connected": is_connected(),
        "mode": state.get("mode"),
    })

@app.route("/api/connect", methods=["POST"])
def api_connect():
    data = request.get_json(force=True)
    ssid = data.get("ssid", "").strip()
    pwd  = data.get("password", "").strip()
    if not ssid:
        return jsonify({"error": "SSID required"}), 400
    threading.Thread(target=connect_to_network, args=(ssid, pwd), daemon=True).start()
    return jsonify({"ok": True})

@app.route("/api/ap-info")
def api_ap_info():
    return jsonify({"ssid": state.get("ap_ssid"), "password": state.get("ap_password")})

# Handle Apple captive portal detection endpoints
@app.route("/hotspot-detect.html")
@app.route("/library/test/success.html")
def apple_success():
    return "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"

@app.route("/generate_204")
def google_204():
    from flask import redirect
    return redirect(f"http://10.42.0.1:{PORTAL_PORT}/", 302)

# ── Monitor loop ───────────────────────────────────────────────────────────────

portal_thread = None
portal_running = False

# Bind the failsafe portal to its OWN hotspot IP, not 0.0.0.0. This keeps it off
# every other interface (incl. wlan0's client traffic) and, crucially, avoids a
# :80 collision with the ap-testbed consent portal (which binds 10.66.66.1:80)
# when the MT7612U dongle is plugged in. activate_ap() has already brought up
# 10.42.0.1 by the time this runs. Matches the 10.42.0.1 captive-redirect targets.
FAILSAFE_BIND = "10.42.0.1"

def run_portal():
    global portal_running
    portal_running = True
    app.run(host=FAILSAFE_BIND, port=PORTAL_PORT, debug=False, use_reloader=False)
    portal_running = False

def start_portal():
    global portal_thread, portal_running
    if portal_running:
        return
    portal_thread = threading.Thread(target=run_portal, daemon=True)
    portal_thread.start()
    logging.info("Portal started on port %d", PORTAL_PORT)

def monitor():
    disconnected_since = None
    ap_active = False

    logging.info("Monitor started (check every %ds, fallback after %ds)",
                 CHECK_INTERVAL, FALLBACK_TIMEOUT)

    while True:
        connected = is_connected()

        if connected:
            if ap_active:
                logging.info("Reconnected — AP not needed")
                # Portal will wind down; AP already deactivated by connect_to_network
                ap_active = False
            disconnected_since = None
        else:
            if disconnected_since is None:
                disconnected_since = time.time()
                logging.info("Lost connectivity — will activate AP in %ds", FALLBACK_TIMEOUT)

            elapsed = time.time() - disconnected_since
            if elapsed >= FALLBACK_TIMEOUT and not ap_active:
                if activate_ap():
                    ap_active = True
                    start_portal()

        time.sleep(CHECK_INTERVAL)

# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [wifi-failsafe] %(levelname)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    def _sig(sig, frame):
        logging.info("Shutting down")
        deactivate_ap()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, _sig)
    signal.signal(signal.SIGINT, _sig)

    logging.info("AP SSID: %s  Password: %s", state.get("ap_ssid"), state.get("ap_password"))
    monitor()
