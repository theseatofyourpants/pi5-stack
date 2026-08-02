---
name: hw-bench
description: Physical hardware-hacking bench runbook for badge CTFs and embedded devices — UART discovery + baud identification, SPI/I2C flash dumping with flashrom/Bus Pirate/CH341A, logic-analyzer capture and protocol decode (UART/RS232, WS2812/NeoPixel, SPI), JTAG/SWD, and sensor triggers (thermistor hot/cold, Hall-effect magnet, IR transmit). Use when you have physical access to a badge/board and need to get data off it. Pairs with fw-triage (which analyzes the dump you pull).
---

# hw-bench — get data off the board

Physical bringup for a badge/board you can touch. Produces the dumps/streams that `fw-triage`, `ctf-rev`, and `ctf-forensics` then analyze. Log every irreversible step (photos) — trace cuts and desolders don't undo.

> [!warning] Match logic levels — most badges are **3.3 V**. A 5 V adapter can kill the MCU. Verify before connecting. Never de-auth WiFi in a venue (ban/legal risk).

## 1. UART — the first thing to find
Identify TX/RX/GND on a header or test pads (scope/logic-analyzer to spot the idle-high line that bursts at boot). Connect a **3.3 V USB-TTL** adapter (TX↔RX crossed).
```bash
picocom -b 115200 /dev/ttyUSB0        # try 115200 first
# unknown baud? sweep the common set — and the leet ones badges love:
for b in 9600 19200 38400 57600 115200 31337 1337; do
  echo "== $b =="; timeout 3 picocom -qrb $b /dev/ttyUSB0 | head -c 200; echo
done
```
Gotcha: some drivers **truncate ~20 chars** at non-standard baud (e.g. 31337) — verify against a partial flag, don't assume it's dead.

## 2. SPI flash dump (no desolder needed)
Clip a **SOIC-8 test clip** onto the flash chip (Winbond W25Q… is common on these badges). Read with a Pi/Bus Pirate/CH341A:
```bash
flashrom -p buspirate_spi:dev=/dev/ttyUSB0 -r dump.bin      # Bus Pirate
flashrom -p ch341a_spi -r dump.bin                          # CH341A programmer
flashrom -p linux_spi:dev=/dev/spidev0.0,spispeed=1000 -r dump.bin   # Pi SPI
```
Then hand `dump.bin` to the **fw-triage** skill (binwalk/strings/carve). If the flash is powered by the board, you may need to isolate it (pull the MCU's reset or power the clip only).

## 3. Logic analyzer — decode a protocol
Capture with `sigrok`/PulseView (or Saleae Logic). Built-in decoders cover the badge staples:
- **UART/RS232** — watch for LSB/MSB inversion and start/stop-bit tricks (DC28).
- **WS2812 / NeoPixel** — probe the last LED's data-in; decode 24-bit **GRB @ 800 kHz**; the "extra" LEDs carry ASCII (DC33).
- **SPI/I2C** — sniff flash/sensor traffic live if you can't clip-dump.
```bash
sigrok-cli -d fx2lafw --channels D0=data -c samplerate=4m --samples 4M -O csv > cap.csv
```

## 4. Sensor / trigger challenges
- **Thermistor:** apply heat (iron tip / heat gun) *or* cold (inverted canned air); watch UART/LEDs — the flag drops while temp is held, disappears when it normalizes.
- **Hall-effect:** hold a strong neodymium/horseshoe magnet near the sensor.
- **IR:** transmit the **exact** derived code (Flipper Zero / universal remote) — a generic TV-B-Gone sweep won't trigger it.

## 5. Surgery (last, irreversible — order matters)
Desolder the battery holder → **cut a trace** or **bridge pads** as the riddle dictates; check continuity with a multimeter before/after. Read **silkscreen hidden under the screen ribbon** (magnify; may be Wingdings). Many surgery flags re-emit on the **UART you enabled in §1** — keep it connected.

## Record & references
Save dumps/captures + a photo log under `~/engagements/ctf/<name>/`. Gear + buy links: [[AND-XOR-Hardware-Gear]]. Challenge context: [[AND-XOR-5n4ck3y]] §3.2/3.4/3.5.
