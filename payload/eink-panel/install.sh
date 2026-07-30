#!/usr/bin/env bash
# install.sh — set up the SEAT OPS e-ink panel ON THE PI ZERO 2 W. Run with sudo.
# Installs deps, enables SPI, vendors the Waveshare driver, and installs the service.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo:  sudo bash install.sh"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST=/opt/eink-panel

echo "[*] Installing dependencies…"
apt-get update -qq
apt-get install -y python3-pil python3-numpy python3-spidev git fonts-dejavu-core >/dev/null || true
# GPIO: RPi.GPIO on Bullseye; lgpio/gpiozero on Bookworm. Install both best-effort.
apt-get install -y python3-rpi.gpio >/dev/null 2>&1 || true
apt-get install -y python3-lgpio python3-gpiozero >/dev/null 2>&1 || true

echo "[*] Enabling SPI…"
raspi-config nonint do_spi 0 2>/dev/null || \
  echo "    (enable SPI manually: raspi-config → Interface Options → SPI → Yes, then reboot)"

echo "[*] Vendoring the Waveshare e-Paper driver (waveshare_epd)…"
if ! python3 -c "import waveshare_epd" 2>/dev/null; then
  tmp="$(mktemp -d)"
  git clone --depth 1 https://github.com/waveshareteam/e-Paper "$tmp/e-Paper" >/dev/null 2>&1
  SRC="$tmp/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd"
  SITE="$(python3 -c 'import site; print((site.getsitepackages() or ["/usr/lib/python3/dist-packages"])[0])')"
  cp -r "$SRC" "$SITE/" && echo "    installed waveshare_epd -> $SITE"
  rm -rf "$tmp"
else
  echo "    waveshare_epd already importable — skipping"
fi

echo "[*] Installing the panel…"
install -d "$DEST"
install -m0755 "$HERE/panel.py" "$DEST/panel.py"
if [ ! -f /etc/eink-panel.conf ]; then
  install -m0600 "$HERE/panel.conf.example" /etc/eink-panel.conf
  echo "    >> EDIT /etc/eink-panel.conf : set PI5_URL, PANEL_TOKEN, and EPD_DRIVER"
fi
install -m0644 "$HERE/eink-panel.service" /etc/systemd/system/eink-panel.service
systemctl daemon-reload
systemctl enable eink-panel.service >/dev/null 2>&1 || true

cat <<EOF

==================================================================
 e-ink panel installed.

 1. Edit the config (Pi 5 URL + scoped token + your HAT revision):
      sudo nano /etc/eink-panel.conf
      # PANEL_TOKEN comes from the Pi 5:  cat ~/ap-testbed/state/panel.token
      # EPD_DRIVER: epd2in13_V4 (default) / _V3 / _V2

 2. Test the layout WITHOUT hardware (writes a PNG):
      python3 $DEST/panel.py --mock /tmp/panel.png --sample

 3. Start it:
      sudo systemctl start eink-panel
      journalctl -fu eink-panel     # watch for fetch/driver errors

 Blank/garbled screen => wrong EPD_DRIVER for your HAT. Upside down => ROTATE=180.
==================================================================
EOF
