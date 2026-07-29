#!/usr/bin/env bash
# install-web-tools.sh — install the web-assessment tools hexstrike was missing.
# All user-space (no sudo): go install -> ~/go/bin, pipx -> ~/.local/bin, cargo -> ~/.cargo/bin.
# Idempotent-ish: re-running just reinstalls @latest. Logs pass/fail per tool, never aborts.

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
