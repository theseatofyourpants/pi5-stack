#!/usr/bin/env bash
# layers/20-mcp-core.sh — the six always-on MCP servers + their backends:
# greynoise(custom), mcp-kali-server, hexstrike, playwright, wstg-pentest, pentest-ai.
# Backends (hexstrike :8899, kali-server :5000) are installed as systemd services so
# they survive reboot — an improvement over the original manual `nohup` approach.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"
source "$STACK_ROOT/versions.env" 2>/dev/null || true
export PATH="$HOME/go/bin:$HOME/go-sdk/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# --- toolchain deps not covered by 00-core ---
log "toolchain: node/npm + uv…"
need_cmd npm || as_root apt-get install -y npm
if ! need_cmd uv && [ ! -x "$HOME/.local/bin/uv" ]; then
  curl -fsSL https://astral.sh/uv/install.sh | sh
fi

clone_ref(){ # clone_ref <url> <ref> <dest>
  local url="$1" ref="$2" dest="$3"
  if [ -d "$dest/.git" ]; then git -C "$dest" fetch -q origin || true
  else git clone -q "$url" "$dest"; fi
  git -C "$dest" checkout -q "$ref" 2>/dev/null || warn "checkout $ref failed in $dest (using default branch)"
}

# ===== 1. greynoise (custom, from payload) =====
log "greynoise MCP (custom)…"
mkdir -p "$HOME/greynoise-mcp"
rsync -a "$STACK_ROOT/payload/greynoise-mcp/" "$HOME/greynoise-mcp/"
[ -d "$HOME/greynoise-mcp/venv" ] || python3 -m venv "$HOME/greynoise-mcp/venv"
# Pin mcp to 1.x: server.py uses mcp.server.fastmcp.FastMCP, which the mcp 2.0
# rewrite moved/removed — an unpinned install pulls 2.x and breaks the import.
"$HOME/greynoise-mcp/venv/bin/pip" -q install --upgrade pip httpx "mcp<2"
verify "greynoise deps" "$HOME/greynoise-mcp/venv/bin/python" -c "import httpx; from mcp.server.fastmcp import FastMCP"

# ===== 2. mcp-kali-server (+ backend :5000) =====
log "mcp-kali-server…"
clone_ref "$KALI_MCP_REPO" "${KALI_MCP_REF:-master}" "$HOME/MCP-Kali-Server"
[ -d "$HOME/MCP-Kali-Server/venv" ] || python3 -m venv "$HOME/MCP-Kali-Server/venv"
"$HOME/MCP-Kali-Server/venv/bin/pip" -q install --upgrade pip
for r in requirements.txt requirements.kali.txt requirements.mcp.txt; do
  [ -f "$HOME/MCP-Kali-Server/$r" ] && "$HOME/MCP-Kali-Server/venv/bin/pip" -q install -r "$HOME/MCP-Kali-Server/$r" || true
done
# mcp_server.py imports mcp.server.fastmcp.FastMCP; the repo leaves mcp unpinned, so
# a fresh install pulls mcp 2.x (fastmcp removed) and the MCP fails to launch. Force 1.x.
"$HOME/MCP-Kali-Server/venv/bin/pip" -q install "mcp<2"
verify "kali-server MCP deps" "$HOME/MCP-Kali-Server/venv/bin/python" -c "from mcp.server.fastmcp import FastMCP"

# ===== 3. hexstrike (+ backend :8899 + web tools) =====
log "hexstrike…"
clone_ref "$HEXSTRIKE_REPO" "${HEXSTRIKE_REF:-master}" "$HOME/hexstrike-ai-community-edition"
HX="$HOME/hexstrike-ai-community-edition"
[ -d "$HX/hexstrike-env" ] || python3 -m venv "$HX/hexstrike-env"
"$HX/hexstrike-env/bin/pip" -q install --upgrade pip
[ -f "$HX/requirements.txt" ] && "$HX/hexstrike-env/bin/pip" -q install -r "$HX/requirements.txt"
log "installing web tools for hexstrike (katana/nuclei/dalfox/… — several minutes)…"
bash "$STACK_ROOT/payload/scripts/install-web-tools.sh" || warn "some web tools failed (non-fatal)"

# ===== 4. wstg-pentest (autopentest-ai, uv project) =====
log "wstg-pentest (autopentest-ai)…"
clone_ref "$WSTG_REPO" "${WSTG_REF:-main}" "$HOME/autopentest-ai"
( cd "$HOME/autopentest-ai/server" && "$HOME/.local/bin/uv" sync ) || warn "uv sync deferred to first run"

