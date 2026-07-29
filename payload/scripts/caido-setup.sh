#!/bin/bash
# caido-setup.sh — authenticate caido-mcp-server against a running Caido instance
#
# Caido has no arm64 Linux binary. Run Caido on your laptop/workstation (x86_64),
# then point this Pi's MCP server at it.
#
# Setup:
#   1. On your laptop: install Caido from https://caido.io/download/
#   2. Launch Caido, go to Settings > Listening Address, note the port (default 8080)
#   3. Run this script with the Caido URL: bash caido-setup.sh http://laptop-ip:8080
#
# After login, the token is stored in ~/.config/caido-mcp-server/ and
# subsequent MCP server starts will authenticate automatically.

set -e

CAIDO_URL="${1:-http://127.0.0.1:8080}"

echo "[+] Authenticating caido-mcp-server against: $CAIDO_URL"
echo ""
echo "    This will open a browser OAuth flow in Caido."
echo "    In the Caido UI, click [Allow] to authorize."
echo ""

~/.local/bin/caido-mcp-server login -u "$CAIDO_URL"

echo ""
echo "[+] Login complete. Testing MCP server connection..."
timeout 5 ~/.local/bin/caido-mcp-server serve -u "$CAIDO_URL" 2>&1 | head -5 || true

echo ""
echo "[+] Done. Update CAIDO_URL in ~/.claude.json if your Caido runs on a different address."
echo "    Current config: http://127.0.0.1:8080"
echo ""
echo "    To change: edit the 'caido' entry in ~/.claude.json mcpServers"
