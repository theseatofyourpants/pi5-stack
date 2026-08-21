#!/usr/bin/env bash
# hexstrike-tools.sh — broaden the hexstrike/offensive toolset with the bin-exploit,
# cloud/container, web-app, recon/OSINT and credential tools hexstrike tracks but a
# base install lacks. Idempotent + graceful (one tool failing never aborts the rest);
# prints a summary of what's present at the end.
#
# Run with sudo (apt needs root; user-scoped installs drop to the invoking user):
#     sudo bash hexstrike-tools.sh
#
# Deliberately NOT installed (can't be done headless/unattended): burpsuite & maltego
# (GUI + registration/licensing — use Caido/Playwright instead), falco (needs a kernel
# driver), clair (DB-backed service, not a CLI). shodan/censys CLIs install but need an
# API key to be useful.
set -uo pipefail

ARCH="$(dpkg --print-architecture 2>/dev/null || echo arm64)"     # arm64 | amd64
UARCH="$(uname -m)"                                                # aarch64 | x86_64
RUN_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
BIN=/usr/local/bin
log(){ printf '\n\033[36m[*] %s\033[0m\n' "$*"; }
warn(){ printf '\033[33m[!] %s\033[0m\n' "$*" >&2; }
# run a command as the invoking (non-root) user with their HOME/PATH
asuser(){ sudo -u "$RUN_USER" env HOME="$USER_HOME" PATH="$USER_HOME/.local/bin:$USER_HOME/go/bin:$USER_HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin" "$@"; }

[ "$(id -u)" -eq 0 ] || { echo "run with sudo: sudo bash $0"; exit 1; }

# ── 1. apt (Kali packages most of these) ─────────────────────────────────────
log "apt packages…"
# Heal any half-configured package (e.g. a suricata conffile prompt left by a prior
# non-interactive apt run) so a single wedged package can't cascade-fail every install.
DEBIAN_FRONTEND=noninteractive dpkg --configure -a --force-confold >/dev/null 2>&1 || true
apt-get update -qq || warn "apt update had issues"
APT_TOOLS=(
  gdb checksec xsser dotdotpwn zaproxy arp-scan responder john httpie   # exploit/web/recon/creds
  enum4linux-ng sherlock rustscan ropgadget                             # recon/creds/pwn (present in Kali repos)
  spiderfoot recon-ng                                                   # OSINT automation for osint-profile / identity-osint
  ruby ruby-dev pipx golang-go                                          # runtimes for gem/pipx/go installs below
)
for p in "${APT_TOOLS[@]}"; do
  apt-get install -y "$p" >/dev/null 2>&1 && echo "  apt  $p ✓" || warn "apt $p failed (may not be packaged) — trying other methods below"
done

# ── 2. pipx — isolated CLI apps ──────────────────────────────────────────────
log "pipx CLI tools…"
asuser pipx ensurepath >/dev/null 2>&1 || true
PIPX_TOOLS=( ropper prowler scoutsuite checkov kube-hunter bbot autorecon social-analyzer shodan censys )
for t in "${PIPX_TOOLS[@]}"; do
  asuser pipx install "$t" >/dev/null 2>&1 && echo "  pipx $t ✓" || warn "pipx $t failed"
done

# ── 3. pip libraries (imported by scripts, not standalone CLIs) ───────────────
log "pip libraries (pwntools, angr)…"
for lib in pwntools angr; do
  asuser pip install --user --break-system-packages "$lib" >/dev/null 2>&1 && echo "  pip  $lib ✓" || warn "pip $lib failed (angr is heavy on arm64)"
done

# ── 4. go install ────────────────────────────────────────────────────────────
log "go tools (jaeles)…"
GO="$USER_HOME/go-sdk/bin/go"; [ -x "$GO" ] || GO="$(command -v go || echo go)"
asuser env GOBIN="$USER_HOME/go/bin" "$GO" install github.com/jaeles-project/jaeles@latest >/dev/null 2>&1 \
  && echo "  go   jaeles ✓" || warn "go jaeles failed"

