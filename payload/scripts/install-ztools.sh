#!/usr/bin/env bash
# install-ztools.sh — build the Z-machine RE tools (infodump / txd) from source.
# NOT apt-installable. User-space only (no sudo): builds in a temp dir, installs
# to ~/.local/bin. Needed to reverse Infocom/Inform .z-story files — e.g. the
# AND!XOR BENDER badge CTF (docs/ctf-references/AND-XOR-5n4ck3y.md).
set -euo pipefail

DEST="$HOME/.local/bin"
mkdir -p "$DEST"

if command -v infodump >/dev/null 2>&1 && command -v txd >/dev/null 2>&1; then
  echo "ztools already present ($(command -v infodump)) — skipping"
  exit 0
fi

for req in git make cc; do
  command -v "$req" >/dev/null 2>&1 || { echo "missing build prereq: $req (run 00-core first)" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "cloning erkyrath/ztools…"
git clone --depth 1 -q https://github.com/erkyrath/ztools.git "$TMP/ztools"
( cd "$TMP/ztools" && make )

for b in infodump txd pix2gif check; do
  if [ -x "$TMP/ztools/$b" ]; then
    install -m 0755 "$TMP/ztools/$b" "$DEST/$b"
    echo "  installed $b -> $DEST/$b"
  fi
done

command -v infodump >/dev/null 2>&1 \
  && echo "ztools OK (ensure ~/.local/bin is on PATH)" \
  || { echo "ztools build failed" >&2; exit 1; }
