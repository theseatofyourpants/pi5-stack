#!/usr/bin/env python3
"""Shared state store for the AP testbed.

One source of truth for: config (SSID/channel/armed), the admin-managed device
allowlist, the consent ledger, and scan records. Imported by the admin Flask app
AND run as a CLI by the shell scripts (trigger-scan.sh / watcher.sh) so both sides
agree. Stdlib only.
"""
import json, os, re, sys, time, tempfile, glob

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(BASE, "state")
LOGS = os.path.join(BASE, "logs")
CONFIG = os.path.join(STATE, "config.json")
DEVICES = os.path.join(STATE, "devices.json")
SCANS = os.path.join(STATE, "scans")
CONSENT_LEDGER = os.path.join(LOGS, "allowlist.jsonl")
HALT = os.path.join(LOGS, "HALT")
ENGAGEMENTS = os.path.expanduser("~/engagements")

MAC_RE  = re.compile(r'^[0-9a-f]{2}(:[0-9a-f]{2}){5}$')
SSID_RE = re.compile(r'^[A-Za-z0-9 ._-]{1,32}$')
SID_RE  = re.compile(r'^[0-9]+-[0-9a-f]{12}$')

DEFAULT_CONFIG = {"ssid": "Open Security Test", "channel": 36, "country": "US",
                  "armed": True, "egress": False, "auto_abort": False}


def _atomic_write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f:
        f.write(data)
    os.replace(tmp, path)


def valid_mac(m):  return bool(MAC_RE.match((m or "").lower()))
def valid_ssid(s): return bool(SSID_RE.match(s or ""))
def valid_sid(s):  return bool(SID_RE.match(s or ""))
def valid_ip(ip):
    p = (ip or "").split(".")
    return len(p) == 4 and all(x.isdigit() and 0 <= int(x) <= 255 for x in p)


# ---- config ----------------------------------------------------------------
def load_config():
    try:
        c = json.load(open(CONFIG))
    except Exception:
        c = {}
    out = dict(DEFAULT_CONFIG); out.update(c or {}); return out

def save_config(c):
    _atomic_write(CONFIG, json.dumps(c, indent=2))

def is_armed():
    if os.path.exists(HALT):
        return False
    return bool(load_config().get("armed", True))

def is_egress():     return bool(load_config().get("egress", False))
def is_auto_abort(): return bool(load_config().get("auto_abort", False))

# ---- authorization state (allowlist ∪ this-session consents) ----------------
SESSION_AUTH = os.path.join(STATE, "session-auth")   # MACs consented this boot

def list_allowed_macs():
    return [d.get("mac") for d in load_devices() if d.get("mac")]

def is_session_auth(mac):
    mac = (mac or "").lower()
    try:
        for line in open(SESSION_AUTH):
            if line.strip().lower() == mac:
                return True
    except FileNotFoundError:
        pass
    return False

def add_session_auth(mac):
    mac = (mac or "").lower()
    if not valid_mac(mac) or is_session_auth(mac):
        return False
    os.makedirs(STATE, exist_ok=True)
    with open(SESSION_AUTH, "a") as f:
        f.write(mac + "\n")
    return True

def is_authorized(mac):
    """A device may egress / gets 'success' captive replies if it's on the managed
    allowlist OR it consented during this AP session."""
    return is_allowed(mac) or is_session_auth(mac)

def remove_session_auth(mac):
    mac = (mac or "").lower()
    try:
        keep = [l for l in open(SESSION_AUTH) if l.strip().lower() != mac]
        with open(SESSION_AUTH, "w") as f:
            f.writelines(keep)
    except FileNotFoundError:
        pass

def lease_ip_for_mac(mac):
    """Current DHCP-assigned IP for a MAC (None if it isn't connected)."""
    mac = (mac or "").lower()
    try:
        for line in open("/run/ap-testbed/dnsmasq.leases"):
            p = line.split()
            if len(p) >= 3 and p[1].lower() == mac:
                return p[2]
    except FileNotFoundError:
        pass
    return None

def clear_cooldown(mac):
    """Drop the per-MAC scan debounce so the device can be scanned again now."""
    p = os.path.join(STATE, ".last-" + (mac or "").replace(":", ""))
    try:
        os.remove(p)
    except FileNotFoundError:
        pass

def delete_scans_for_mac(mac):
    """Forget a device's scan records (json+log) so it 'acts new'. Report files in
    ~/engagements are left as the audit trail (use delete_reports_for_mac to wipe)."""
    mac = (mac or "").lower()
    try:
        files = os.listdir(SCANS)
    except FileNotFoundError:
        return
    for fn in files:
        if not fn.endswith(".json"):
            continue
        try:
            rec = json.load(open(os.path.join(SCANS, fn)))
        except Exception:
            continue
        if (rec.get("mac", "") or "").lower() == mac:
            for ext in (".json", ".log"):
                try:
                    os.remove(os.path.join(SCANS, rec.get("id", "") + ext))
                except FileNotFoundError:
                    pass

def remove_consent(mac):
    """Drop a MAC's entries from the consent ledger (as if it never consented)."""
    mac = (mac or "").lower()
    keep = []
    try:
        for line in open(CONSENT_LEDGER):
            s = line.strip()
            if not s:
                continue
            try:
                rec = json.loads(s)
            except Exception:
                keep.append(line if line.endswith("\n") else line + "\n")
                continue
            if (rec.get("mac", "") or "").lower() != mac:
                keep.append(json.dumps(rec) + "\n")
    except FileNotFoundError:
        return
    with open(CONSENT_LEDGER, "w") as f:
        f.writelines(keep)