# ── 5. cargo (rust) — pwninit; rustscan too if apt missed it ─────────────────
log "cargo tools (pwninit)…"
CARGO="$USER_HOME/.cargo/bin/cargo"; [ -x "$CARGO" ] || CARGO="$(command -v cargo || echo cargo)"
command -v rustscan >/dev/null 2>&1 || asuser "$CARGO" install rustscan >/dev/null 2>&1 && echo "  cargo rustscan ✓" || true
asuser "$CARGO" install pwninit >/dev/null 2>&1 && echo "  cargo pwninit ✓" || warn "cargo pwninit failed"

# ── 6. gem (ruby) — one_gadget ───────────────────────────────────────────────
log "gem tools (one_gadget)…"
gem install one_gadget >/dev/null 2>&1 && echo "  gem  one_gadget ✓" || warn "gem one_gadget failed"

# ── 7. release binaries (arch-aware): trivy, terrascan, kube-bench ───────────
log "release binaries (trivy, terrascan, kube-bench)…"
gh_latest(){ curl -fsSL "https://api.github.com/repos/$1/releases/latest" | grep -oP '"tag_name": "\K[^"]+'; }
dl_tar(){ # url, binary-name-in-tar
  local url="$1" bin="$2" tmp; tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/a.tgz" && tar -C "$tmp" -xzf "$tmp/a.tgz" 2>/dev/null \
    && install -m0755 "$(find "$tmp" -name "$bin" -type f | head -1)" "$BIN/$bin" && echo "  bin  $bin ✓" || warn "binary $bin failed"
  rm -rf "$tmp"
}
# arch tokens differ per project
case "$ARCH" in arm64) TRIVY_A=ARM64; TERRA_A=arm64; KB_A=arm64;; *) TRIVY_A=64bit; TERRA_A=amd64; KB_A=amd64;; esac
TV="$(gh_latest aquasecurity/trivy)";      dl_tar "https://github.com/aquasecurity/trivy/releases/download/${TV}/trivy_${TV#v}_Linux-${TRIVY_A}.tar.gz" trivy
TS="$(gh_latest tenable/terrascan)";       dl_tar "https://github.com/tenable/terrascan/releases/download/${TS}/terrascan_${TS#v}_Linux_${TERRA_A}.tar.gz" terrascan
KBV="$(gh_latest aquasecurity/kube-bench)";dl_tar "https://github.com/aquasecurity/kube-bench/releases/download/${KBV}/kube-bench_${KBV#v}_linux_${KB_A}.tar.gz" kube-bench

# ── 8. git-clone tools: libc-database, docker-bench-security, jwt_tool ────────
log "git-clone tools…"
clone(){ [ -d "$USER_HOME/$2/.git" ] || asuser git clone -q --depth 1 "$1" "$USER_HOME/$2" && echo "  git  $2 ✓" || warn "git $2 failed"; }
clone https://github.com/docker/docker-bench-security  docker-bench-security
clone https://github.com/ticarpi/jwt_tool               jwt_tool
asuser pip install --user --break-system-packages termcolor cprint pycryptodomex requests >/dev/null 2>&1 || true  # jwt_tool deps
# libc-database is large (downloads libc sets); clone shallow without the DBs by default
clone https://github.com/niklasb/libc-database          libc-database

# ── summary ──────────────────────────────────────────────────────────────────
log "installed-tool check"
CHECK=( gdb checksec ROPgadget ropper one_gadget pwninit angr:py pwntools:py xsser dotdotpwn zaproxy jaeles jwt_tool
        rustscan arp-scan bbot autorecon sherlock social-analyzer shodan censys enum4linux-ng responder john httpie spiderfoot recon-ng
        trivy terrascan kube-bench prowler scout kube-hunter checkov )
present=0; total=0
for c in "${CHECK[@]}"; do
  total=$((total+1)); name="${c%%:*}"; kind="${c##*:}"
  if [ "$kind" = py ]; then
    asuser python3 -c "import ${name}" >/dev/null 2>&1 && { echo "  ✓ ${name} (py)"; present=$((present+1)); } || echo "  ✗ ${name} (py)"
  else
    { command -v "$name" >/dev/null 2>&1 || asuser bash -c "command -v $name" >/dev/null 2>&1 || [ -e "$USER_HOME/$name" ]; } \
      && { echo "  ✓ ${name}"; present=$((present+1)); } || echo "  ✗ ${name}"
  fi
done
echo
echo "==== $present/$total target tools present ===="
echo "Skipped by design: burpsuite, maltego (GUI/license), falco (kernel), clair (service)."
