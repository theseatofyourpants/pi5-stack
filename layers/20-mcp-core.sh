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
as_root tee /etc/systemd/system/hexstrike-backend.service >/dev/null <<UNIT
[Unit]
Description=HexStrike AI backend (:${HEXSTRIKE_PORT:-8899})
After=network.target
[Service]
User=$USER
# HOME must be set explicitly: hexstrike_server.py writes its data dir under \$HOME,
# and systemd does not always populate HOME from User=, so it falls back to '/'
# (-> PermissionError on /.hexstrike_data). WorkingDirectory keeps relative paths sane.
Environment=HOME=$HOME
WorkingDirectory=$HX
Environment=PATH=$HOME/go/bin:$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin
Environment=HEXSTRIKE_PORT=${HEXSTRIKE_PORT:-8899}
ExecStart=$HX/hexstrike-env/bin/python3 $HX/hexstrike_server.py --port ${HEXSTRIKE_PORT:-8899}
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
as_root tee /etc/systemd/system/kali-server-backend.service >/dev/null <<UNIT
[Unit]
Description=MCP Kali Server backend (:${KALI_BACKEND_PORT:-5000})
After=network.target
[Service]
User=$USER
ExecStart=$HOME/MCP-Kali-Server/venv/bin/python3 $HOME/MCP-Kali-Server/kali-server/kali_server.py
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
as_root systemctl daemon-reload
as_root systemctl enable --now hexstrike-backend.service kali-server-backend.service || warn "backend services didn't start cleanly — check journalctl"

# --- verify (soft on the backends: they can take a moment to bind) ---
sleep 5
if bash -lc 'ss -tln 2>/dev/null | grep -q :'"${HEXSTRIKE_PORT:-8899}"; then ok "hexstrike backend listening :${HEXSTRIKE_PORT:-8899}"; else warn "hexstrike backend not listening yet — check: journalctl -u hexstrike-backend"; fi
if bash -lc 'ss -tln 2>/dev/null | grep -q :'"${KALI_BACKEND_PORT:-5000}"; then ok "kali-server backend listening :${KALI_BACKEND_PORT:-5000}"; else warn "kali-server backend not listening yet — check: journalctl -u kali-server-backend"; fi
verify "uv present" test -x "$HOME/.local/bin/uv"
verify "npx present" bash -lc 'command -v npx'
verify "greynoise present" test -f "$HOME/greynoise-mcp/server.py"
ok "20-mcp-core done. The MCP entries rendered into ~/.claude.json (layer 10) connect to these."
