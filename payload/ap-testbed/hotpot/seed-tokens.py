#!/usr/bin/env python3
"""Seed the hot-pot's honeytokens and bait files.

Reads the token backend from the shared store (config.token_backend) and lays down
instrumented bait into the SMB share and the fake-admin "config backup", then
records every token in the registry (state/hotpot-tokens.json).

  local        — mint unique ids; beacons point at OUR collector
                 (http://10.66.66.1:8686/t/<id>). Fully automatic. Catches trips
                 while the client can still reach the AP + server-side loot pulls.
  canarytokens — embed operator-minted canarytokens.org URLs (open-anywhere
                 beacons, incl. Office/PDF/AWS-key). Provide them in
                 state/canarytokens.json as [{"name","url","kind"}]; this script
                 embeds those. (canarytokens are minted on their site / API — we
                 don't mint them here.)

Run:  python3 ~/ap-testbed/hotpot/seed-tokens.py [--rotate]
Nothing here runs on a prober; tokens are passive phone-home telemetry only.
"""
import json, os, sys, time, uuid

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(BASE, "lib"))
import store  # noqa: E402

HOTPOT = os.path.join(BASE, "hotpot")
SHARE = os.path.join(HOTPOT, "smb", "share")
TOKENS = os.path.join(HOTPOT, "tokens")
COLLECTOR = "http://10.66.66.1:8686/t"          # local beacon base (AP gateway)
CANARY_INPUT = os.path.join(BASE, "state", "canarytokens.json")


def _w(path, data, mode="w"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, mode) as f:
        f.write(data)


def _nid():
    return uuid.uuid4().hex[:16]


def seed_local():
    reg = []
    # 1) HTML credentials file with an <img> beacon (fires if opened in a browser)
    tid = _nid(); beacon = "%s/%s.png" % (COLLECTOR, tid)
    _w(os.path.join(SHARE, "IT-credentials.html"),
       "<!doctype html><html><head><meta charset=utf-8><title>IT Credentials</title></head>"
       "<body><h2>IT / Infrastructure — credentials</h2>"
       "<p>vCenter admin: administrator@vsphere.local / (see password manager)</p>"
       "<p>Backup NAS: root / Backup!2023</p>"
       "<img src=\"%s\" width=1 height=1 alt=\"\"></body></html>" % beacon)
    reg.append({"id": tid, "file": "IT-credentials.html", "kind": "html-img",
                "backend": "local", "beacon": beacon,
                "minted": time.strftime("%Y-%m-%dT%H:%M:%S"), "tripped": None})
    # 2) Windows .url shortcut -> opens the beacon in a browser on double-click
    tid = _nid(); beacon = "%s/%s" % (COLLECTOR, tid)
    _w(os.path.join(SHARE, "Company Portal.url"),
       "[InternetShortcut]\nURL=%s\nIconIndex=0\n" % beacon)
    reg.append({"id": tid, "file": "Company Portal.url", "kind": "url-shortcut",
                "backend": "local", "beacon": beacon,
                "minted": time.strftime("%Y-%m-%dT%H:%M:%S"), "tripped": None})
    # 3) Fake AWS credentials — plain bait in local mode (no auto-beacon; local
    #    can't detect key *use*. Switch to canarytokens for a real AWS-key canary).
    _w(os.path.join(SHARE, "aws_credentials"),
       "[default]\naws_access_key_id = AKIAIOSFODNN7EXAMPLE\n"
       "aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY\nregion = us-east-1\n")
    reg.append({"id": "aws-bait", "file": "aws_credentials", "kind": "aws-bait-local",
                "backend": "local", "beacon": None,
                "minted": time.strftime("%Y-%m-%dT%H:%M:%S"), "tripped": None,
                "note": "plain bait; use canarytokens backend for a live AWS-key canary"})
    # 4) fake-admin "config backup" — the pull itself is logged server-side; embed a
    #    beacon comment too (harmless if opened in a browser as text).
    tid = _nid(); beacon = "%s/%s.png" % (COLLECTOR, tid)
    _w(os.path.join(TOKENS, "router-config-backup.cfg"),
       "# RT-AX88U configuration backup\n# fw 3.0.0.4\nadmin_user=admin\n"
       "admin_pass_hash=$1$Fx9$4bC1exampleHASH.\nwan_pppoe_user=isp12345\n"
       "wan_pppoe_pass=hunter2\n<!-- <img src=\"%s\"> -->\n" % beacon)
    reg.append({"id": tid, "file": "router-config-backup.cfg", "kind": "admin-backup",
                "backend": "local", "beacon": beacon,
                "minted": time.strftime("%Y-%m-%dT%H:%M:%S"), "tripped": None})
    # a little flavor so the share looks lived-in
    _w(os.path.join(SHARE, "README.txt"),
       "IT share. Do NOT move files. Nightly backup 02:00. Contact it@corp.local\n")
    return reg


def seed_canarytokens():
    if not os.path.exists(CANARY_INPUT):
        print("[!] token_backend=canarytokens but %s is missing." % CANARY_INPUT)
        print("    Mint tokens at https://canarytokens.org (or via your Canary")
        print("    console/API), then write them as a JSON array, e.g.:")
        print('    [{"name":"IT-credentials.docx","url":"https://canarytokens.com/…/submit.aspx","kind":"docx"},')
        print('     {"name":"aws_credentials","url":"","kind":"aws-key","aws":{"access_key":"…","secret":"…"}}]')
        sys.exit(2)
    items = json.load(open(CANARY_INPUT))
    reg = []
    for it in items:
        name = it.get("name", "token"); url = it.get("url", ""); kind = it.get("kind", "canary")
        tid = _nid()
        if kind == "aws-key" and it.get("aws"):
            aws = it["aws"]
            _w(os.path.join(SHARE, name or "aws_credentials"),
               "[default]\naws_access_key_id = %s\naws_secret_access_key = %s\nregion = us-east-1\n"
               % (aws.get("access_key", ""), aws.get("secret", "")))
        elif name.endswith(".url"):
            _w(os.path.join(SHARE, name), "[InternetShortcut]\nURL=%s\nIconIndex=0\n" % url)
        elif name.endswith((".html", ".htm")):
            _w(os.path.join(SHARE, name),
               "<!doctype html><html><body><img src=\"%s\"></body></html>" % url)
        else:
            # binary Office/PDF token: the operator drops the downloaded token file
            # into hotpot/tokens/<name>; we just register it and copy if present.
            src = os.path.join(TOKENS, name)
            if not os.path.exists(src):
                print("[!] expected canarytoken file at %s (download it there) — registering anyway" % src)
            else:
                _w(os.path.join(SHARE, name), open(src, "rb").read(), mode="wb")
        reg.append({"id": tid, "file": name, "kind": "canary-" + kind, "backend": "canarytokens",
                    "beacon": url, "minted": time.strftime("%Y-%m-%dT%H:%M:%S"), "tripped": None})
    return reg


def main():
    os.makedirs(SHARE, exist_ok=True); os.makedirs(TOKENS, exist_ok=True)
    backend = store.token_backend()
    print("[*] seeding hot-pot honeytokens — backend = %s" % backend)
    reg = seed_canarytokens() if backend == "canarytokens" else seed_local()
    store.save_tokens(reg)
    print("[*] wrote %d tokens -> %s" % (len(reg), store.HOTPOT_TOKENS))
    print("[*] SMB share seeded -> %s" % SHARE)
    for t in reg:
        print("      - %-28s %-14s %s" % (t["file"], t["kind"], t.get("beacon") or ""))


if __name__ == "__main__":
    main()
