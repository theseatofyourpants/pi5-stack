---
title: CTF Toolkit
tags: [ctf, pwn, rev, forensics, crypto, agent, skill]
updated: 2026-08-01
---

# CTF Toolkit

Part of [[Operator-Skills]]. CTF-focused capabilities added 2026-08-01 (the operator runs DEF CON CTFs — see [[#Related]]). A triage front-door skill routes to three specialist agents, all leaning on [[mcp-hexstrike]]'s binary/forensics toolset.

## Front door (skill)
- **`ctf-triage`** — fingerprint the given files/URL (`file`/`strings`/`binwalk`/`exiftool`), classify the category (pwn / rev / web / crypto / forensics / misc), and route to the right specialist. Web → [[web-assess]]; pinball nudge cipher → the `nudge` skill.

## Specialist agents (`~/.claude/agents/`)
| Agent | Domain | Chain |
|-------|--------|-------|
| `ctf-pwn` | Binary exploitation | checksec → Ghidra/radare2 → pwntools/ROPgadget/one_gadget → angr → remote flag |
| `ctf-rev` | Reverse engineering | Ghidra/radare2 decompile → angr symbolic solve → invert transform |
| `ctf-forensics` | Memory/stego/carving | volatility3, binwalk, foremost, steghide, exiftool, xxd |
| `ctf-crypto` | Cryptography (2026-08-02) | encoding/classical chains → XOR/known-plaintext → RSA/ECC/block/hash weaknesses → invert |

Artifacts land in `~/engagements/ctf/<name>/`.

## Bench skills (`~/.claude/skills/`) — added 2026-08-02
Fill the non-solver gaps around the specialists:
- **`fw-triage`** — id + carve an unknown firmware image / flash dump / badge repo, route to rev/forensics/crypto. Pairs with `hw-bench`.
- **`rf-decode`** — SDR capture → POCSAG/FLEX (`multimon-ng`), T9→phone→reversed-audio, sub-GHz + LoRa/Meshtastic. Overlaps sensor/testbed RF gear.
- **`hw-bench`** — physical bringup: UART/baud discovery, `flashrom` SPI dump, logic-analyzer (UART/WS2812), thermistor/Hall/IR triggers, trace surgery.
- **`andxor-ctf`** — the AND!XOR/5n4ck3y/BENDER playbook (recognize→recipe).

Offline practice material: `~/engagements/ctf/andxor-firmware/` (DC24/28/31/32/33 repos — incl. the DC33 `bender_ctf.z5` Z-machine story and DC28 SPI flash image).

## Also
- **`nudge` skill** — the DEF CON pinball "Analog Awakening" cipher toolkit (`~/engagements/nudge.py`); wraps encode/pin/decode/table for this year's SHELL 16-digit PIN device. Passive/cipher work only — hands off the physical device until organizer rules allow.
- **`andxor-ctf` skill** — playbook for the AND!XOR / 5n4ck3y / BENDER badge CTF (the phygital badge-hacking contest). Recognizes the recurring challenge patterns (stacked classical crypto, POCSAG/RF, UART @ odd baud, thermistor/Hall/IR triggers, WS2812/flash-dump surgery, Shakespeare esolang, Z-machine RE) and jumps straight to the decode recipe. Fills the bench-work gap between `ctf-rev` and `ctf-forensics`.

## CTF references (`ctf-references/`)
- [[AND-XOR-5n4ck3y]] — recurring mechanics, gotchas, per-year worked examples (DC28/DC33), tooling checklist.
- [[AND-XOR-Hardware-Gear]] — the physical field kit with links/examples/priority buy order.

## Related
- [[Stack-Ops-Skills]] (the other new SKILL.md skills) · the DEF CON pinball CTF is tracked in project memory, not this vault (engagement-specific).
