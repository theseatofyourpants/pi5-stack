#!/usr/bin/env python3
"""Fake device admin (router/NAS) login for the hot-pot.

Serves a convincing but INERT admin login. Every credential attempt and every
"config backup" download is logged as a hostile-recon event. It never
authenticates anyone and never returns anything that runs on the client — the
"config backup" is a honeytoken file whose only power is to phone home to our own
collector when opened. Stdlib only.
"""
import json, os, time, html
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

EVENTS = "/logs/events.jsonl"
TOKENS_DIR = "/tokens"
PORT = 8080

LOGIN_PAGE = """<!doctype html><html><head><meta charset=utf-8>
<title>RT-AX88U · Administration</title>
<style>body{font:15px/1.5 -apple-system,Segoe UI,sans-serif;background:#eef1f4;margin:0}
.box{max-width:360px;margin:9vh auto;background:#fff;border-radius:10px;padding:28px 30px;box-shadow:0 6px 24px #0002}
h1{font-size:18px;color:#0b3a5b;margin:0 0 4px}.sub{color:#789;font-size:12px;margin:0 0 20px}
input{width:100%%;box-sizing:border-box;padding:9px 10px;margin:6px 0 12px;border:1px solid #ccd;border-radius:6px}
button{width:100%%;padding:10px;background:#0b6bb5;color:#fff;border:0;border-radius:6px;font-size:15px;cursor:pointer}
.err{color:#b00;font-size:13px;margin:0 0 10px}.ft{color:#9ab;font-size:11px;text-align:center;margin-top:16px}
a{color:#0b6bb5;font-size:12px}</style></head><body>
<div class=box><h1>Router Administration</h1><p class=sub>Firmware 3.0.0.4 · sign in to continue</p>
%s<form method=post action=/login>
<label>Username</label><input name=username autofocus>
<label>Password</label><input name=password type=password>
<button type=submit>Sign In</button></form>
<p class=ft>Trouble signing in? <a href=/backup>Download configuration backup</a></p></div>
</body></html>"""


def log_event(rec):
    try:
        rec = dict(rec); rec.setdefault("ts", time.strftime("%Y-%m-%dT%H:%M:%S"))
        rec.setdefault("service", "fake-admin")
        with open(EVENTS, "a") as f:
            f.write(json.dumps(rec) + "\n")
    except Exception:
        pass


class H(BaseHTTPRequestHandler):
    server_version = "Boa/0.94.14"          # a classic embedded-router banner
    def _client(self):
        xff = self.headers.get("X-Forwarded-For", "")
        return xff.split(",")[0].strip() if xff else self.client_address[0]

    def _page(self, err=""):
        body = (LOGIN_PAGE % ('<p class=err>%s</p>' % html.escape(err) if err else "")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/backup"):
            self._serve_backup(); return
        log_event({"type": "probe", "src": self._client(), "method": "GET",
                   "path": self.path, "ua": self.headers.get("User-Agent", "")})
        self._page()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(n).decode("utf-8", "ignore") if n else ""
        form = parse_qs(raw)
        u = (form.get("username", [""])[0])[:128]
        p = (form.get("password", [""])[0])[:128]
        log_event({"type": "cred_attempt", "src": self._client(), "path": self.path,
                   "username": u, "password": p, "ua": self.headers.get("User-Agent", "")})
        # never authenticate — always bounce back with an error
        self._page("Invalid username or password.")

    def _serve_backup(self):
        """Hand over the honeytoken 'config backup'. Logged as a loot pull."""
        path = os.path.join(TOKENS_DIR, "router-config-backup.cfg")
        try:
            data = open(path, "rb").read()
        except Exception:
            data = b"# configuration backup unavailable\n"
        log_event({"type": "loot_pull", "src": self._client(),
                   "file": "router-config-backup.cfg", "ua": self.headers.get("User-Agent", "")})
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", 'attachment; filename="router-config-backup.cfg"')
        self.send_header("Content-Length", str(len(data)))
        self.end_headers(); self.wfile.write(data)

    def log_message(self, *a):        # silence default stderr logging
        return


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
