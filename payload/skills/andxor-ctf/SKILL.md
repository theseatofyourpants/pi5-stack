---
name: andxor-ctf
description: Playbook for the AND!XOR / 5n4ck3y / BENDER badge CTF at DEF CON — the phygital badge-hacking contest (Zork-style on-badge adventure + vending-machine dispense codes). Recognize which recurring challenge type you're on (stacked classical crypto, POCSAG/RF, UART @ odd baud, thermistor/Hall/IR sensor triggers, WS2812/flash-dump hardware surgery, Shakespeare/esolang, phreak coin-tones, Z-machine RE) and go straight to the decode recipe + exact tooling. Use for AND!XOR badges or any similar hardware badge CTF. Fills the bench-work gap between ctf-rev and ctf-forensics.
---

# andxor-ctf — AND!XOR / 5n4ck3y / BENDER playbook

Deep reference: [[AND-XOR-5n4ck3y]]; gear: [[AND-XOR-Hardware-Gear]] (in the pi_design vault / repo `docs/ctf-references/`). This skill is the **fast path**: identify the recurring pattern, jump to the recipe. Pairs with `ctf-triage` (front door), `ctf-rev` (Ghidra/angr), `ctf-forensics` (binwalk/stego), `nudge` (pinball).

## Mental model
- **BENDER** = Zork-style text adventure *on the badge*; walking the map / talking to NPCs *is* how you find the next challenge. Read room + object + NPC text carefully — hints are in there.
- **5n4ck3y** = physical vending machine. Puzzle → **dispense code** → machine vends a badge or prints an **NFT/QR** to the next stage. Some flags are **phygital** (need the machine, an off-site venue, or internet).
- Storyline: **"Save Matt Damon"** — `MATTDAMON` is a recurring key/passphrase. Keep a scratch dir: `~/engagements/ctf/andxor-<year>/`.

## Recognize → recipe

**Stacked classical crypto** (the #1 pattern — never just one layer)
- Suspect: text that decodes partway then still looks encoded. Try **CyberChef**-style chains: ROT13 → Base64 → Braille → Morse → XOR; or Baconian/Vigenère/Bifid/Atbash/Polybius(keyword, I=J).
- **Repeating-key XOR w/ known prefix:** key = `ciphertext[:len("flag{")] XOR "flag{"`, then repeat.
  ```python
  ct=bytes.fromhex(H); k=bytes(a^b for a,b in zip(ct,b"flag{"))
  print(bytes(c^k[i%len(k)] for i,c in enumerate(ct)))
  ```
- Keys are often earned in-game (an NPC name, `DEFCON`, `MATTDAMON`, `JACKPOT`).

**RF / pager (POCSAG/FLEX)** — ~900–925 MHz
```bash
rtl_fm -f 929.6M -s 22050 - | multimon-ng -t raw -a POCSAG512 -a POCSAG1200 -a FLEX -f alpha -
```
Output is often a **T9 phone number** → *call it* → **reversed voicemail** → reverse in Audacity. LoRa/Meshtastic (915 MHz) appeared DC33 — connect a node, DM the 5n4ck3y BBS.

**UART console** — hidden on nearly every badge
- 3.3 V USB-TTL to RX/TX/GND. Try **115200** first, then odd rates (**31337** at DC33). `picocom -b 31337 /dev/ttyUSB0`.
- Gotcha: some drivers **truncate ~20 chars** at non-standard baud — verify against a partial flag.

**Sensor triggers**
- **Thermistor:** heat (iron tip) or cool (inverted canned air); watch UART/blink — flag drops while temp held.
- **Hall-effect:** strong neodymium/horseshoe magnet near the sensor.
- **IR:** derive the code (arithmetic in the hint), then transmit the **exact Sony code** via Flipper/universal remote (a TV-B-Gone sweep won't work).

**Hardware surgery (post-badge "Phase 2")** — irreversible, order matters
- **SPI flash dump:** SOIC-8 clip on the Winbond chip → `flashrom -p buspirate_spi:dev=/dev/ttyUSB0 -r dump.bin` → `binwalk -e dump.bin` → grep hidden `.txt`.
- **WS2812/NeoPixel:** logic analyzer on the last data pin → decode 24-bit **GRB @ 800 kHz** → ASCII.
- **Trace cut / pad bridge** under battery holder; **Wingdings silkscreen** under the screen ribbon (magnify + map).

**Esolang / phreak / stego**
- **Shakespeare Programming Language:** run for flag A; **invert one conditional** (`If so`→`If not`) for flag B.
- **Coin tones → ASCII:** cent value = ASCII code (65→`A`). Analyze WAV in Audacity.
- **PNG stego:** repair magic bytes in a hex editor → `steghide extract` → payload is a **transparency mask** to **overlay** on the original image.

**Z-machine RE** (the BENDER `.z5` itself)
- Disassemble the story file to find inaccessible/"purgatory" rooms & embedded data: `txd`, `infodump` (ztools), or a Z-machine disassembler. Hand heavy RE to `ctf-rev`.

## Gotchas (see [[AND-XOR-5n4ck3y]] §6)
- **Never de-auth WiFi in Vegas** — venue ban / legal risk (badge default `Matt Damon`/`WEmustSAVEhim`).
- Naive **firmware dumps can cost points** (DC28 −1000) — follow the intended path.
- **Sewer mazes** are anti-bot; map by hand. Log/photo every irreversible mod.

## Practice
No live server after con — reverse the year's firmware from `github.com/ANDnXOR`. Pinball challenges recur → `nudge` skill + `defcon-pinball-ctf` memory.
