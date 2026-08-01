#!/usr/bin/env bash
# layers/10-skills.sh — operator skills to ~/.claude/agents and render the
# mcpServers block of ~/.claude.json from claude.json.tmpl + secrets. Merges into
# any existing ~/.claude.json (never clobbers Claude Code's other state).
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"

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

verify "device-assess agent present" test -f "$HOME/.claude/agents/device-assess.md"
verify "mcp-doctor skill present" test -f "$HOME/.claude/skills/mcp-doctor/SKILL.md"
verify "mcpServers in config" python3 -c "import json;assert json.load(open('$HOME/.claude.json'))['mcpServers']"
ok "10-skills done"
