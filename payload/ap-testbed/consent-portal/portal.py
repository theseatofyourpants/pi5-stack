#!/usr/bin/env python3
"""
consent-portal — the authorization gate for the AP testbed.

Captive DNS points every hostname at this server, so the moment a device opens
any page it lands here. NOTHING happens to a device until its owner explicitly
clicks "I own this device and authorize a scan." That click — not the act of
connecting — is the consent record. This is what keeps the testbed inside the
CFAA line and any conference's code of conduct.

Dependency-free (Python stdlib only). Runs unprivileged.

Files:
  logs/allowlist.jsonl   append-only consent ledger (one JSON object per grant)
  logs/portal.log        access log
"""
import http.server, socketserver, json, time, os, sys, subprocess, urllib.parse, html

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(BASE, "lib"))
import store  # shared state: is_authorized / add_session_auth
LOGS = os.path.join(BASE, "logs")
ALLOWLIST = os.path.join(LOGS, "allowlist.jsonl")
PORT = int(os.environ.get("PORTAL_PORT", "80"))  # bind :80 directly (evilportal-style).
# nat REDIRECT to a high port does NOT work reliably on this Docker host, so the
# portal owns :80. Needs CAP_NET_BIND_SERVICE (systemd) or sudo to bind <1024.
# Bind ONLY the AP interface IP (not 0.0.0.0) so we never answer on wlan0/uplink/
# tailscale and never collide with the wifi-failsafe portal on wlan0.
BIND = os.environ.get("PORTAL_BIND", "10.66.66.1")
TPL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "templates")


def mac_for_ip(ip):
    """Resolve client IP -> MAC via the neighbour table (no root needed)."""
    try:
        out = subprocess.run(["ip", "neigh", "show", ip], capture_output=True, text=True, timeout=3).stdout
        for tok in out.split():
            if ":" in tok and len(tok) == 17:
                return tok.lower()
    except Exception:
        pass
    return None


def page(name):
    with open(os.path.join(TPL, name), "r") as f:
        return f.read()


def grant_consent(ip, mac, ua):
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "ip": ip, "mac": mac,
           "user_agent": ua, "consent": True}
    os.makedirs(LOGS, exist_ok=True)
    with open(ALLOWLIST, "a") as f:
        f.write(json.dumps(rec) + "\n")
    return rec


