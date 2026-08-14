#!/usr/bin/env bash
# layers/51-c2-mythic.sh — Mythic C2 (Docker) + admin-pw capture + mythic MCP +
# caido MCP. [opt-in, slow — Mythic pulls/builds 8 containers on first start]
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"
source "$STACK_ROOT/versions.env" 2>/dev/null || true
export PATH="$HOME/go/bin:$HOME/go-sdk/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

clone_ref(){ local u="$1" r="$2" d="$3"; if [ -d "$d/.git" ]; then git -C "$d" fetch -q origin || true; else git clone -q "$u" "$d"; fi; git -C "$d" checkout -q "$r" 2>/dev/null || warn "checkout $r failed ($d)"; }

# 0. docker — Kali ships docker.io natively; Docker's CE repo publishes no
# 'kali-rolling' suite (get.docker.com fails), and forcing a Debian codename risks
# dep conflicts on Kali. So install the native engine and drop in the official
# compose v2 plugin binary (docker.io does not bundle it; Mythic needs `docker compose`).
if ! need_cmd docker; then
  log "installing docker.io + containerd (Kali-native)…"
  as_root apt-get install -y docker.io containerd
  as_root systemctl enable --now docker || true
  as_root usermod -aG docker "$USER" || true
fi
if ! docker compose version >/dev/null 2>&1; then
  DCV="${DOCKER_COMPOSE_VERSION:-$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep -oP '"tag_name": "\K[^"]+')}"
  log "installing docker compose v2 plugin ${DCV}…"
  as_root mkdir -p /usr/local/lib/docker/cli-plugins
  as_root curl -fsSL "https://github.com/docker/compose/releases/download/${DCV}/docker-compose-linux-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  as_root chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi
verify "docker" command -v docker
verify "docker compose" docker compose version

# 1. Mythic (clone + build mythic-cli)
log "installing Mythic ${MYTHIC_VERSION:-v3.4.0}…"
clone_ref "https://github.com/its-a-feature/Mythic" "${MYTHIC_VERSION:-v3.4.0}" "$HOME/Mythic"
if [ ! -x "$HOME/Mythic/mythic-cli" ]; then
  ( cd "$HOME/Mythic" && as_root make ) || warn "mythic-cli build failed — see Mythic install docs"
fi

# 2. start Mythic (generates .env with a random admin password) — heavy
stop_for_manual "Start Mythic (Docker — several minutes on first run)" \
  "About to run:  cd ~/Mythic && sudo ./mythic-cli start" \
  "It pulls/builds 8 containers. Press Enter to proceed (Ctrl-C to skip Mythic)."
( cd "$HOME/Mythic" && as_root ./mythic-cli start ) || warn "mythic-cli start had issues — check: sudo ./mythic-cli status"

# 3. capture the generated admin password -> secrets.env
if [ -f "$HOME/Mythic/.env" ]; then
  pw="$(grep -E '^MYTHIC_ADMIN_PASSWORD' "$HOME/Mythic/.env" | head -1 | sed 's/^[^=]*=//; s/^"//; s/"$//')"
  if [ -n "$pw" ]; then
    touch "$SECRETS_FILE"; chmod 600 "$SECRETS_FILE"
    if grep -q '^MYTHIC_PASSWORD=' "$SECRETS_FILE" 2>/dev/null; then
      sed -i "s|^MYTHIC_PASSWORD=.*|MYTHIC_PASSWORD=${pw}|" "$SECRETS_FILE"
    else echo "MYTHIC_PASSWORD=${pw}" >> "$SECRETS_FILE"; fi
    ok "captured Mythic admin password -> secrets.env (login: mythic_admin)"
    warn "re-run './bootstrap.sh --layers 10-skills' to inject it into ~/.claude.json"
  fi
fi

# 4. Mythic-MCP (Go build)
log "building Mythic-MCP…"
clone_ref "$MYTHIC_MCP_REPO" "${MYTHIC_MCP_REF:-main}" "$HOME/Mythic-MCP"
( cd "$HOME/Mythic-MCP" && { [ -f Makefile ] && make || go build -o mythic-mcp .; } ) || warn "Mythic-MCP build failed"
verify "mythic-mcp binary" test -x "$HOME/Mythic-MCP/mythic-mcp"

# 5. caido-mcp-server (Go build) -> ~/.local/bin
log "building caido-mcp-server…"
clone_ref "$CAIDO_MCP_REPO" "${CAIDO_MCP_REF:-main}" "$HOME/caido-mcp-server"
( cd "$HOME/caido-mcp-server" && go build -o "$HOME/.local/bin/caido-mcp-server" . ) || warn "caido MCP build failed"
verify "caido-mcp-server binary" test -x "$HOME/.local/bin/caido-mcp-server"

# 6. Caido runs on your laptop (no arm64 build) — manual, safe to skip now
stop_for_manual "Caido (laptop) — optional" \
  "Caido has no arm64 build. When you want the caido MCP live:" \
  "  1. run the Caido desktop app on your x86_64 laptop" \
  "  2. bash ~/pi5-stack/payload/scripts/caido-setup.sh http://<laptop-ip>:8080" \
  "  3. set CAIDO_URL in secrets.env, then ./bootstrap.sh --layers 10-skills" \
  "Press Enter to continue (safe to skip)."

ok "51-c2-mythic done. Mythic UI: https://localhost:7443 (mythic_admin / captured pw)."
