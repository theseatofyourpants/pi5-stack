---
title: "Badge-CTF Hardware Gear — Field Kit"
tags: [ctf, reference, hardware, gear, defcon, andxor, rf, sdr, hardware-hacking]
updated: 2026-08-02
---

# Badge-CTF Hardware Gear — Field Kit

The physical tooling that recurs across AND!XOR / 5n4ck3y (and badge CTFs generally — MCH, SHA, Hackaday Supercon). Companion to **[[AND-XOR-5n4ck3y]]** §7. Each entry: what it's for, which challenge type it unlocks, a rough price band, and a link/example.

> [!note] Links & images
> Product/reference links are external and may rot — they're examples, not endorsements. Image thumbnails are hotlinked from the vendor/Hackaday; if a badge is offline they simply won't render in Obsidian. The **DEF CON badge photo galleries live on the Hackaday project pages** linked at the bottom.

> [!tip] Priority buy order (if starting from zero)
> 1. **USB-TTL serial adapter** (CP2102/FTDI) — used almost every year.
> 2. **RTL-SDR v4** — POCSAG/pager decode is a staple.
> 3. **Logic analyzer** (cheap 8-ch or Saleae) — UART/WS2812/RS232.
> 4. **SOIC-8 test clip + Bus Pirate** — flash dumps.
> 5. **Flipper Zero** — IR/RF/sub-GHz swiss-army convenience.
> 6. **Meshtastic node** — appeared DC33; likely to recur.

---

## Serial / logic