class Handler(http.server.BaseHTTPRequestHandler):
    def _client_ip(self):
        return self.client_address[0]

    def _send(self, body, code=200, ctype="text/html; charset=utf-8"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, fmt, *args):
        os.makedirs(LOGS, exist_ok=True)
        with open(os.path.join(LOGS, "portal.log"), "a") as f:
            f.write("%s %s %s\n" % (time.strftime("%H:%M:%S"), self._client_ip(), fmt % args))

    def _splash(self, ip, mac):
        return page("splash.html").replace("{{IP}}", html.escape(ip)).replace("{{MAC}}", html.escape(mac or "unknown"))

    def _captive_success(self, host):
        # Tell the OS "you're online" (used for AUTHORIZED devices so their periodic
        # captive probes don't keep re-popping the portal).
        p = self.path
        if p in ("/generate_204", "/gen_204"):
            self.send_response(204); self.send_header("Content-Length", "0"); self.end_headers(); return
        if "msftncsi" in host or p == "/ncsi.txt":
            return self._send("Microsoft NCSI", ctype="text/plain")
        if "msftconnecttest" in host or p == "/connecttest.txt":
            return self._send("Microsoft Connect Test", ctype="text/plain")
        if "firefox" in host or p == "/success.txt":
            return self._send("success\n", ctype="text/plain")
        return self._send("<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>")

    # ---- per-device status / report page -----------------------------------
    def _status_html(self, title, body, refresh):
        meta = '<meta http-equiv="refresh" content="5">' if refresh else ''
        return """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">%s
<title>%s — Security by Black Hole Route</title>
<style>
 body{margin:0;background:#0f1216;color:#e8ecf1;font:16px/1.6 system-ui,-apple-system,sans-serif}
 .wrap{max-width:44rem;margin:0 auto;padding:22px 18px 64px}
 .brand{font-size:.9rem;font-weight:600;color:#8b95a3} .brand b{color:#ffb02e;font-weight:700}
 .tag{color:#ffb02e;font-size:.72rem;text-transform:uppercase;letter-spacing:.09em;margin-top:6px;display:block}
 h1{font-size:1.3rem;margin:.15em 0 .7em}
 pre{background:#0a0d12;border:1px solid #2a313c;border-radius:8px;padding:12px;overflow:auto;white-space:pre-wrap;word-break:break-word;font:12.5px ui-monospace,Menlo,monospace;color:#cdd6e0;max-height:60vh}
 .report{border-top:1px solid #2a313c;margin-top:18px;padding-top:6px}
 .report h1{font-size:1.15rem} .report h2{font-size:1.02rem;color:#ffb02e}
 .report table{border-collapse:collapse;width:100%%;margin:.6em 0}
 .report th,.report td{border:1px solid #2a313c;padding:5px 8px;text-align:left;font-size:13px}
 .report pre{white-space:pre-wrap} a{color:#ffb02e}
 .foot{margin-top:26px;padding-top:14px;border-top:1px solid #2a313c;font-size:.78rem;color:#8b95a3}
 .foot a{color:#ffb02e;text-decoration:none}
 .btn{display:inline-block;background:#ffb02e;color:#1a1200;font-weight:700;padding:11px 18px;border-radius:10px;text-decoration:none}
 .muted{color:#8b95a3;font-size:.88rem}
</style></head><body><div class="wrap">
 <div class="brand">Security by <b>Black Hole Route</b></div>
 <span class="tag">Open Security Test</span><h1>%s</h1>%s
 <p class="foot">🛡️ Authorized lab testing — devices on this AP only</p>
</div></body></html>""" % (meta, html.escape(title), html.escape(title), body)

    def _render_report(self, rec):
        rp = os.path.realpath(rec.get("report_md", ""))
        engroot = os.path.realpath(os.path.expanduser("~/engagements"))
        if not rp.startswith(engroot + os.sep):
            return "<p><em>Report unavailable.</em></p>"
        try:
            raw = open(rp).read()
        except Exception:
            return "<p><em>Report not ready yet.</em></p>"
        try:
            import markdown
            # escape HTML in the (semi-trusted) report before markdown -> no XSS
            safe = raw.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            return "<div class='report'>" + markdown.markdown(
                safe, extensions=["fenced_code", "tables", "sane_lists"]) + "</div>"
        except Exception:
            return "<pre>%s</pre>" % html.escape(raw)

    def _status_page(self, ip, mac):
        if not mac:
            return self._send(self._status_html("Device not recognized",
                "<p>Couldn't identify this device from the network. Reconnect to "
                "<b>Open Security Test</b> and reopen <b>http://status.test</b>.</p>", False))
        scans = [s for s in store.list_scans() if (s.get("mac", "") or "").lower() == mac.lower()]
        if not scans:
            if not store.is_armed():
                body = "<p>No scan has run for this device. Scanning is currently disabled by the operator.</p>"; refresh = True
            elif not store.is_authorized(mac):
                body = ("<p>This device hasn't been authorized yet.</p>"
                        "<p><a class='btn' href='http://%s/'>Authorize a scan &rarr;</a></p>"
                        "<p class='muted'>Or reconnect to <b>Open Security Test</b> and tap the “sign in to network” notification.</p>" % html.escape(BIND)); refresh = False
            else:
                body = "<p>Your scan is queued and should begin shortly. This page refreshes automatically.</p>"; refresh = True
            return self._send(self._status_html("Waiting for scan", body, refresh))
        s = scans[0]
        st = s.get("status"); sid = s.get("id", "")
        if st == "running":
            log = store.scan_log(sid) or "(starting…)"
            body = ("<p>Status: <b>scanning your device…</b> This page refreshes every few seconds.</p>"
                    "<pre>%s</pre>" % html.escape(log[-4000:]))
            return self._send(self._status_html("Scan in progress", body, True))
        if st == "done":
            body = "<p>Status: <b>complete</b> — your device's report is below.</p>" + self._render_report(s)
            return self._send(self._status_html("Scan complete", body, False))
        log = store.scan_log(sid) or ""
        body = "<p>Status: <b>%s</b>.</p><pre>%s</pre>" % (html.escape(st), html.escape(log[-2000:]))
        return self._send(self._status_html("Scan %s" % st, body, False))

    def do_GET(self):
        # Hybrid captive: only the OS probe domains are DNS-hijacked here. An
        # AUTHORIZED device (allowlist or consented) gets a "success" reply (clean
        # internet, no captive UI); an UNAUTHORIZED device gets the consent splash
        # so the OS captive assistant pops.
        ip = self._client_ip()
        mac = mac_for_ip(ip)
        host = self.headers.get("Host", "").lower()
        # RFC 8908 Captive-Portal API — the modern positive signal advertised via
        # DHCP option 114 (RFC 8910). Android 11+/iOS 14+ query this and act on it
        # directly, bypassing HTTP-probe interception entirely (works on carrier
        # Androids that only validate over HTTPS).
        if self.path in ("/captive-api", "/.well-known/captive-portal"):
            authorized = bool(mac and store.is_authorized(mac))
            body = json.dumps({"captive": (not authorized),
                               "user-portal-url": "http://%s/" % BIND}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/captive+json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        # Per-device status/report page (friendly local domain or /status path).
        if "status.test" in host or "report.test" in host or self.path.startswith("/status"):
            return self._status_page(ip, mac)
        probe_hosts = ("captive.apple.com", "connectivitycheck.gstatic.com",
                       "connectivitycheck.android.com", "clients3.google.com",
                       "clients4.google.com", "msftconnecttest.com", "msftncsi.com",
                       "detectportal.firefox.com", "network-test.debian.org")
        probe_paths = ("/generate_204", "/gen_204", "/hotspot-detect.html",
                       "/library/test/success.html", "/ncsi.txt", "/connecttest.txt",
                       "/success.txt", "/canonical.html")
        is_probe = any(h in host for h in probe_hosts) or self.path in probe_paths
        if is_probe:
            if mac and store.is_authorized(mac):
                return self._captive_success(host)
            # unauthorized probe -> 302 to the portal. A redirect is the strongest
            # captive signal for the Android/iOS network-check assistants (stronger
            # than a 200 body), so the "sign in to network" sheet pops reliably.
            self.send_response(302)
            self.send_header("Location", "http://%s/" % BIND)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        # any normal page (or the portal root) -> the consent splash
        self._send(self._splash(ip, mac))

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        data = urllib.parse.parse_qs(self.rfile.read(length).decode())
        ip = self._client_ip()
        mac = mac_for_ip(ip)
        if self.path == "/consent" and data.get("agree", ["0"])[0] == "1" and mac:
            rec = grant_consent(ip, mac, self.headers.get("User-Agent", ""))
            # Mark authorized for this session (captive success + egress).
            store.add_session_auth(mac)
            body = page("granted.html").replace("{{MAC}}", html.escape(mac)).replace("{{IP}}", html.escape(ip))
            self._send(body)
            print("[CONSENT] %s / %s authorized a scan of their own device" % (ip, mac))
            # Open LAN-isolated internet egress for this MAC (no-op in walled-garden
            # mode). Scoped root helper via sudoers.
            try:
                subprocess.Popen(["sudo", "-n", "/usr/local/sbin/apt-testbed-authorize", "add", mac],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                print("[WARN] could not open egress: %s" % e)
            # Fire the scan trigger (DISARMED unless armed; see trigger-scan.sh).
            try:
                subprocess.Popen([os.path.join(BASE, "trigger-scan.sh"), ip, mac],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                print("[WARN] could not launch trigger: %s" % e)
        else:
            self._send(page("splash.html").replace("{{IP}}", html.escape(ip)).replace("{{MAC}}", html.escape(mac or "unknown")), code=400)


def _ensure_cert():
    """Self-signed cert for the AP IP (RFC 8910 prefers an HTTPS captive-API URL).
    Stored in state/ (git-ignored via *.pem); generated once if missing."""
    cert = os.path.join(BASE, "state", "portal-cert.pem")
    key = os.path.join(BASE, "state", "portal-key.pem")
    if not (os.path.exists(cert) and os.path.exists(key)):
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                        "-keyout", key, "-out", cert, "-days", "3650",
                        "-subj", "/CN=%s" % BIND,
                        "-addext", "subjectAltName=IP:%s" % BIND],
                       check=True, capture_output=True)
    return cert, key


def _serve(bind, port, tls=False):
    # Threaded: each request gets its own thread so one slow/stuck client (e.g. a
    # captive probe that connects but never completes) can't wedge the whole portal
    # and stall the connection backlog. daemon_threads lets it shut down cleanly.
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    socketserver.ThreadingTCPServer.daemon_threads = True
    httpd = socketserver.ThreadingTCPServer((bind, port), Handler)
    if tls:
        import ssl
        cert, key = _ensure_cert()
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert, key)
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    httpd.serve_forever()


if __name__ == "__main__":
    os.makedirs(LOGS, exist_ok=True)
    import threading
    # HTTPS listener on :443 so option 114 can advertise an https:// captive-API URL
    # (some Android NetworkStack builds refuse to fetch a plaintext option-114 URL).
    try:
        threading.Thread(target=_serve, args=(BIND, 443, True), daemon=True).start()
        print("consent-portal TLS on %s:443" % BIND)
    except Exception as e:
        print("[WARN] HTTPS listener failed (continuing HTTP-only): %s" % e)
    print("consent-portal on %s:%d  (ledger: %s)" % (BIND, PORT, ALLOWLIST))
    _serve(BIND, PORT, False)