# ===== 5. pentest-ai (ptai pip package in a venv) =====
log "pentest-ai (ptai)…"
[ -d "$HOME/pentest-ai/venv" ] || python3 -m venv "$HOME/pentest-ai/venv"
"$HOME/pentest-ai/venv/bin/pip" -q install --upgrade pip "${PENTEST_AI_PIP:-ptai}"

# ===== 6. playwright MCP (npx) + browser =====
log "playwright MCP + chromium browser…"
npx -y playwright install chromium >/dev/null 2>&1 || warn "playwright browser install had issues (non-fatal)"

# ===== backends as systemd (survive reboot) =====
log "installing backend systemd units (hexstrike :${HEXSTRIKE_PORT:-8899}, kali-server :${KALI_BACKEND_PORT:-5000})…"
# From payload, not heredocs. These were the only units in the stack that stack-drift
# could not see, because a heredoc inside a layer is not a file the manifest can
# compare — and three different generations of kali-server's unit accumulated across
# the Pi and the VM under two different NAMES as a result.
# Canonical name is kali-server.service: it is what mcp-doctor, add-mcp and the
# reboot runbook all reference. The old kali-server-backend.service is retired here,
# or an in-place re-run leaves two enabled units fighting over :5000.
U="$(id -un)"; G="$(id -gn)"
for unit in "$STACK_ROOT"/payload/mcp-backends/*.service; do
  sed -e "s#/home/tsoyp#$HOME#g" -e "s#User=tsoyp#User=$U#g" -e "s#Group=tsoyp#Group=$G#g" "$unit" \
    | as_root tee "/etc/systemd/system/$(basename "$unit")" >/dev/null
done
if [ -e /etc/systemd/system/kali-server-backend.service ]; then
  log "retiring superseded kali-server-backend.service…"
  as_root systemctl disable --now kali-server-backend.service 2>/dev/null || true
  as_root rm -rf /etc/systemd/system/kali-server-backend.service \
                 /etc/systemd/system/kali-server-backend.service.d
fi
# Drop-ins existed only to patch what the old unit bodies were missing; everything
# they supplied is inline now, and a stale one would silently override it.
as_root rm -rf /etc/systemd/system/kali-server.service.d
as_root systemctl daemon-reload
as_root systemctl enable --now hexstrike-backend.service kali-server.service || warn "backend services didn't start cleanly — check journalctl"

# ===== lab-guard: close what we just opened =====
# Both backends bind 0.0.0.0 and answer with NO AUTHENTICATION, and neither takes a
# bind argument (kali_server.py hardcodes app.run(host="0.0.0.0")). On any network
# that is not a dedicated lab segment that is an unauthenticated RCE surface for
# every other device on the LAN. The layer that opens the ports closes them.
log "installing lab-guard (confine control plane to loopback + tailnet)…"
as_root install -m0755 -o root -g root "$STACK_ROOT/payload/lab-guard/lab-guard.sh" /usr/local/sbin/lab-guard
as_root install -m0644 -o root -g root "$STACK_ROOT/payload/lab-guard/lab-guard.service" /etc/systemd/system/
as_root systemctl daemon-reload
as_root systemctl enable --now lab-guard.service || warn "lab-guard did not apply — control-plane ports are LAN-reachable"
verify "lab-guard active" bash -c 'sudo -n iptables -n -L LABGUARD >/dev/null 2>&1 || systemctl is-active --quiet lab-guard.service' 

# --- verify (soft on the backends: they can take a moment to bind) ---
sleep 5
if bash -lc 'ss -tln 2>/dev/null | grep -q :'"${HEXSTRIKE_PORT:-8899}"; then ok "hexstrike backend listening :${HEXSTRIKE_PORT:-8899}"; else warn "hexstrike backend not listening yet — check: journalctl -u hexstrike-backend"; fi
if bash -lc 'ss -tln 2>/dev/null | grep -q :'"${KALI_BACKEND_PORT:-5000}"; then ok "kali-server backend listening :${KALI_BACKEND_PORT:-5000}"; else warn "kali-server backend not listening yet — check: journalctl -u kali-server-backend"; fi
verify "uv present" test -x "$HOME/.local/bin/uv"
verify "npx present" bash -lc 'command -v npx'
verify "greynoise present" test -f "$HOME/greynoise-mcp/server.py"
ok "20-mcp-core done. The MCP entries rendered into ~/.claude.json (layer 10) connect to these."
