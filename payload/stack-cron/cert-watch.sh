#!/usr/bin/env bash
# cert-watch.sh — CT-log hygiene + certificate expiry monitor for the lab domain.
#
# Why this exists (see ~/engagements/self-osint-20260816/playbook-ct-migration.md §5):
#   1. CT hygiene: the ONLY names that may ever appear in Certificate Transparency for
#      the lab domain are the apex and the wildcard. A per-host leaf (c2., captive., …)
#      is logged publicly and permanently, and re-creates the exact exposure this whole
#      migration was undertaken to fix. Catch it same-day.
#   2. Silent renewal failure: both boxes registered with --register-unsafely-without-email,
#      so Let's Encrypt will NEVER email an expiry warning. The dns-cloudflare plugin also
#      warns that python-cloudflare 2.19.x is going away and 3.x is not call-compatible.
#      If renewal breaks, nothing tells you until the portal serves an expired cert.
#
# Deterministic on purpose — no LLM in the path. Exits non-zero on ALERT so systemd marks
# the unit failed (visible in `systemctl --failed`); wire OnFailure= for a louder signal.
set -uo pipefail

DOMAIN="${LAB_DOMAIN:-blackholeroute.com}"
# The only SANs permitted in CT for $DOMAIN. Anything else is a leak.
ALLOWED_NAMES=("$DOMAIN" "*.$DOMAIN")
# Alert when a deployed cert has fewer than this many days left. LE renews at 30 days
# remaining, so 21 means "renewal should already have happened and didn't."
EXPIRY_WARN_DAYS="${EXPIRY_WARN_DAYS:-21}"

PI_CERT="/home/tsoyp/ap-testbed/state/portal-cert.pem"
VM_SSH="${VM_SSH:-kalivm@100.90.116.22}"
VM_CERT="/home/kalivm/ap-testbed/state/portal-cert.pem"

BASE="$HOME/stack-cron"; LOGDIR="$BASE/logs"; mkdir -p "$LOGDIR"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGDIR/cert-watch-${TS}.log"
ALERT_LOG="$LOGDIR/cert-watch-ALERT.log"

ALERTS=0
WARNS=0

log()   { echo "$*" | tee -a "$LOG"; }
alert() { ALERTS=$((ALERTS+1)); echo "[ALERT] $*" | tee -a "$LOG" >> "$ALERT_LOG"; echo "[ALERT] $*"; }
warn()  { WARNS=$((WARNS+1));  log "[warn]  $*"; }
ok()    { log "[ok]    $*"; }

log "=== cert-watch @ $(date -Is) — domain: $DOMAIN ==="

# ---------------------------------------------------------------------------
# 1. CT-log hygiene: no name other than apex + wildcard may be logged.
# ---------------------------------------------------------------------------
# crt.sh is genuinely unreliable — it regularly serves a 502 nginx HTML page with a
# 200-ish response, so "did I get JSON back" must be checked explicitly rather than
# trusting the status code. Retry with backoff before giving up.
fetch_ct() {
  local attempt body
  for attempt in 1 2 3 4; do
    body="$(curl -s --max-time 45 -H 'Accept: application/json' \
            "https://crt.sh/?q=%25.${DOMAIN}&output=json" 2>/dev/null)"
    # A valid response is a JSON array. Anything else (empty, HTML error page) is a miss.
    case "${body#"${body%%[![:space:]]*}"}" in
      '['*) printf '%s' "$body"; return 0 ;;
    esac
    [ "$attempt" -lt 4 ] && sleep $(( attempt * 10 ))
  done
  return 1
}

if ! CT_JSON="$(fetch_ct)"; then
  # NOT an alert — crying wolf whenever crt.sh has a bad afternoon would train you to
  # ignore this job, which is worse than not having it.
  warn "crt.sh unavailable after 4 attempts (502/timeout) — CT check skipped this run"
else
  CT_NAMES="$(printf '%s' "$CT_JSON" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(2)
names = set()
for entry in data:
    for n in (entry.get("name_value") or "").split("\n"):
        n = n.strip().lower()
        if n:
            names.add(n)
for n in sorted(names):
    print(n)
