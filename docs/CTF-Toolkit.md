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

Artifacts land in `~/engagements/ctf/<name>/`.

## Also
- **`nudge` skill** — the DEF CON pinball "Analog Awakening" cipher toolkit (`~/engagements/nudge.py`); wraps encode/pin/decode/table for this year's SHELL 16-digit PIN device. Passive/cipher work only — hands off the physical device until organizer rules allow.

## Related
- [[Stack-Ops-Skills]] (the other new SKILL.md skills) · the DEF CON pinball CTF is tracked in project memory, not this vault (engagement-specific).
