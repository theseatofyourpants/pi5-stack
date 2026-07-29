#!/usr/bin/env bash
# Zeek install — diagnose first, then install non-interactively or build from source
# Run: bash ~/zeek-install.sh
set -uo pipefail

export DEBIAN_FRONTEND=noninteractive
JOBS=$(nproc)

echo "=== Zeek install (diagnostic mode) ==="
echo ""

# ─── Step 1: dry-run to see if OBS package is installable (no hang) ───────────
echo "[*] Dry-run: checking if OBS zeek package resolves cleanly..."
DRYRUN=$(sudo apt-get install -y --dry-run zeek 2>&1)
echo "$DRYRUN" | grep -E "would be|not going to be installed|Conflicts|held broken|Depends" | head -20

if echo "$DRYRUN" | grep -qE "not going to be installed|broken|Conflicts|Unable to"; then
    echo ""
    echo "[!] OBS package has a dependency conflict (same libc6 issue as before)."
    echo "[!] Falling through to source build."
    OBS_OK=0
else
    echo ""
    echo "[+] OBS package resolves cleanly — installing non-interactively..."
    OBS_OK=1
fi

# ─── Step 2a: OBS install if clean ────────────────────────────────────────────
if [[ "$OBS_OK" == "1" ]]; then
    sudo apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        zeek
    ZEEK_BIN=$(command -v zeek || echo /opt/zeek/bin/zeek)
    if [[ -x "$ZEEK_BIN" ]]; then
        echo "[+] Zeek installed via OBS: $($ZEEK_BIN --version 2>&1 | head -1)"
        [[ "$ZEEK_BIN" == /opt/zeek* ]] && echo 'export PATH="/opt/zeek/bin:$PATH"' | sudo tee /etc/profile.d/zeek.sh > /dev/null
        exit 0
    fi
    echo "[!] OBS install did not produce a working binary — falling back to source."
fi

# ─── Step 2b: Source build fallback ───────────────────────────────────────────
echo ""
echo "=== Building Zeek from source (~30-40 min on Pi 5) ==="
echo "[*] Installing build deps..."
sudo apt-get install -y \
    cmake make gcc g++ flex bison libpcap-dev libssl-dev \
    python3-dev swig zlib1g-dev libkrb5-dev 2>&1 | tail -4

cd /tmp
rm -rf zeek-build
echo "[*] Cloning Zeek (with submodules)..."
git clone --recurse-submodules --depth=1 https://github.com/zeek/zeek.git zeek-build
cd zeek-build

echo "[*] Configuring (prefix /opt/zeek)..."
./configure --prefix=/opt/zeek --generator=Ninja 2>&1 | tail -8 \
    || ./configure --prefix=/opt/zeek 2>&1 | tail -8

echo "[*] Building with $JOBS jobs — this is the long part..."
if command -v ninja > /dev/null 2>&1 && [[ -f build/build.ninja ]]; then
    ( cd build && ninja ) 2>&1 | tail -15
else
    make -j"$JOBS" 2>&1 | tail -15
fi

echo "[*] Installing..."
sudo make install 2>&1 | tail -3 || ( cd build && sudo ninja install 2>&1 | tail -3 )
sudo ldconfig
echo 'export PATH="/opt/zeek/bin:$PATH"' | sudo tee /etc/profile.d/zeek.sh > /dev/null

if [[ -x /opt/zeek/bin/zeek ]]; then
    echo "[+] Zeek built from source: $(/opt/zeek/bin/zeek --version 2>&1 | head -1)"
else
    echo "[-] Zeek build failed — check output above"
    exit 1
fi
