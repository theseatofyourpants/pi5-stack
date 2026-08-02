---
name: fw-triage
description: Triage a firmware image, flash dump, or embedded-device / badge code repo — identify the architecture and format (ELF/PE, raw MCU image, SPI flash dump, filesystem, Z-machine story, MicroPython), carve embedded files, pull strings/flags/keys, map the memory layout, and route to the right RE/forensics specialist. Use on any unknown firmware blob, a chip dump (flashrom output), or a badge-CTF firmware repo. Pairs with hw-bench (which produces the dump) and ctf-rev/ctf-forensics (which go deep).
---

# fw-triage — make sense of an unknown firmware blob

Fast structural understanding before deep RE. Input is a `.bin`/`.img`/flash dump, an ELF/`.uf2`/`.hex`, or a badge repo. Output: what it is, where the interesting parts are, and who solves it. Scratch dir: `~/engagements/ctf/<name>/` or `~/engagements/fw/<name>/`.

## 1. Fingerprint
```bash
file fw.bin; ls -l fw.bin
binwalk fw.bin                     # signatures: filesystems, compression, embedded files, bootloaders
strings -n 8 fw.bin | grep -iE 'flag|ctf|key|passw|http|ssid|version|\{' | head -40
xxd fw.bin | head                  # magic bytes, load address hints, padding pattern (0xFF = erased flash)
```
Recognize common headers: `7f 45 4c 46` ELF · `UF2\n`/`0x0A324655` UF2 (RP2040) · SquashFS/JFFS2/UBI/CramFS (Linux fs) · `d1 e5` MicroPython `.mpy` · `Infocom / Z-machine` story (`.z5`) · Intel-HEX `:` lines.

## 2. Carve & extract
```bash
binwalk -e fw.bin                  # auto-extract to _fw.bin.extracted/
# entropy check — a flat high-entropy region = encrypted/compressed, not code:
binwalk -E fw.bin
```
If `binwalk -e` misses it, carve manually with `dd` at the offsets binwalk reported. For a **raw MCU image** (no filesystem), there's nothing to extract — it goes straight to RE (§4).

## 3. Classify the payload → route
| What you found | Route to | First move |
|---|---|---|
| Linux filesystem (squashfs/etc) | `ctf-forensics` | mount/extract, grep configs, `/etc/shadow`, keys |
| Raw ARM/RISC-V/MIPS image or ELF | `ctf-rev` | load in Ghidra/radare2; set the right load address & arch |
| RP2040 `.uf2` / Pico | `ctf-rev` | convert uf2→bin (`uf2conv`), base 0x10000000 |
| MicroPython `.mpy`/`.py` | inline / `ctf-rev` | decompile mpy or just read the `.py` |
| **Z-machine `.z5`** | `ctf-rev` | play with `dfrotz`; disassemble with ztools (`infodump`/`txd`) for hidden rooms/data |
| pcap / images / audio inside | `ctf-forensics` | per-file stego/carve |
| crypto blob / keys | `ctf-crypto` | identify scheme, invert |

## 4. RE orientation notes (hand-off context)
- **Arch/endianness:** from `file` (ELF) or infer from vector table / instruction density in radare2 (`radare2 -a arm -b 16/32`). Wrong arch = garbage decompile.
- **Load address:** strings referencing absolute pointers reveal the base; RP2040 flash is `0x10000000`, many Cortex-M reset vectors sit at `0x0`/`0x8000000`.
- **Strings that matter:** SSIDs, default creds, URLs, version banners, and the flag format — grep these first; they often shortcut the whole challenge.

## 5. Record
One-line inventory per interesting region (offset, type, note) in the scratch dir, then launch the specialist. For AND!XOR badge repos specifically, see [[AND-XOR-5n4ck3y]] (the `.z5` is the CTF) and the `andxor-ctf` skill.
