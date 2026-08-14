#!/usr/bin/env bash
# layers/00-core.sh — base system foundation: apt packages, Go SDK, Rust, python
# libs, tool PATH. Idempotent. (No ipset — the AP testbed uses stock `-m mac`.)
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"
source "$STACK_ROOT/versions.env" 2>/dev/null || true

log "apt: base packages…"
as_root apt-get update -qq
as_root apt-get install -y \
  git curl wget rsync jq ca-certificates build-essential \
  cmake pkg-config libpq-dev \
  python3 python3-pip python3-venv python3-dev pipx \
  python3-flask python3-markdown \
  hostapd dnsmasq iptables nmap \
  chromium network-manager
ok "apt packages installed"
as_root systemctl unmask hostapd 2>/dev/null || true   # fresh installs mask it

# Wi-Fi dongle firmware (MT7612U / mt76) for the AP-testbed radio — needed on the Pi
# and in a VM when the dongle is passed through. Best-effort: non-fatal if the
# non-free firmware pkg isn't available on this host.
as_root apt-get install -y firmware-misc-nonfree 2>/dev/null \
  || warn "firmware-misc-nonfree not installed — MT7612U dongle may need it for AP mode"

# --- Go SDK (pinned) -> ~/go-sdk ---
GO_VER="${GO_VERSION:-1.26.5}"
if ! "$HOME/go-sdk/bin/go" version 2>/dev/null | grep -q "go${GO_VER}"; then
  log "installing Go ${GO_VER} -> ~/go-sdk"
  tmp="$(mktemp -d)"
  curl -fsSL "https://go.dev/dl/go${GO_VER}.linux-${ARCH}.tar.gz" -o "$tmp/go.tgz"
  rm -rf "$HOME/go-sdk"; mkdir -p "$HOME/go-sdk"
  tar -C "$tmp" -xzf "$tmp/go.tgz"
  mv "$tmp/go/"* "$HOME/go-sdk/"
  rm -rf "$tmp"
fi
verify "go ${GO_VER}" "$HOME/go-sdk/bin/go" version

# --- Rust / cargo (needed by the x8 web tool) ---
if [ ! -x "$HOME/.cargo/bin/cargo" ] && ! need_cmd cargo; then
  log "installing Rust (rustup, non-interactive)…"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi
verify "cargo present" bash -lc 'source $HOME/.cargo/env 2>/dev/null; cargo --version'

# --- pipx + weasyprint (PDF fallback; chromium is primary, so best-effort) ---
pipx ensurepath >/dev/null 2>&1 || true
pip install --user --break-system-packages weasyprint >/dev/null 2>&1 \
  || warn "weasyprint not installed — chromium is the primary PDF path, this is fine"

# --- tool PATH (idempotent) ---
mkdir -p "$HOME/go/bin" "$HOME/.local/bin"
PATH_LINE='export PATH="$HOME/go/bin:$HOME/go-sdk/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"'
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  grep -qF '$HOME/go/bin:$HOME/go-sdk/bin' "$rc" 2>/dev/null || echo "$PATH_LINE" >> "$rc"
done

# --- tailscale (daemon only; `tailscale up` is a manual step you run when needed) ---
if ! need_cmd tailscale; then
  log "installing tailscale…"
  curl -fsSL https://tailscale.com/install.sh | as_root sh || warn "tailscale install failed (non-fatal)"
fi

# --- verify ---
verify "hostapd"  command -v hostapd
verify "dnsmasq"  command -v dnsmasq
verify "nmap"     command -v nmap
verify "chromium" bash -lc 'command -v chromium || command -v chromium-browser'
verify "python: flask"    python3 -c "import flask"
verify "python: markdown" python3 -c "import markdown"
ok "00-core done"
