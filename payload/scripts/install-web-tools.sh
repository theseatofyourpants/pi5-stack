#!/usr/bin/env bash
# install-web-tools.sh — install the web-assessment tools hexstrike was missing.
# All user-space (no sudo): go install -> ~/go/bin, pipx -> ~/.local/bin, cargo -> ~/.cargo/bin.
# Idempotent-ish: re-running just reinstalls @latest. Logs pass/fail per tool, never aborts.

# Source the pins directly: this script runs as a CHILD of the layer, which sources
# versions.env without exporting -- so SSTIMAP_COMMIT would otherwise be empty here
# and the clone would silently float to master HEAD.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${STACK_ROOT:-$_SELF_DIR/../..}/versions.env" 2>/dev/null || true

export GOROOT="$HOME/go-sdk"
export GOPATH="$HOME/go"
export GOBIN="$HOME/go/bin"
export PATH="$HOME/go-sdk/bin:$HOME/go/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
mkdir -p "$GOBIN" "$HOME/.local/bin"

LOG="$HOME/install-web-tools.log"
: > "$LOG"
PASS=(); FAIL=()

say(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

run(){ # run <name> <command...>
  local name="$1"; shift
  say ">>> $name : $*"
  if "$@" >>"$LOG" 2>&1; then
    if command -v "$name" >/dev/null 2>&1; then PASS+=("$name"); say "    OK  ($(command -v $name))"
    else FAIL+=("$name (installed but not on PATH)"); say "    ?? installed but $name not on PATH"; fi
  else
    FAIL+=("$name"); say "    FAIL (see log)"
  fi
}

say "=== GO TOOLS (-> $GOBIN) ==="
run katana      go install github.com/projectdiscovery/katana/cmd/katana@latest
run hakrawler   go install github.com/hakluke/hakrawler@latest
run dalfox      go install github.com/hahwul/dalfox/v2@latest
run gau         go install github.com/lc/gau/v2/cmd/gau@latest
run waybackurls go install github.com/tomnomnom/waybackurls@latest
run qsreplace   go install github.com/tomnomnom/qsreplace@latest
run assetfinder go install github.com/tomnomnom/assetfinder@latest
run subfinder   go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest

say "=== PYTHON TOOLS (pipx -> ~/.local/bin) ==="
run arjun       pipx install arjun --force
run uro         pipx install uro --force
run dirsearch   pipx install dirsearch --force
# paramspider: pypi package name is 'paramspider'; fall back to git if needed
if ! pipx install paramspider --force >>"$LOG" 2>&1; then
  pipx install "git+https://github.com/devanshbatham/paramspider.git" --force >>"$LOG" 2>&1
fi
command -v paramspider >/dev/null 2>&1 && { PASS+=(paramspider); say ">>> paramspider OK"; } || { FAIL+=(paramspider); say ">>> paramspider FAIL"; }

say "=== SSTImap (server-side template injection; clone-and-run, pinned) ==="
# Upstream ships no pyproject/setup.py, so pipx/pip cannot install it. Clone at the
# pinned commit, give it its own venv, and drop a wrapper on PATH.
SSTIMAP_REPO="${SSTIMAP_REPO:-https://github.com/vladko312/SSTImap.git}"
SSTIMAP_COMMIT="${SSTIMAP_COMMIT:-}"
SSTI_SRC="$HOME/SSTImap"
if [ -d "$SSTI_SRC/.git" ]; then
  git -C "$SSTI_SRC" fetch -q origin >>"$LOG" 2>&1 || true
else
  git clone -q "$SSTIMAP_REPO" "$SSTI_SRC" >>"$LOG" 2>&1 || true
fi
[ -n "$SSTIMAP_COMMIT" ] && git -C "$SSTI_SRC" checkout -q "$SSTIMAP_COMMIT" >>"$LOG" 2>&1 || true
python3 -m venv "$SSTI_SRC/venv" >>"$LOG" 2>&1 || true
"$SSTI_SRC/venv/bin/pip" install -q -r "$SSTI_SRC/requirements.txt" >>"$LOG" 2>&1 || true
cat > "$HOME/.local/bin/sstimap" <<'WRAP'
#!/usr/bin/env bash
# wrapper: SSTImap is clone-and-run (no pyproject/setup.py upstream)
exec "$HOME/SSTImap/venv/bin/python" "$HOME/SSTImap/sstimap.py" "$@"
WRAP
chmod 0755 "$HOME/.local/bin/sstimap"
if sstimap --version >>"$LOG" 2>&1; then PASS+=(sstimap); say ">>> sstimap OK"; else FAIL+=(sstimap); say ">>> sstimap FAIL"; fi

say "=== feroxbuster (prebuilt arm64 binary -> ~/.local/bin) ==="
( cd "$HOME/.local/bin" && curl -sL https://raw.githubusercontent.com/epi052/feroxbuster/main/install-nix.sh | bash ) >>"$LOG" 2>&1
command -v feroxbuster >/dev/null 2>&1 && { PASS+=(feroxbuster); say ">>> feroxbuster OK"; } || { FAIL+=(feroxbuster); say ">>> feroxbuster FAIL"; }

say "=== x8 (cargo -> ~/.cargo/bin; compiles, may be slow) ==="
run x8          cargo install x8

say ""
say "================= INSTALL SUMMARY ================="
say "INSTALLED (${#PASS[@]}): ${PASS[*]}"
say "FAILED    (${#FAIL[@]}): ${FAIL[*]}"
say "=================================================="
say "Next: add ~/go/bin to shell PATH permanently, then restart hexstrike backend with augmented PATH."
