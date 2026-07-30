#!/usr/bin/env python3
"""Local honeytoken collector for the hot-pot (token_backend = local).

A honeytoken file (HTML/img beacon, .url shortcut, etc.) fetches
http://10.66.66.1:8686/t/<token-id> when opened. This endpoint records that trip
— token id, source IP, user-agent, time — as a hostile-recon event, then returns a
1x1 GIF so an <img> beacon renders cleanly. It is PASSIVE telemetry: it observes
that our own file was opened. It sends nothing that executes on the opener.

Note: this catches trips from clients that can still reach 10.66.66.1 (i.e. while
on/near the AP). For beacons that fire from anywhere after the file is exfiltrated,
use token_backend = canarytokens (public collector). See the design note.
"""
import json, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EVENTS = "/logs/events.jsonl"
PORT = 8686
# smallest valid transparent GIF
PIXEL = (b"GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!"
         b"\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;")


def log_event(rec):
    try:
        rec = dict(rec); rec.setdefault("ts", time.strftime("%Y-%m-%dT%H:%M:%S"))
        rec.setdefault("service", "collector")
        with open(EVENTS, "a") as f:
            f.write(json.dumps(rec) + "\n")
    except Exception:
        pass


class H(BaseHTTPRequestHandler):
    server_version = "nginx"
    def _client(self):
        xff = self.headers.get("X-Forwarded-For", "")
        return xff.split(",")[0].strip() if xff else self.client_address[0]

    def do_GET(self):
        if self.path.startswith("/t/"):
            tid = self.path[3:].split("?")[0].split("/")[0]
            for ext in (".png", ".gif", ".jpg", ".ico"):
                if tid.endswith(ext):
                    tid = tid[:-len(ext)]
            log_event({"type": "token_trip", "token": tid, "src": self._client(),
                       "ua": self.headers.get("User-Agent", ""),
                       "referer": self.headers.get("Referer", "")})
        self.send_response(200)
        self.send_header("Content-Type", "image/gif")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(PIXEL)))
        self.end_headers(); self.wfile.write(PIXEL)

    def log_message(self, *a):
        return


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
