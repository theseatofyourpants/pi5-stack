#!/usr/bin/env bash
# setup-recon-ng.sh — first-run setup for recon-ng: install the curated module set
# and load API keys from the stores the stack already keeps.
#
# recon-ng ships with NO modules installed; a bare `recon-ng` is inert. Modules come
# from its marketplace at runtime, so this has to happen after apt, not from it.
#
# SECURITY: this script writes API keys into ~/.recon-ng/keys.db. It never echoes a
# key value. Do NOT add `keys list` for debugging -- recon-ng prints keys in FULL,
# unmasked, which will leak them into any log or transcript that captures stdout.
# Use `ls -l ~/.recon-ng/keys.db` or the count check at the bottom instead.
set -uo pipefail

WS="${RECON_NG_WORKSPACE:-stack}"
RC="$(mktemp)"; trap 'rm -f "$RC"' EXIT

# Curated set. Verified working on 2026-08-21 unless noted; recon-ng modules are
# mostly 2020-era and several upstream data sources have since died, so this list is
# empirical rather than aspirational.
MODULES=(
  recon/domains-hosts/hackertarget              # verified: returns hosts
  recon/domains-hosts/certificate_transparency  # crt.sh; slow, needs TIMEOUT raised
  recon/hosts-hosts/resolve
  recon/domains-contacts/whois_pocs
  recon/profiles-profiles/profiler              # username -> profiles (overlaps sherlock)
  recon/domains-hosts/threatcrowd               # upstream may be dead; harmless if so
  discovery/info_disclosure/interesting_files
  recon/domains-hosts/shodan_hostname           # needs shodan_api
  recon/hosts-ports/shodan_ip                   # needs shodan_api
)

{
  for m in "${MODULES[@]}"; do echo "marketplace install $m"; done

  # Keys, sourced from where the stack already stores them. Emitted into the resource
  # file (mode 0600 via mktemp) rather than the command line, so they never appear in
  # this process's argv or in `ps` output.
  SHODAN_KEY="$(cat "$HOME/.config/shodan/api_key" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$SHODAN_KEY" ] && echo "keys add shodan_api $SHODAN_KEY"

  VT_KEY="$(python3 - <<'PY' 2>/dev/null
import json, os
out = ''
try:
    d = json.load(open(os.path.expanduser('~/.claude.json')))
except Exception:
    d = {}
def walk(o):
    global out
    if isinstance(o, dict):
        env = o.get('env')
        if isinstance(env, dict) and env.get('VIRUSTOTAL_API_KEY'):
            out = env['VIRUSTOTAL_API_KEY']
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(d)
print(out)
PY
)"
  [ -n "$VT_KEY" ] && echo "keys add virustotal_api $VT_KEY"

  echo exit
} > "$RC"
chmod 0600 "$RC"

timeout 300 recon-ng --no-analytics --no-version -w "$WS" -r "$RC" >/tmp/recon-ng-setup.log 2>&1

# `grep -c` PRINTS 0 and RETURNS 1 on no-match, so `|| echo 0` emits a second 0.
# Use `|| true` and keep one value. And count keys from the db, not the log:
# recon-ng prints no confirmation line when a key is stored.
INSTALLED="$(grep -c 'Module installed' /tmp/recon-ng-setup.log 2>/dev/null || true)"
INSTALLED="${INSTALLED:-0}"
KEYCOUNT="$(python3 - <<'PYK' 2>/dev/null || echo 0
import sqlite3, os
try:
    c = sqlite3.connect(os.path.expanduser('~/.recon-ng/keys.db'))
    # count only; NEVER select the value column into stdout
    print(c.execute('select count(*) from keys where value is not null').fetchone()[0])
except Exception:
    print(0)
PYK
)"
echo "  recon-ng: ${INSTALLED} module(s) installed, ${KEYCOUNT} key(s) loaded into workspace '${WS}'"
grep -iE '^\[!\]|Invalid module' /tmp/recon-ng-setup.log 2>/dev/null | sed 's/^/    /' | head -5
rm -f /tmp/recon-ng-setup.log
