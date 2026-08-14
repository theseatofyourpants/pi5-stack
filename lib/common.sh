#!/usr/bin/env bash
# common.sh — shared helpers for the pi5-stack rebuild. Sourced by bootstrap.sh
# and every layer. Provides logging, interactive prompts/stops, secret handling,
# verification, and layer-state tracking.

STACK_ROOT="${STACK_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SECRETS_FILE="$STACK_ROOT/secrets.env"
STATE_FILE="$STACK_ROOT/.bootstrap-state"
LOG_DIR="$STACK_ROOT/logs"
mkdir -p "$LOG_DIR"

if [ -t 1 ]; then
  C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_B=$'\e[36m'; C_0=$'\e[0m'; C_BOLD=$'\e[1m'
else C_R=; C_G=; C_Y=; C_B=; C_0=; C_BOLD=; fi

log(){  printf '%s[*]%s %s\n' "$C_B" "$C_0" "$*"; }
ok(){   printf '%s[ok]%s %s\n' "$C_G" "$C_0" "$*"; }
warn(){ printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
err(){  printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die(){  err "$*"; exit 1; }
hr(){   printf '%s────────────────────────────────────────────────────────────%s\n' "$C_B" "$C_0"; }

# confirm "question"  -> exit 0 if yes
confirm(){ local a; read -rp "${C_BOLD}$* [y/N]${C_0} " a; [[ "$a" =~ ^[Yy] ]]; }

# stop_for_manual "title" "line1" "line2" ...  — print instructions, wait for Enter
stop_for_manual(){
  local title="$1"; shift
  hr; printf '%s MANUAL STEP: %s%s\n' "${C_Y}${C_BOLD}" "$title" "$C_0"
  local line; for line in "$@"; do printf '   %s\n' "$line"; done
  hr; read -rp "${C_BOLD} Press Enter when done (Ctrl-C to abort) …${C_0} " _
}

# load secrets.env into the environment (if present)
load_secrets(){ if [ -f "$SECRETS_FILE" ]; then set -a; . "$SECRETS_FILE"; set +a; fi; }

# require_secret VAR "description"  — prompt if missing, offer to persist
require_secret(){
  local var="$1" desc="${2:-$1}" val; val="${!var:-}"
  [ -n "$val" ] && return 0
  hr; printf '%s Secret needed: %s%s\n   %s\n' "$C_Y" "$var" "$C_0" "$desc"
  read -rp "   value (blank to skip): " val
  if [ -z "$val" ]; then warn "$var left blank — dependent feature may not work"; return 0; fi
  export "$var=$val"
  if confirm "   save $var to secrets.env?"; then
    touch "$SECRETS_FILE"; chmod 600 "$SECRETS_FILE"
    if grep -q "^${var}=" "$SECRETS_FILE" 2>/dev/null; then
      sed -i "s|^${var}=.*|${var}=${val}|" "$SECRETS_FILE"
    else echo "${var}=${val}" >> "$SECRETS_FILE"; fi
    ok "saved $var"
  fi
}

# verify "description" cmd...  — run a check, report pass/fail (returns cmd status)
verify(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "verify: $d"; else err "verify FAILED: $d"; return 1; fi; }

# layer state
layer_is_done(){   grep -qxF "$1" "$STATE_FILE" 2>/dev/null; }
mark_layer_done(){ touch "$STATE_FILE"; layer_is_done "$1" || echo "$1" >> "$STATE_FILE"; }

need_cmd(){ command -v "$1" >/dev/null 2>&1; }
as_root(){ if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

# ── host profile + hardware capability probes ───────────────────────────────
# One repo builds two targets: the Pi (built-in radio + GPIO) and a Kali arm64 VM
# (no built-in radio, hardware attached over USB passthrough). PROFILE (pi|vm) is
# auto-detected from hardware and only tunes what 90-verify asserts; the hardware
# layers self-skip on the capability probes below regardless of PROFILE. ARCH drives
# arch-specific downloads (Go, Sliver): arm64 on the Pi AND on an Apple-Silicon VM,
# amd64 on an Intel host.
ARCH="$(dpkg --print-architecture 2>/dev/null || echo arm64)"; export ARCH

# _wifi_is_usb IFACE -> true if that wireless iface sits on the USB bus (a dongle).
_wifi_is_usb(){ case "$(readlink -f "/sys/class/net/$1/device" 2>/dev/null)" in *usb*) return 0;; *) return 1;; esac; }
# iterate wireless interfaces, calling back with each iface name
_each_wifi(){ local d i; for d in /sys/class/net/*/wireless; do [ -e "$d" ] || continue; i="$(basename "$(dirname "$d")")"; "$1" "$i" && return 0; done; return 1; }

# have_builtin_wifi -> a NON-USB wireless phy exists (the Pi's brcmfmac). This is the
# pi-vs-vm discriminator: a VM has no built-in radio.
have_builtin_wifi(){ _each_wifi _wifi_not_usb; }
_wifi_not_usb(){ ! _wifi_is_usb "$1"; }
# have_ap_dongle -> a USB wireless iface (e.g. MT7612U) is present (AP-testbed radio).
have_ap_dongle(){ _each_wifi _wifi_is_usb; }
# has_spidev -> a SPI device node exists (the e-ink HAT bus; Pi-only).
has_spidev(){ ls /dev/spidev* >/dev/null 2>&1; }

# detect_profile -> 'pi' if a built-in radio is present, else 'vm'.
detect_profile(){ if have_builtin_wifi; then echo pi; else echo vm; fi; }

# Resolve PROFILE now (honoring an explicit override); 'auto' (default) detects.
# bootstrap.sh may re-resolve after parsing --profile.
: "${PROFILE:=auto}"
[ "$PROFILE" = auto ] && PROFILE="$(detect_profile)"
export PROFILE