def delete_reports_for_mac(mac):
    """Delete the device's rendered scan reports in ~/engagements (auto-<mac>-*.md)."""
    macn = (mac or "").lower().replace(":", "")
    if not macn:
        return
    for p in glob.glob(os.path.join(ENGAGEMENTS, "auto-%s-*.md" % macn)):
        try:
            os.remove(p)
        except FileNotFoundError:
            pass

def purge_device(mac):
    """Full wipe for 'revoke & wipe': consent ledger, session auth, cooldown, scan
    records+logs, and report files. Egress revoke is done by the caller (it holds
    the privileged helper)."""
    remove_session_auth(mac)
    clear_cooldown(mac)
    remove_consent(mac)
    delete_scans_for_mac(mac)
    delete_reports_for_mac(mac)


# ---- managed device allowlist ----------------------------------------------
def load_devices():
    try:
        d = json.load(open(DEVICES))
        return d if isinstance(d, list) else []
    except Exception:
        return []

def save_devices(d):
    _atomic_write(DEVICES, json.dumps(d, indent=2))

def add_device(mac, label=""):
    mac = (mac or "").lower().strip()
    if not valid_mac(mac):
        return False, "invalid MAC (expect aa:bb:cc:dd:ee:ff)"
    devs = load_devices()
    if any(x.get("mac") == mac for x in devs):
        return False, "already on the list"
    devs.append({"mac": mac, "label": (label or "").strip()[:64],
                 "added": time.strftime("%Y-%m-%dT%H:%M:%S")})
    save_devices(devs)
    return True, "added"

def remove_device(mac):
    mac = (mac or "").lower()
    devs = load_devices()
    new = [x for x in devs if x.get("mac") != mac]
    save_devices(new)
    return len(new) != len(devs)

def is_allowed(mac):
    mac = (mac or "").lower()
    return any(x.get("mac") == mac for x in load_devices())


# ---- consent ledger (append-only, written by the portal) -------------------
def list_consents(limit=300):
    out = []
    try:
        for line in open(CONSENT_LEDGER):
            line = line.strip()
            if line:
                try: out.append(json.loads(line))
                except Exception: pass
    except FileNotFoundError:
        pass
    return out[-limit:][::-1]


# ---- scan records ----------------------------------------------------------
def scan_start(sid, mac, ip, auth, report_md, pid=""):
    rec = {"id": sid, "mac": mac, "ip": ip, "auth": auth,
           "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
           "status": "running", "report_md": report_md, "pid": str(pid), "finished": None}
    _atomic_write(os.path.join(SCANS, sid + ".json"), json.dumps(rec, indent=2))

def scan_finish(sid, status):
    p = os.path.join(SCANS, sid + ".json")
    try: rec = json.load(open(p))
    except Exception: rec = {"id": sid}
    rec["status"] = status
    rec["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    _atomic_write(p, json.dumps(rec, indent=2))

def list_scans(limit=300):
    out = []
    try: files = os.listdir(SCANS)
    except FileNotFoundError: files = []
    for fn in files:
        if fn.endswith(".json"):
            try: out.append(json.load(open(os.path.join(SCANS, fn))))
            except Exception: pass
    out.sort(key=lambda r: r.get("started", ""), reverse=True)
    return out[:limit]

def get_scan(sid):
    if not valid_sid(sid):
        return None
    try: return json.load(open(os.path.join(SCANS, sid + ".json")))
    except Exception: return None

def scan_log(sid):
    if not valid_sid(sid):
        return ""
    try: return open(os.path.join(SCANS, sid + ".log")).read()
    except Exception: return ""

def _scan_pid_alive(pid):
    """True only if <pid> is a live trigger-scan process (guards against PID reuse
    by checking the cmdline). Records with no/stale pid -> not alive."""
    pid = str(pid or "").strip()
    if not pid.isdigit():
        return False
    try:
        cl = open("/proc/%s/cmdline" % pid, "rb").read().decode("utf-8", "ignore")
        return "trigger-scan" in cl
    except Exception:
        return False

def reap_stale_scans():
    """Reconcile orphaned scans: a target/dnsmasq restart kills a backgrounded scan
    without letting trigger-scan.sh write a final status, so its record stays stuck
    at 'running'. Mark any 'running' scan whose trigger-scan PID is gone as
    'interrupted'. Returns the count reaped."""
    n = 0
    for rec in list_scans():
        if rec.get("status") == "running" and not _scan_pid_alive(rec.get("pid", "")):
            scan_finish(rec.get("id", ""), "interrupted")
            n += 1
    return n


# ---- CLI (used by trigger-scan.sh / watcher.sh) ----------------------------
if __name__ == "__main__":
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if   cmd == "is-allowed":  sys.exit(0 if is_allowed(a[1]) else 1)
    elif cmd == "is-armed":    sys.exit(0 if is_armed() else 1)
    elif cmd == "is-egress":     sys.exit(0 if is_egress() else 1)
    elif cmd == "is-auto-abort": sys.exit(0 if is_auto_abort() else 1)
    elif cmd == "is-authorized": sys.exit(0 if is_authorized(a[1]) else 1)
    elif cmd == "add-session-auth": sys.exit(0 if add_session_auth(a[1]) else 1)
    elif cmd == "list-allowed-macs":
        for m in list_allowed_macs():
            print(m)
    elif cmd == "valid-mac":   sys.exit(0 if valid_mac(a[1]) else 1)
    elif cmd == "valid-ip":    sys.exit(0 if valid_ip(a[1]) else 1)
    elif cmd == "scan-start":  scan_start(a[1], a[2], a[3], a[4], a[5], a[6] if len(a) > 6 else "")
    elif cmd == "scan-finish": scan_finish(a[1], a[2])
    elif cmd == "reap-stale":  print(reap_stale_scans())
    elif cmd == "ssid":        print(load_config().get("ssid", ""))
    else: sys.exit(2)