' 2>/dev/null)"
  parse_rc=$?

  if [ "$parse_rc" -eq 2 ]; then
    warn "crt.sh returned unparseable JSON — CT check inconclusive"
  elif [ -z "$CT_NAMES" ]; then
    # Distinct from a fetch failure: crt.sh answered correctly and knows of no certs.
    ok "CT: zero certificates logged for $DOMAIN (indexing lags issuance by hours)"
  else
    UNEXPECTED=""
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      permitted=0
      for a in "${ALLOWED_NAMES[@]}"; do
        [ "$name" = "$a" ] && permitted=1 && break
      done
      [ $permitted -eq 0 ] && UNEXPECTED="${UNEXPECTED}${name} "
    done <<< "$CT_NAMES"

    if [ -n "$UNEXPECTED" ]; then
      alert "CT LEAK — unexpected name(s) logged for $DOMAIN: $UNEXPECTED"
      alert "  A per-host cert was issued. It is public and PERMANENT. Find what issued it"
      alert "  (check certbot/acme.sh on every box) and stop it before more names leak."
    else
      ok "CT clean — only apex + wildcard logged ($(printf '%s' "$CT_NAMES" | wc -l) name(s))"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 2. CAA sanity: Let's Encrypt must stay authorized or renewal fails silently.
# ---------------------------------------------------------------------------
CAA="$(dig +short CAA "$DOMAIN" @1.1.1.1 2>/dev/null)"
if [ -z "$CAA" ]; then
  warn "no CAA records on $DOMAIN (issuance unrestricted — playbook §2a not applied)"
elif printf '%s' "$CAA" | grep -q 'issuewild "letsencrypt.org"'; then
  ok "CAA authorizes letsencrypt.org for wildcards"
else
  alert "CAA does NOT authorize letsencrypt.org for issuewild — renewal WILL fail"
fi

# ---------------------------------------------------------------------------
# 3. Deployed certificate expiry, per box.
# ---------------------------------------------------------------------------
check_cert_expiry() {
  local label="$1" pem_data="$2"
  local secs=$(( EXPIRY_WARN_DAYS * 86400 ))

  if [ -z "$pem_data" ]; then
    warn "$label: certificate unavailable — skipped"
    return
  fi
  local enddate
  enddate="$(printf '%s' "$pem_data" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
  if [ -z "$enddate" ]; then
    alert "$label: certificate is unreadable / not valid PEM"
    return
  fi
  local days_left
  days_left=$(( ( $(date -d "$enddate" +%s) - $(date +%s) ) / 86400 ))

  if ! printf '%s' "$pem_data" | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then
    alert "$label: certificate has EXPIRED ($enddate)"
  elif ! printf '%s' "$pem_data" | openssl x509 -noout -checkend "$secs" >/dev/null 2>&1; then
    alert "$label: expires in ${days_left}d ($enddate) — renewal did not run. Investigate certbot."
  else
    ok "$label: valid, ${days_left}d remaining"
  fi

  # Guard the other half of the invariant: the deployed cert must be the wildcard,
  # not some per-host cert someone swapped in.
  local sans
  sans="$(printf '%s' "$pem_data" | openssl x509 -noout -ext subjectAltName 2>/dev/null \
          | tr ',' '\n' | sed -n 's/.*DNS://p' | tr -d ' ' | sort | tr '\n' ' ')"
  local expected
  expected="$(printf '%s\n' "${ALLOWED_NAMES[@]}" | sort | tr '\n' ' ')"
  if [ "$sans" != "$expected" ]; then
    alert "$label: deployed SANs are [$sans] — expected [$expected]"
  fi
}

check_cert_expiry "Pi  portal cert" "$(cat "$PI_CERT" 2>/dev/null)"

# The VM lives on the tailnet and is frequently powered off — unreachable is a warning,
# never an alert, or this job would page you every time the MacBook sleeps.
if VM_PEM="$(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
             "$VM_SSH" "cat $VM_CERT" 2>/dev/null)" && [ -n "$VM_PEM" ]; then
  check_cert_expiry "VM  portal cert" "$VM_PEM"
else
  warn "VM ($VM_SSH) unreachable — skipped (normal when the MacBook is off)"
fi

# ---------------------------------------------------------------------------
# 4. Renewal machinery is actually armed.
# ---------------------------------------------------------------------------
if systemctl is-active certbot.timer >/dev/null 2>&1; then
  ok "Pi: certbot.timer active"
else
  alert "Pi: certbot.timer is NOT active — nothing will renew"
fi

# ---------------------------------------------------------------------------
log "=== done: ${ALERTS} alert(s), ${WARNS} warning(s) ==="
ln -sfn "$LOG" "$LOGDIR/cert-watch-latest.log"
ls -1t "$LOGDIR/cert-watch-"2*.log 2>/dev/null | tail -n +21 | xargs -r rm -f

[ "$ALERTS" -gt 0 ] && exit 1
exit 0
