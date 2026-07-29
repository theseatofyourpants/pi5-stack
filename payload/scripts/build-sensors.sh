#!/usr/bin/env bash
# Sensor install: bettercap + Suricata (source) + Zeek (OBS repo)
# Run: bash ~/build-sensors.sh 2>&1 | tee ~/build-sensors.log

set -euo pipefail
JOBS=$(nproc)
echo "[*] $JOBS build jobs available"

# ─── Fix broken Docker apt repo (kali-rolling → bookworm) ─────────────────────
echo ""
echo "=== Fixing Docker apt repo ==="
if grep -q "kali-rolling" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
    sudo sed -i 's/kali-rolling/bookworm/g' /etc/apt/sources.list.d/docker.list
    echo "[+] Fixed: docker.list now uses bookworm"
fi

echo "[*] Running apt update..."
sudo apt-get update 2>&1 | grep -E "^Err|^W:" | head -10 || true
echo "[+] apt update done"

# ─── bettercap ────────────────────────────────────────────────────────────────
echo ""
echo "=== [1/3] bettercap ==="
if which bettercap > /dev/null 2>&1; then
    echo "[+] bettercap already installed: $(bettercap -version 2>&1 | head -1)"
else
    sudo apt-get install -y bettercap
    echo "[+] bettercap installed: $(bettercap -version 2>&1 | head -1)"
fi

# ─── Rust + cbindgen (required for Suricata 7.x) ──────────────────────────────
echo ""
echo "=== Rust toolchain ==="
if ! command -v cargo > /dev/null 2>&1; then
    echo "[*] Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --no-modify-path
    export PATH="$HOME/.cargo/bin:$PATH"
    echo "[+] Rust installed: $(rustc --version)"
else
    export PATH="$HOME/.cargo/bin:$PATH"
    echo "[+] Rust already installed: $(rustc --version)"
fi

if ! command -v cbindgen > /dev/null 2>&1; then
    echo "[*] Installing cbindgen..."
    cargo install cbindgen 2>&1 | tail -3
    echo "[+] cbindgen installed"
fi

# ─── Suricata from tarball (pre-generated configure, no autogen needed) ────────
echo ""
echo "=== [2/3] Suricata 7.0.10 from source ==="

echo "[*] Installing build dependencies..."
sudo apt-get install -y \
    build-essential pkg-config \
    python3-yaml \
    libpcap-dev libpcre2-dev libyaml-dev \
    libjansson-dev libmagic-dev zlib1g-dev \
    libmaxminddb-dev libnetfilter-queue-dev \
    liblzma-dev libluajit-5.1-dev \
    2>&1 | tail -5

echo "[*] Downloading Suricata 7.0.10 tarball..."
cd /tmp
rm -rf suricata-build
mkdir suricata-build && cd suricata-build
wget -q --show-progress \
    "https://www.openinfosecfoundation.org/download/suricata-7.0.10.tar.gz" \
    -O suricata-7.0.10.tar.gz
tar xzf suricata-7.0.10.tar.gz
cd suricata-7.0.10

echo "[*] Configuring (no DPDK, no XDP, no eBPF)..."
./configure \
    --prefix=/usr/local \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --disable-dpdk \
    --disable-ebpf \
    --disable-geoip \
    --with-libpcap-includes=/usr/include \
    2>&1 | tail -10

echo "[*] Building Suricata (~20-25 min on Pi 5)..."
make -j"$JOBS" 2>&1 | grep -v "^  CC\|^  CCLD\|^make\[" | tail -20

echo "[*] Installing..."
sudo make install 2>&1 | tail -3
sudo make install-conf 2>&1 | tail -3
sudo ldconfig

# Create required directories and a minimal config for IDS mode
sudo mkdir -p /var/log/suricata /var/run/suricata /var/lib/suricata/rules
sudo chown "$(id -un)":"$(id -gn)" /var/log/suricata /var/run/suricata 2>/dev/null || true

echo "[+] Suricata installed: $(suricata --version 2>&1 | head -1)"

