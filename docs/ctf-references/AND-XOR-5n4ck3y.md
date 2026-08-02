---
title: "AND!XOR 5n4ck3y / BENDER — CTF Reference"
tags: [ctf, reference, defcon, andxor, 5n4ck3y, bender, hardware, crypto, rf]
event: "DEF CON — AND!XOR indie badge + 5n4ck3y contest"
updated: 2026-08-02
---

# AND!XOR 5n4ck3y / BENDER — CTF Reference

Field guide for the **AND!XOR** indie-badge CTF and its vending-machine sidekick **5n4ck3y**. Focus: the *recurring* mechanics, the gotchas that burn people, and the exact tooling to bring — so a new year's challenges feel familiar. Drives the `andxor-ctf` skill (see [[Stack-Ops-Skills]] / [[CTF-Toolkit]]).

> [!warning] Source confidence
> Synthesized 2026-08-02 from the AND!XOR GitHub org, the Hackaday build logs (DC25–DC30), the DEF CON contest pages, and the `5N4CK3Y_DC33_WALKTHROUGH.md` committed to the DC33 badge repo. **Mechanics & tooling patterns are reliable and repeat year-over-year; exact flag strings / point values are indicative** (post-con reconstructions, treat as illustrative). Verify the current year's rules at the DEF CON contest page — 5n4ck3y is spun **down after each con**, so there is no always-on practice server.

---

## 1. What it is

Two intertwined systems carry the CTF:

- **BENDER** — *Badge Enabled Non-Directive Enigma Routine*. A **Zork-style Z-machine text adventure that runs on the badge itself** and is the connective tissue for every puzzle. You walk a virtual Vegas map, pick up objects, talk to NPCs; each "room" gates a real-world challenge. The format since ~DC24, still current at DC33.
- **5n4ck3y** ("snackey") — an ammo-can **vending machine** + web CTF (CTFd). Solve a puzzle → get a **dispense code** → punch it into the physical machine → it vends a badge, or increasingly prints an **NFT/QR** linking to the *next* stage.

The defining property: challenges are **phygital** — part in-game, part web, part hands-on-hardware. You can't solve everything from a hotel room; some flags need the physical machine, an announced off-site venue, or internet access for a QR/Dropbox link.

Storyline running gag: **"Save Matt Damon."** `MATTDAMON` recurs as a passphrase/cipher key; his face/keychain appear as puzzle props. Futurama's **Bender** is the mascot.

---

## 2. Badge lineage (what to reverse for practice)

