#!/usr/bin/env bash
# layers/55-ctf-tools.sh — CTF / badge-hacking toolchain for the ctf-* agents & skills
# (ctf-crypto, ctf-rev, ctf-forensics, fw-triage, rf-decode, hw-bench, andxor-ctf).
# Opt-in. apt packages + a user-space ztools build. See docs/ctf-references/.
# NOTE: pulls Ghidra (a JDK + a few hundred MB) — the slow part of this layer.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"
source "$STACK_ROOT/versions.env" 2>/dev/null || true

log "apt: CTF toolchain (RE / crypto / stego / RF / serial)…"
as_root apt-get update -qq
as_root apt-get install -y \
  frotz multimon-ng steghide sox foremost picocom \
  rtl-sdr rtl-433 sigrok-cli ghidra \
  python3-pycryptodome python3-gmpy2 python3-pwntools \
  || warn "some CTF apt packages failed — see output above"

log "building ztools (infodump/txd — not apt-installable)…"
bash "$STACK_ROOT/payload/scripts/install-ztools.sh" || warn "ztools build had issues — see output above"

# Broaden the hexstrike/offensive toolset: bin-exploit/pwn, cloud/container, web-app,
# recon/OSINT, creds. Long (~20-30 min), idempotent + graceful; skips GUI/licensed/
# kernel tools (burpsuite, maltego, falco, clair).
log "installing extended offensive toolset (hexstrike-tools.sh)…"
as_root bash "$STACK_ROOT/payload/scripts/hexstrike-tools.sh" || warn "extended toolset had issues — see output above"

# ── GEF (gdb enhancement) ─────────────────────────────────────────────────────
# NOT peda: hexstrike's gdb_peda_debug endpoint hardcodes `source ~/peda/peda.py`,
# a path that has never existed on either host -- so that MCP tool is broken and
# the stack had no gdb enhancement at all. GEF also has far better aarch64 support,
# and both hosts are arm64. Pinned by release tag, user-scoped (no sudo).
log "installing GEF ${GEF_TAG:-latest} (gdb enhancement for ctf-pwn / ctf-rev / fw-triage)…"
if curl -fsSL "https://raw.githubusercontent.com/hugsy/gef/${GEF_TAG:-main}/gef.py" -o "$HOME/.gdbinit-gef.py"; then
  grep -q 'gdbinit-gef.py' "$HOME/.gdbinit" 2>/dev/null \
    || echo "source $HOME/.gdbinit-gef.py" >> "$HOME/.gdbinit"
else
  warn "GEF download failed — gdb will run unenhanced"
fi

# ── CyberChef (local decode workbench) ────────────────────────────────────────
# Offline "cyber swiss-army knife" for the ctf-* / fw-triage / rf-decode chains.
# Bound to loopback + tailnet ONLY -- never 0.0.0.0. Enforced at the Docker port
# binding, so it needs no lab-guard rule (it never reaches the LAN in the first
# place). Pinned by digest, same discipline as COWRIE_DIGEST.
if command -v docker >/dev/null 2>&1; then
  log "starting CyberChef on 127.0.0.1:${CYBERCHEF_PORT:-8000} + tailnet…"
  _ts_ip="$(tailscale ip -4 2>/dev/null | head -1 | tr -d '[:space:]')"
  _cc_ref="${CYBERCHEF_IMAGE:-mpepping/cyberchef}@${CYBERCHEF_DIGEST:-}"
  [ -z "${CYBERCHEF_DIGEST:-}" ] && _cc_ref="${CYBERCHEF_IMAGE:-mpepping/cyberchef}:latest"
  docker pull -q "$_cc_ref" >/dev/null 2>&1 || warn "cyberchef pull failed"
  docker rm -f cyberchef >/dev/null 2>&1 || true
  docker run -d --name cyberchef --restart unless-stopped \
    -p "127.0.0.1:${CYBERCHEF_PORT:-8000}:8000" \
    ${_ts_ip:+-p "${_ts_ip}:${CYBERCHEF_PORT:-8000}:8000"} \
    "$_cc_ref" >/dev/null 2>&1 && ok "cyberchef up" || warn "cyberchef failed to start"
else
  warn "docker absent — skipping CyberChef"
fi

# ── OSINT automation setup (spiderfoot + recon-ng) ────────────────────────────
# apt installs both via hexstrike-tools.sh above, but recon-ng ships with NO modules
# -- a bare install is inert -- so the marketplace set and API keys are a separate
# post-apt step. spiderfoot needs no setup; it runs headless straight from the CLI.
log "setting up recon-ng modules + keys, installing recon-ng-domain wrapper…"
install -Dm0755 "$STACK_ROOT/payload/scripts/recon-ng-domain.sh" "$HOME/.local/bin/recon-ng-domain"
bash "$STACK_ROOT/payload/scripts/setup-recon-ng.sh" || warn "recon-ng setup had issues — see output above"

verify "dfrotz present"   bash -lc 'command -v dfrotz'
verify "infodump present" bash -lc 'command -v infodump'
verify "multimon-ng"      bash -lc 'command -v multimon-ng'
verify "ghidra present"   bash -lc 'command -v ghidra'
# Debian ships pycryptodome under the 'Cryptodome' namespace, not 'Crypto':
verify "pycryptodome"     python3 -c 'import Cryptodome'
verify "spiderfoot headless" bash -lc 'spiderfoot --help >/dev/null 2>&1'
verify "recon-ng modules"    bash -lc '[ "$(find "$HOME/.recon-ng/modules" -name "*.py" 2>/dev/null | wc -l)" -gt 0 ]'
verify "gef loads in gdb" bash -lc 'gdb -q -batch -ex "gef" 2>&1 | grep -q "commands loaded"'
ok "55-ctf-tools done — solve scripts import from 'Cryptodome' (not 'Crypto') on this box"
