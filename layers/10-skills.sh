#!/usr/bin/env bash
# layers/10-skills.sh — install Claude Code, deploy the operator agents/skills into
# ~/.claude/, and render the mcpServers block of ~/.claude.json from
# claude.json.tmpl + secrets. Merges into any existing ~/.claude.json (never
# clobbers Claude Code's other state).
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"
source "$STACK_ROOT/versions.env" 2>/dev/null || true   # CLAUDE_CODE_VERSION

# 0. Claude Code itself. Everything else in this layer — and the headless
# stack-status / triage-alerts timers from 70-automation — is inert without it.
# The rebuild used to assume it was already on the box and only prompted for login.
CLAUDE_BIN="$HOME/.local/bin/claude"
if [ -x "$CLAUDE_BIN" ] || command -v claude >/dev/null 2>&1; then
  ok "Claude Code already installed: $(claude --version 2>/dev/null || "$CLAUDE_BIN" --version)"
else
  log "installing Claude Code (${CLAUDE_CODE_VERSION:-latest})…"
  # Deliberately NOT as_root: the installer puts everything under $HOME and refuses
  # to run under sudo, which would land the binary in /root/.local/bin.
  curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_VERSION:-latest}" \
    || die "Claude Code install failed — agents, skills and the headless timers all need it"
  ok "Claude Code installed: $("$CLAUDE_BIN" --version 2>/dev/null || echo unknown)"
fi

# 1. operator agents (autonomous, /operation-chainable)
mkdir -p "$HOME/.claude/agents"
cp "$STACK_ROOT"/payload/agents/*.md "$HOME/.claude/agents/"
ok "installed $(ls "$STACK_ROOT"/payload/agents/*.md | wc -l) operator agents -> ~/.claude/agents"

# 1b. operator skills (inline SKILL.md runbooks) — each is a <name>/SKILL.md dir
if [ -d "$STACK_ROOT/payload/skills" ]; then
  mkdir -p "$HOME/.claude/skills"
  cp -r "$STACK_ROOT"/payload/skills/* "$HOME/.claude/skills/"
  ok "installed $(ls -d "$STACK_ROOT"/payload/skills/*/ | wc -l) operator skills -> ~/.claude/skills"
fi

# 2. secrets for MCP rendering (prompt if missing)
require_secret VT_API_KEY        "VirusTotal API key (virustotal MCP; blank = it won't auth)"
require_secret GREYNOISE_API_KEY "GreyNoise API key (OPTIONAL — greynoise MCP works keyless)"
: "${CAIDO_URL:=http://127.0.0.1:8080}";  export CAIDO_URL
: "${MYTHIC_PASSWORD:=}";                 export MYTHIC_PASSWORD

# The virustotal and playwright MCP servers are spawned by Claude Code with a
# minimal environment, so the template carries an ABSOLUTE npx path rather than a
# bare "npx". On this stack npm is not installed at all and npx comes from Debian's
# corepack shims, which are not on PATH — a bare "npx" would leave both servers
# dead, and virustotal backs nine of the operator agents.
NPX_BIN="$(ensure_npx)" || warn "no npx found — the virustotal and playwright MCP servers will not start"
: "${NPX_BIN:=npx}"; export NPX_BIN
log "npx resolved to: $NPX_BIN"

# 3. render the template (substitute {{VARS}} from env) and validate JSON
rendered="$(mktemp)"
python3 - "$STACK_ROOT/payload/claude.json.tmpl" > "$rendered" <<'PY'
import json, sys, os, re
t = open(sys.argv[1]).read()
t = re.sub(r"\{\{([A-Z0-9_]+)\}\}", lambda m: os.environ.get(m.group(1), ""), t)
json.loads(t)          # fail loudly if the substitution broke the JSON
sys.stdout.write(t)
PY

# 4. merge mcpServers into ~/.claude.json, preserving everything else
python3 - "$HOME/.claude.json" "$rendered" <<'PY'
import json, sys, os
cj, rendered = sys.argv[1], sys.argv[2]
mcp = json.load(open(rendered))["mcpServers"]
cfg = {}
if os.path.exists(cj):
    try: cfg = json.load(open(cj))
    except Exception: cfg = {}
cfg["mcpServers"] = mcp
json.dump(cfg, open(cj, "w"), indent=2)
print("merged %d MCP servers into ~/.claude.json" % len(mcp))
PY
rm -f "$rendered"

# 5. Claude Code auth (can't be scripted)
stop_for_manual "Claude Code login" \
  "If this is a fresh box, authenticate Claude Code now in another shell:" \
  "    claude        (then use /login)" \
  "Skip if you're already logged in."

verify "claude CLI installed"       bash -lc 'command -v claude >/dev/null || test -x "$HOME/.local/bin/claude"'
verify "claude CLI runs"            bash -lc '"${HOME}/.local/bin/claude" --version >/dev/null 2>&1 || claude --version >/dev/null 2>&1'
verify "npx resolvable for MCPs"    test -x "$NPX_BIN"
verify "device-assess agent present" test -f "$HOME/.claude/agents/device-assess.md"
verify "mcp-doctor skill present" test -f "$HOME/.claude/skills/mcp-doctor/SKILL.md"
verify "mcpServers in config" python3 -c "import json;assert json.load(open('$HOME/.claude.json'))['mcpServers']"
ok "10-skills done"