All firmware is on GitHub under [`ANDnXOR/`](https://github.com/ANDnXOR). Since there's no live practice server, **the firmware repos are the practice material** — reverse the `.z5` story file or the MicroPython app.

| Year | Repo / platform | Notes |
|------|-----------------|-------|
| DC24 | `ANDnXOR_DC24_Badge` (C) | UART console; solve puzzles → unlock badge features |
| DC25 | (Hackaday `19121`) | Wireless console over a phone app (too remote — reverted after) |
| DC26 | (Hackaday `28389`) | Back to embedded console; single-player focus; color screen; BLE cross-badge tie-ins |
| DC27 | (Hackaday `164346`) | |
| DC28 | `ANDnXOR_DC28_Badge` (C) | Rich documented CTF (see §4) |
| DC30 | LilyGo **T-Watch ESP32**, custom MicroPython 1.18 ("Chomper" smartwatch) | picocom @115200 to `/dev/ttyACM0`; `config.json` survives flashes |
| DC31 | `ANDnXOR_DC31_Badge` (Python) | |
| DC32 | `ANDnXOR_DC32_Badge` (C) | 5n4ck3y: solve any 5 of 15 → HackBoi badge |
| DC33 | `ANDnXOR_DC33_Badge` | Full `5N4CK3Y_DC33_WALKTHROUGH.md` in-repo; 36 challenges, 2 phases (see §5) |

---

## 3. Recurring themes — the pattern language

Drill these and you're prepared regardless of year:

### 3.1 Multi-layer classical crypto chains
Never one cipher — always **stacked**, and often keyed with something you had to earn.
- DC28 Ch9: `ROT13 → Base64 → Braille → Morse → XOR`.
- DC33 "NPC-crets": `Baconian`, `Vigenère(key)`, `Bifid(key)`, `Atbash→Hex→Base64` — one layer per NPC, then assemble words into a passphrase.
- **Signature move:** repeating-key XOR where the key is recovered from the **known `flag{` prefix** — XOR the first N ciphertext bytes with `flag{` to reveal the key (DC33 Ch5: key `MATTD`).
- Polybius square with a **keyword** (`DEFCON`, I=J rule), coordinates delivered by **Morse** (a blinking LED / HAL's eye).

### 3.2 Serial / UART — the rite of passage
Nearly every badge hides content on a **UART console**.
- DC30: picocom @ **115200** to `/dev/ttyACM0`.
- DC33: a *hidden* UART at a **non-standard 31337 baud** ("locusts talk at a leet rate").
- DC28 Ch5: raw **RS232** decode on a logic analyzer with **LSB/MSB inversion** and start/stop-bit gotchas.

### 3.3 RF / SDR
- **POCSAG/FLEX pager** decode recurs (DC28 Ch7, DC33 Ch3): capture ~**900–925 MHz** with an SDR, decode with **multimon-ng**. Output is frequently a **T9-encoded phone number** you *actually call* → hear a **reversed voicemail** → reverse it in Audacity for the code.
- DC33 added **LoRa / Meshtastic** (915 MHz) as a whole delivery channel — including a **buffer overflow via radio message** (`4294967295` = max uint32 into a game input).

### 3.4 Environmental / sensor triggers
- **Thermistor:** heat it (soldering-iron tip / heat gun) *or* cool it (inverted canned air) to change a blink rate or unlock a UART flag. Flag disappears when temp normalizes — keep it held. (DC26/DC28/DC33)
- **Hall-effect:** hold a strong magnet near the sensor (DC33 "golden Matt Damon keychain").
- Light sensor, accelerometer tilt, vibration motor as output.

### 3.5 Hardware surgery (DC33 "Phase 2" — post-badge)
Gets physical and often **irreversible** — do steps in order, many later flags depend on the UART you enabled earlier:
- **SPI flash dump:** SOIC-8 clip on the **Winbond** chip → `flashrom`/Bus Pirate → `binwalk` → find a hidden `.txt`.
- **Cut a trace** / **bridge pads** under the battery holder (desolder holder first).
- **Silkscreen under the screen ribbon**, written in **Wingdings** — magnify + transcribe + decode.
- **WS2812 / NeoPixel** data-line sniff with a logic analyzer → decode 24-bit **GRB @ 800 kHz** timing → ASCII in the "extra" LEDs.

### 3.6 Steganography + file repair
- **Corrupt PNG header** you fix in a hex editor (magic bytes) → `steghide` extract → the payload is a **transparency mask** you **overlay** on the original image to reveal text (DC33 Ch6). LSB stego also appears.

### 3.7 Esoteric languages & phreaking
- **Shakespeare Programming Language:** run the script for flag A, then **invert one conditional** (`If so` → `If not`) and re-run for flag B.
- **Red/blue-box coin tones → ASCII** (cent value = ASCII code: 65→`A`). Simulated phone trees / elevator "phreaking" with specific extensions.

### 3.8 IR
- Derive a code by arithmetic, then **transmit a specific Sony IR command** (Flipper Zero or a universal remote). Must be the **exact** code — a generic TV-B-Gone sweep won't trigger it.

### 3.9 OSINT + easter eggs
- **Photo-OSINT** a hotel/location from background details, then act on it (DC33 GPS-spoof a foxhunt).
- Easter eggs seeded across **Twitter, the GitHub repos, video content, and physical merch**. DC28 shipped ~36 hidden ones.

---

## 4. Worked reference — DC28 (well-documented year)

| # | Category | Mechanic |
|---|----------|----------|
| 0 | OSINT | Social-media hunt → `420-69-1337` |
| 1 | Cipher | BlackBerry-keyboard directional shift |
| 4 | Sensor + Morse | Cool the **thermistor** to slow a blink → Morse |
| 5 | UART | **RS232** decode, LSB/MSB inversion |
| 7 | RF | **POCSAG** pager over **SDR** |
| 8 | Cracking | **NTLM** hashes from a Win2000 SAM |
| 9 | Crypto chain | ROT13→Base64→Braille→Morse→**XOR** |
| — | Phreaking | Elevator phone system (ext. 4177/2323/1337) |

**Landmine:** naive firmware extraction docked **−1000 pts** — the scoring rewarded the *intended* learning path over brute point-grabbing.

---

## 5. Worked reference — DC33 (most recent, full walkthrough in-repo)

36 challenges, **Phase 1** (17, need 5 for the badge) then **Phase 2** (19, unlocked post-badge via AES256). Representative slice:

**Phase 1 (in-game + web + RF):**
- LoRa/Meshtastic buffer overflow (`4294967295`) · GPS foxhunt + photo-OSINT + GPS spoof · POCSAG→phone-call→reversed-audio · Shakespeare Programming Language (run, then invert branch) · Z-machine hidden "purgatory" room + repeating-XOR (`flag{`→key) · PNG-repair→steghide→overlay-mask stego · distributed NPC cipher chain (Baconian/Vigenère/Bifid/Atbash) · **pinball** challenges (Dune, Labyrinth, off-site Crabfoam) · HAL's-eye Morse→Polybius(`DEFCON`) · red-box coin-tones→ASCII · casino-chip hex-slices→keyed-XOR · IR-arithmetic→Sony-code transmit.

**Phase 2 (hardware surgery):**
- Hidden UART @ **31337 baud** · cut trace under battery holder · bridge pads · **SPI flash dump** → binwalk → `.txt` · **Wingdings** silkscreen under ribbon · **WS2812** logic-analyzer decode · **thermistor** hot *and* cold · **Hall-effect** magnet.

Pinball tie-in is directly relevant to the [[CTF-Toolkit]] `nudge` work — AND!XOR literally uses pinball machines as flag sources.

---

## 6. Gotchas that burn people

- **31337 (and other oddball) baud:** some adapters/terminals silently **truncate after ~20 chars** — verify against a partial flag before assuming it's broken.
- **Firmware-dump landmines:** naive flash extraction can *cost* points (DC28 −1000). Read the intended path first.
- **De-auth = venue ban.** DC30 manual is explicit: do **not** use badge WiFi-attack features in Vegas — real legal/expulsion risk. Default WiFi creds `Matt Damon` / `WEmustSAVEhim`; settings in `config.json` survive flashes.
- **Physical irreversibility:** trace cuts / desoldering permanently change badge behavior. Order matters — later flags often need an earlier-enabled UART.
- **Sewer mazes** are intentionally disorienting (11–16 rooms) to defeat auto-mappers/bots — map by hand.
- **Phygital dependency:** some flags need the physical 5n4ck3y machine, an announced off-site arcade, or internet (NFT/Dropbox QR).
- **Exact-signal challenges:** IR and RF want the *precise* code/frequency, not a sweep.
- **ampy is slow:** MicroPython file transfer (~1 min / 100 KB) on the ESP32 badges — batch your pushes.

---

## 7. Tooling checklist (by category)

| Category | Reach for |
|----------|-----------|
| Serial / UART | `picocom` / `minicom` / PuTTY, USB-TTL adapter, **logic analyzer** (Saleae / `sigrok`+PulseView), soldering iron |
| RF | RTL-SDR + **gqrx** / `rtl_433`, **multimon-ng** (POCSAG/FLEX), Flipper Zero, Meshtastic node (915 MHz) |
| Flash / PCB | **SOIC-8 clip**, Bus Pirate / Raspberry Pi, **flashrom**, **binwalk**, hex editor, multimeter, hobby knife |
| RE | **Ghidra** / Cutter / radare2, **Z-machine disassembler** (`txd`, `infodump`, ztools) for `.z5`, `angr` for keygen-style checks |
| Crypto | **CyberChef** (workhorse for stacked chains), Vigenère/Bifid/Baconian/Polybius solvers, XOR-known-plaintext script |
| Stego | `steghide`, `zsteg`, `exiftool`, `binwalk`, image editor for overlay masks |
| Audio / phreak | **Audacity** (reverse + spectrogram), DTMF / coin-tone decoders |
| IR | Flipper Zero or universal remote (exact Sony codes) |
| Esolang | Shakespeare Programming Language interpreter (Python pkg) |

Physical gear detail, links, and examples: **[[AND-XOR-Hardware-Gear]]**.

> [!note] Rebuild coverage
> This whole toolchain is reproduced by the opt-in `pi5-stack` layer **`55-ctf-tools`** (apt: frotz, multimon-ng, steghide, sox, foremost, picocom, rtl-sdr/433, sigrok-cli, ghidra, python3-pycryptodome/gmpy2/pwntools) + a user-space **ztools** build (`payload/scripts/install-ztools.sh`, since `infodump`/`txd` aren't apt-installable). On Debian, pycryptodome imports as **`Cryptodome`**, not `Crypto`.

---

## 8. How it maps to this stack

| Track | Route to |
|-------|----------|
| Fingerprint / classify a dropped file | `ctf-triage` skill |
| Ghidra/radare2/angr + **Z-machine `.z5`** disassembly | `ctf-rev` agent |
| `binwalk`/`steghide`/`exiftool`/flash-dump/WS2812 decode | `ctf-forensics` agent |
| Stacked classical crypto, RF/pager decode, phreak audio, IR, esolang | **`andxor-ctf` skill** (the bench-work gap between rev & forensics) |
| Pinball / nudge-cipher flags | `nudge` skill · project-memory `defcon-pinball-ctf` |

Keep artifacts per challenge in `~/engagements/ctf/<name>/`.

## Related
- [[AND-XOR-Hardware-Gear]] — gear list with links/examples
- [[CTF-Toolkit]] · [[Stack-Ops-Skills]] · [[Operator-Skills]]
- Sources: [github.com/ANDnXOR](https://github.com/ANDnXOR) · [DC33 badge repo](https://github.com/ANDnXOR/ANDnXOR_DC33_Badge) · [DC28 build logs](https://hackaday.io/project/173627/logs) · [DC26 badge](https://hackaday.io/project/28389-andxor-dc26-badge) · [5n4ck3y — DEF CON Forums](https://forum.defcon.org/node/245451)
