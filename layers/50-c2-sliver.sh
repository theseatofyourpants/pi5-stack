#!/usr/bin/env bash
# layers/50-c2-sliver.sh — Sliver C2 server + operator config + sliver-c2 MCP. [opt-in]
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"
source "$STACK_ROOT/versions.env" 2>/dev/null || true
export PATH="$HOME/go/bin:$HOME/go-sdk/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

clone_ref(){ local u="$1" r="$2" d="$3"; if [ -d "$d/.git" ]; then git -C "$d" fetch -q origin || true; else git clone -q "$u" "$d"; fi; git -C "$d" checkout -q "$r" 2>/dev/null || warn "checkout $r failed ($d)"; }
SLIVER_VER="${SLIVER_VERSION:-v1.7.3}"

# 1. sliver-server binary (arm64) -> ~/.local/bin
if ! "$HOME/.local/bin/sliver-server" version 2>/dev/null | grep -q "$SLIVER_VER"; then
  log "downloading sliver-server ${SLIVER_VER} (arm64, ~250MB)…"
  curl -fL "https://github.com/BishopFox/sliver/releases/download/${SLIVER_VER}/sliver-server_linux-arm64" \
    -o "$HOME/.local/bin/sliver-server"
  chmod +x "$HOME/.local/bin/sliver-server"
fi
verify "sliver-server ${SLIVER_VER}" bash -lc "\$HOME/.local/bin/sliver-server version | grep -q $SLIVER_VER"

# 2. sliver daemon as systemd (multiplayer gRPC/mTLS on 127.0.0.1:31337)
log "installing sliver daemon systemd unit…"
as_root tee /etc/systemd/system/sliver.service >/dev/null <<UNIT
[Unit]
Description=Sliver C2 server (daemon / multiplayer :31337)
After=network.target
[Service]
User=$USER
ExecStart=$HOME/.local/bin/sliver-server daemon
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
as_root systemctl daemon-reload
as_root systemctl enable --now sliver.service
sleep 5

# 3. operator config for the MCP (mTLS cert) -> ~/sliver-claude.cfg
if [ ! -f "$HOME/sliver-claude.cfg" ]; then
  log "generating operator config (claude-operator)…"
  "$HOME/.local/bin/sliver-server" operator --name claude-operator --lhost 127.0.0.1 --save "$HOME/sliver-claude.cfg" \
    || warn "operator gen failed — run: sliver-server operator --name claude-operator --lhost 127.0.0.1 --save ~/sliver-claude.cfg"
fi
verify "operator config present" test -f "$HOME/sliver-claude.cfg"

# 4. sliver-c2 MCP (Node build + python venv)
log "building sec-sliver-c2-mcp…"
clone_ref "$SLIVER_MCP_REPO" "${SLIVER_MCP_REF:-main}" "$HOME/sec-sliver-c2-mcp"
( cd "$HOME/sec-sliver-c2-mcp" && npm install --no-fund --no-audit && npm run build ) || warn "sliver MCP node build had issues"
[ -d "$HOME/sec-sliver-c2-mcp/venv" ] || python3 -m venv "$HOME/sec-sliver-c2-mcp/venv"
[ -f "$HOME/sec-sliver-c2-mcp/requirements.txt" ] && "$HOME/sec-sliver-c2-mcp/venv/bin/pip" -q install -r "$HOME/sec-sliver-c2-mcp/requirements.txt" || true
verify "sliver MCP built" test -f "$HOME/sec-sliver-c2-mcp/dist/index.js"
ok "50-c2-sliver done. Daemon :31337, operator config ~/sliver-claude.cfg."
