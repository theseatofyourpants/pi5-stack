#!/usr/bin/env bash
# secret-scan.sh — gate that fails a commit if a real secret is staged.
#
# Lives here rather than as a regex pasted inside the pi5-stack-sync skill: the
# in-doc version scanned the WHOLE diff (so it matched unchanged context lines and
# cried wolf), matched bare variable NAMES rather than values (so a harmless
# `: "${MYTHIC_PASSWORD:=}"` declaration blocked commits), and could not be tested.
# A gate nobody can test is a gate people learn to bypass.
#
# Usage:
#   tools/secret-scan.sh              scan staged changes; exit 1 if a secret is found
#   tools/secret-scan.sh --self-test  prove it catches leaks and ignores decoys
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.." || exit 2

# Every pattern must require a VALUE, not just a name. The value has to start with
# an alphanumeric, which is what excludes shell default-assignment forms like
# ${VAR:=} and ${VAR:-} as well as {{PLACEHOLDER}} tokens.
PAT='(VIRUSTOTAL|GREYNOISE)_API_KEY["'"'"']?[[:space:]]*[:=]{1,2}[[:space:]]*["'"'"']?[A-Za-z0-9]{20}'
PAT="$PAT"'|MYTHIC_PASSWORD["'"'"']?[[:space:]]*[:=]{1,2}[[:space:]]*["'"'"']?[A-Za-z0-9]'
PAT="$PAT"'|gh[pous]_[A-Za-z0-9]{20}'
PAT="$PAT"'|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY'
PAT="$PAT"'|dns_cloudflare_api_token[[:space:]]*=[[:space:]]*[A-Za-z0-9_-]{10}'

scan() { grep -E '^\+' | grep -v '^+++' | grep -nEi "$PAT"; }

if [ "${1:-}" = "--self-test" ]; then
  fail=0
  # Fixtures are SPLIT across adjacent quoted strings so this file contains no
  # literal that matches the gate. Bash concatenates them, so the values the test
  # actually scans are the real thing — but the gate does not flag its own source.
  must_catch=(
    'MYTHIC_PASS''WORD=hunter2'
    'VIRUSTOTAL_API_''KEY="abcdefghij0123456789abcd"'
    'gh''p_abcdefghij0123456789abcd'
    '    "MYTHIC_PASS''WORD": "s3cret"'
    'dns_cloudflare_api_''token = A1b2C3d4E5f6'
    '-----BEGIN OPENSSH PRIVATE ''KEY-----'
  )
  must_ignore=(
    ': "${MYTHIC_PASS''WORD:=}";                 export MYTHIC_PASSWORD'
    'require_secret VT_API_KEY        "VirusTotal API key"'
    '"apiKey": "{{VT_API_KEY}}"'
    '${GREYNOISE_API_KEY:-}'
    '# MYTHIC_PASS''WORD is read from secrets.env'
  )
  for l in "${must_catch[@]}"; do
    printf '+%s\n' "$l" | scan >/dev/null \
      && echo "  ok   caught: $l" || { echo "  FAIL missed: $l"; fail=1; }
  done
  for l in "${must_ignore[@]}"; do
    printf '+%s\n' "$l" | scan >/dev/null \
      && { echo "  FAIL false positive: $l"; fail=1; } || echo "  ok   ignored: $l"
  done
  # Context lines must never be scanned, only additions.
  printf ' %s\n' 'MYTHIC_PASS''WORD=hunter2' | scan >/dev/null \
    && { echo "  FAIL scanned an unchanged context line"; fail=1; } \
    || echo "  ok   ignores unchanged context lines"
  echo; [ $fail -eq 0 ] && echo "self-test: ALL PASS" || echo "self-test: FAILURES"
  exit $fail
fi

if git diff --cached | scan; then
  echo "ABORT: secret detected in staged changes — unstage and replace with {{PLACEHOLDER}}" >&2
  exit 1
fi
if git ls-files --cached | grep -qx 'secrets.env'; then
  echo "ABORT: secrets.env is tracked" >&2
  exit 1
fi
echo "secret-scan: clean"
exit 0