### USB-to-TTL serial adapter (CP2102 / FTDI FT232 / CH340)
- **For:** the UART console hidden on nearly every badge (DC30 @115200, DC33 @31337 baud). RX/TX/GND to the badge header.
- **Watch:** match **3.3 V** logic (most badges) — a 5 V adapter can damage the MCU. Get one with a voltage jumper. Non-standard baud (31337) may truncate on some drivers.
- **~$8–12.** Example: [Adafruit CP2102 friend](https://www.adafruit.com/product/954) · [SparkFun FTDI Basic 3.3V](https://www.sparkfun.com/products/9873)

### Logic analyzer
- **For:** decoding **RS232/UART** (DC28), **WS2812/NeoPixel** data lines (DC33), any unknown digital protocol. Use `sigrok`/**PulseView** or Saleae Logic; both have WS2812 & UART decoders built in.
- **Budget:** generic 8-ch 24 MHz clone (~$10). **Nicer:** [Saleae Logic 8](https://www.saleae.com/) (~$400+). The clone is enough for badge speeds.
- ![Logic analyzer](https://sigrok.org/w/images/9/9e/Fx2lafw-generic.jpg)

### Soldering iron + fine tip / hot-air
- **For:** desoldering battery holders, cutting/bridging traces (DC33 Phase 2), tacking wires to test pads, applying **heat to a thermistor**.
- A temperature-controlled iron (Pinecil / TS101 / Hakko) + flux + solder wick. Hot-air station helps for SOIC removal.
- **~$40–100.** Example: [Pinecil V2](https://pine64.com/product/pinecil-smart-mini-portable-soldering-iron/)

---

## RF / wireless

### RTL-SDR (v4 recommended)
- **For:** capturing **POCSAG/FLEX pager** transmissions (~900–925 MHz) — a near-annual challenge. Pipe to **multimon-ng**; visualize in **gqrx** / SDR#.
- **~$35.** Example: [RTL-SDR Blog V4](https://www.rtl-sdr.com/buy-rtl-sdr-dvb-t-dongles/)
- ![RTL-SDR dongle](https://www.rtl-sdr.com/wp-content/uploads/2013/04/rtl-sdr-v3-1.jpg)
- **Decode recipe:** `rtl_fm -f 929.6M -s 22050 - | multimon-ng -t raw -a POCSAG512 -a POCSAG1200 -a FLEX -f alpha -`

### Flipper Zero
- **For:** convenience swiss-army — **IR transmit** (exact Sony codes, DC33), sub-GHz capture/replay, NFC/125 kHz, GPIO/UART bridge, iButton. Replaces several single-purpose gadgets on the show floor.
- **~$169.** Example: [flipperzero.one](https://flipperzero.one/)
- ![Flipper Zero](https://cdn.flipperzero.one/Product-1.png)

### Meshtastic node (LoRa, 915 MHz US)
- **For:** DC33 used Meshtastic as a whole delivery channel (BBS, foxhunt, radio buffer-overflow). Any US-915 Meshtastic board works (Heltec V3, LilyGo T-Beam, RAK WisBlock).
- **~$25–45.** Example: [meshtastic.org supported hardware](https://meshtastic.org/docs/hardware/devices/)

### (Optional) HackRF / universal remote
- **HackRF One** (~$150) for TX-capable / wider-band work beyond RX-only RTL-SDR. A cheap **universal IR remote** is a fine low-tech substitute for the Flipper on IR challenges.

---

## Flash / PCB / chip

### SOIC-8 test clip ("chip clip")
- **For:** clipping onto the **Winbond SPI flash** to dump firmware without desoldering (DC33 Phase 2 — the walkthrough even nicknames it "Ch1pQu1k's chip clips"). Pair with a **Bus Pirate**, a **CH341A** programmer, or a Raspberry Pi + `flashrom`.
- **~$5–15 (clip)**, **~$3 (CH341A)**, **~$30 (Bus Pirate)**. Example: [Pomona 5250 SOIC-8 clip](https://www.digikey.com/en/products/detail/pomona-electronics/5250/745103) · [Bus Pirate](http://dangerousprototypes.com/docs/Bus_Pirate)
- ![SOIC-8 clip](https://cdn-shop.adafruit.com/970x728/1550-00.jpg)
- **Dump recipe:** `flashrom -p buspirate_spi:dev=/dev/ttyUSB0 -r dump.bin` → `binwalk -e dump.bin` → grep for the hidden `.txt`.

### Ch1pQuik / low-melt solder
- **For:** clean removal of the battery holder / SMD parts before cutting traces or bridging pads. The DC33 puzzle prop is literally named after it.
- **~$15.** Example: [Chip Quik SMD removal kit](https://www.chipquik.com/store/product_info.php?products_id=1010)

### Multimeter + hobby knife + tweezers + magnifier
- **For:** continuity-checking traces before/after a cut, the **trace-cut / pad-bridge** surgery, and reading the **Wingdings silkscreen under the screen ribbon** (DC33). A cheap USB microscope (~$30) beats a loupe for silkscreen.
- Fine-tip **hobby knife** (X-Acto) for the trace cut; ESD tweezers for SMD.

### Magnet (Hall-effect trigger)
- **For:** DC33 Hall-effect challenge — a strong **neodymium** or horseshoe magnet held near the sensor. Any N42+ button magnet works.

### Environmental — canned air + heat
- **For:** **thermistor** challenges — **inverted canned air** (cold) or the soldering-iron tip / heat gun (hot). Hold the temperature; the flag drops out when the sensor normalizes.

---

## Consumables / kit hygiene

- **Dupont jumper wires** (M-M / M-F / F-F), fine **magnet wire** for tack-ons.
- **3.3 V logic** awareness — verify before connecting anything.
- **Breadboard + USB power bank** for bench work away from a desk.
- **Label + bag artifacts** per challenge; keep a photo log of every irreversible mod (trace cuts don't undo).

---

## DC34 (2026) packing list & current kit

Tailored to the AND!XOR / 5n4ck3y challenge families above; tiered by value, mapping the current kit against the gaps.

### Current kit
- **FreeWili2** — *picking up at DC34.* RP2350 + FPGA, Python-programmable hardware multitool: GPIO / UART / SPI / I2C bit-bang, IR, buttons + display, some sub-GHz RF. Covers much of the serial / IR / GPIO surface. ⚠ **Verify its final RF + logic-analyzer specs** — that decides whether the SDR / standalone analyzer below are still needed (assume not-wideband for now).
- **Waveshare USB-to-TTL** — dedicated 3.3 V serial line. **Set the jumper to 3.3 V before touching a badge.** The reliable UART path when the FreeWili is busy; keep spare jumper leads.
- **CH341A + SOIC8 clip kit** (ACEIRMC, [amazon B07V2M5MVH](https://www.amazon.com/dp/B07V2M5MVH)) — CH341A programmer + SOIC8/SOP8 test clip + **1.8 V adapter** + SOP8→DIP8 socket. Covers the whole **SPI-flash-dump** line in one box. ⚠ the classic CH341A drives ~5 V on its data pins even at 3.3 V VCC — fine for *reading* most 25-series 3.3 V flash; use the 1.8 V adapter for 1.8 V chips; consider the 3.3 V I/O mod for sensitive parts. `flashrom -p ch341a_spi -r dump.bin`.
- **Software toolchain** — already installed on the Pi 5 stack (dfrotz / infodump / txd, ghidra, radare2, multimon-ng, steghide, sox, foremost, picocom, sigrok-cli, hashcat / john; pycryptodome as **`Cryptodome`**). Reproduced by the `55-ctf-tools` layer — see [[AND-XOR-5n4ck3y]] §8.

### Tier 1 — real gaps (buy)
- **RTL-SDR v4 + ~900 MHz whip/telescopic antenna** — POCSAG/FLEX pager decode; the FreeWili's radio won't demod it. RX-only, ~$35.
- ✅ **SPI flash dump** — covered by the CH341A + SOIC8 kit above.
- **IC-hook / grabber probe clips + Dupont jumpers** (M-M / M-F / F-F) — probe pads & header pins **without soldering**; pairs with both the Waveshare and FreeWili. Cheapest, highest-convenience item.

### Tier 2 — surgery kit (for the hardware-hacking challenges)
Portable iron (Pinecil / TS101, USB-C) + solder / **flux** / desolder wick + **Chip Quik** low-melt (clean battery-holder removal); fine tweezers, flush cutters, **X-Acto** (trace cuts), pocket **multimeter** (continuity before/after a cut), **loupe or clip-on USB microscope** (Wingdings silkscreen under the ribbon). Solder at the Hardware Hacking Village, not on hotel carpet.

### Tier 3 — cheap, challenge-specific
- Strong **neodymium magnet** — Hall-effect triggers.
- **Canned air** for thermistor-**cold** — *buy in Vegas* (TSA hassle); the iron covers thermistor-hot.
- **Flipper Zero** *if owned* — exact-code IR + sub-GHz + NFC (else the FreeWili's IR likely covers it).
- **Meshtastic node** (Heltec V3 / T-Beam, **915 MHz US**) — DC33 ran a Meshtastic BBS; decent odds it recurs.

### Tier 4 — logistics that make or break the weekend
Known-good USB-C **data** cables (label them — charge-only cables are the #1 time-sink) · USB **battery bank** · powered **USB hub** · A↔C adapters · **microSD + reader** · laptop/Pi with the toolchain · **notebook + Sharpie + parts bags** (photo every irreversible mod).

**Don'ts:** no WiFi **de-auth** (venue ban / legal risk) · never rely on a single cable or power path.

## Badge photo galleries & references (images live here)

- [AND!XOR DC26 badge — Hackaday](https://hackaday.io/project/28389-andxor-dc26-badge) (photos, teardown)
- [AND!XOR DC28 badge — Hackaday build logs](https://hackaday.io/project/173627/logs)
- [AND!XOR DC25 badge — Hackaday](https://hackaday.io/project/19121-andxor-dc25-badge)
- [Hands-on: AND!XOR DC26 badge — Hackaday blog](https://hackaday.com/2018/07/30/hands-on-andxor-def-con-26-badge/)
- [ANDnXOR GitHub org (firmware, schematics, KiCad)](https://github.com/ANDnXOR) — pull a year's repo for board photos + pinouts
- [AND!XOR shop (current badges/SAOs)](https://shop.andnxor.com/)

## Related
- [[AND-XOR-5n4ck3y]] — the challenge-mechanics reference this kit serves
- [[CTF-Toolkit]] · [[Autonomous-AP-Testbed]] (bench RF gear overlaps)