# ─── Zeek from OpenSUSE Build Service (Debian 12 / arm64) ─────────────────────
echo ""
echo "=== [3/3] Zeek ==="

# Repo was added by previous run — check if it's already there
if ! grep -q "opensuse.*zeek" /etc/apt/sources.list.d/zeek.list 2>/dev/null; then
    echo '[*] Adding Zeek OBS repo...'
    echo 'deb [signed-by=/etc/apt/keyrings/zeek.gpg] https://download.opensuse.org/repositories/security:/zeek/Debian_12/ /' \
        | sudo tee /etc/apt/sources.list.d/zeek.list > /dev/null
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.opensuse.org/repositories/security:/zeek/Debian_12/Release.key \
        | sudo gpg --dearmor -o /etc/apt/keyrings/zeek.gpg
    sudo apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/zeek.list 2>&1 | tail -3
fi

echo "[*] Installing zeek from OBS repo..."
sudo apt-get install -y zeek 2>&1 | tail -5

if command -v zeek > /dev/null 2>&1 || command -v /opt/zeek/bin/zeek > /dev/null 2>&1; then
    ZEEK_BIN=$(which zeek 2>/dev/null || echo /opt/zeek/bin/zeek)
    echo "[+] Zeek installed: $($ZEEK_BIN --version 2>&1 | head -1)"
    # Add /opt/zeek/bin to PATH if that's where it landed
    if [[ "$ZEEK_BIN" == /opt/zeek* ]]; then
        echo 'export PATH="/opt/zeek/bin:$PATH"' | sudo tee /etc/profile.d/zeek.sh > /dev/null
        export PATH="/opt/zeek/bin:$PATH"
    fi
else
    echo "[!] Zeek OBS install failed. Building from source (~30 min)..."
    sudo apt-get install -y cmake flex bison libssl-dev python3-dev swig 2>&1 | tail -3
    cd /tmp
    rm -rf zeek-build
    git clone --recurse-submodules --depth=1 https://github.com/zeek/zeek.git zeek-build
    cd zeek-build
    ./configure --prefix=/usr/local --disable-broker-tests 2>&1 | tail -5
    echo "[*] Building Zeek (~30 min)..."
    make -j"$JOBS" 2>&1 | tail -10
    sudo make install 2>&1 | tail -3
    sudo ldconfig
    echo "[+] Zeek installed from source: $(zeek --version 2>&1 | head -1)"
fi

# ─── Suricata rules (ET Open) ──────────────────────────────────────────────────
echo ""
echo "=== Pulling Suricata ET Open rules ==="
if command -v suricata-update > /dev/null 2>&1; then
    sudo suricata-update 2>&1 | tail -5
else
    pip3 install --user suricata-update 2>&1 | tail -3
    sudo ~/.local/bin/suricata-update 2>&1 | tail -5
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo " SENSOR INSTALL COMPLETE"
echo "============================================"
if command -v bettercap > /dev/null 2>&1; then
    echo " bettercap: $(bettercap -version 2>&1 | head -1)"
else
    echo " bettercap: NOT INSTALLED"
fi
if command -v suricata > /dev/null 2>&1; then
    echo " suricata:  $(suricata --version 2>&1 | head -1)"
else
    echo " suricata:  NOT INSTALLED"
fi
ZEEK_BIN=$(which zeek 2>/dev/null || echo /opt/zeek/bin/zeek)
if [[ -x "$ZEEK_BIN" ]]; then
    echo " zeek:      $($ZEEK_BIN --version 2>&1 | head -1)"
else
    echo " zeek:      NOT INSTALLED"
fi
echo ""
echo "Next steps:"
echo "  Suricata: sudo suricata -c /etc/suricata/suricata.yaml -i eth0 -D --pidfile /var/run/suricata/suricata.pid"
echo "  Zeek:     sudo zeekctl deploy   (or: /opt/zeek/bin/zeekctl deploy)"
echo "  bettercap: sudo bettercap"
echo "============================================"
