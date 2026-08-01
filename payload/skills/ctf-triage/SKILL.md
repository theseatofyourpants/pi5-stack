---
name: ctf-triage
description: Front door for an unknown CTF challenge — fingerprint the provided files/URL, classify the category (pwn / rev / web / crypto / forensics / misc), surface the obvious first observations, and route to the right specialist (ctf-pwn, ctf-rev, ctf-forensics, /web-assess) with the tools to reach for. Use at the start of any CTF challenge before committing to an approach.
---

# ctf-triage — classify a challenge and route it

Fast identification, not full solving. Hand off to a specialist once the category is clear.

## 1. Fingerprint whatever you were given
```bash
file *                      # ELF? PE? image? pcap? archive? ambiguous data?
ls -la; strings -n 8 <f> | head -40
exiftool <f> 2>/dev/null | head        # images/docs: metadata, embedded junk
binwalk <f> 2>/dev/null | head         # anything: embedded/appended files (stego/carve tell)
```
For a URL/webapp: note the stack (headers, cookies, JS) — that's `/web-assess` territory.

## 2. Classify → route
| Signals | Category | Route to | First tools |
|---|---|---|---|
| ELF/PE binary, "nc host port", wants input | **pwn** | `ctf-pwn` | checksec, ghidra, pwntools |
| ELF/PE, "find the key/flag", no remote | **rev** | `ctf-rev` | ghidra, radare2, angr |
| Image/audio/pcap/memory dump/odd file | **forensics** | `ctf-forensics` | binwalk, volatility3, steghide, foremost |
| URL / webapp | **web** | `/web-assess` | katana, ffuf, sqlmap, caido |
| Ciphertext, keys, math, `.pem`, RSA params | **crypto** | (handle inline) | python + sympy/pycryptodome; look for small-e/reused-nonce/weak-modulus |
| QR/esoteric/steg-in-text/"nudge" | **misc** | inline / `nudge` for pinball | strings, cyberchef-style transforms |

## 3. Cheap wins to always check first
- `strings | grep -iE 'flag|ctf|\{'` and the challenge's flag format.
- `binwalk`/`foremost` any media before deep stego (an appended zip is common).
- `checksec` any binary immediately (it decides pwn strategy).
- Metadata/EXIF and least-significant-bit on images.

## 4. Hand off
State the category, the concrete evidence for it, and the top 2–3 tools, then launch the specialist agent (subagent_type: ctf-pwn / ctf-rev / ctf-forensics) or `/web-assess`. Keep a scratch dir per challenge (`~/engagements/ctf/<name>/`) for artifacts.
