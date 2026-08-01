---
name: nudge
description: Encode/decode the DEF CON pinball "Analog Awakening" nudge cipher (L/R/F nudges → text; digits are always 4 nudges). Use for the pinballhackers.com RTPT challenge and this year's SHELL 16-digit PIN device. Wraps the ~/engagements/nudge.py toolkit.
---

# nudge — pinball nudge-cipher toolkit

Front end for `~/engagements/nudge.py`. Cipher: L=LEFT, R=RIGHT, F=FORWARD; letters A–Z are 1–4 nudges (variable length), digits 0–9 are ALWAYS 4 nudges. Authoritative table lives in `app.pinballhackers.com/analog-awakening.html`. See [[defcon-pinball-ctf]].

## Modes
```bash
~/engagements/nudge.py encode "1337"            # text  -> nudges
~/engagements/nudge.py encode "TILT" --sep -    # custom separator
~/engagements/nudge.py pin  FLFRRFLR...         # all-numeric stream -> digits (chunk by 4)
~/engagements/nudge.py decode "LRF-LF-FR" -t -  # trigger-delimited stream -> text (exact)
~/engagements/nudge.py decode "LRFLFFRLRF"      # no delimiter -> greedy best-effort
~/engagements/nudge.py table                    # print the full cipher table
echo "FLFR RFLR" | ~/engagements/nudge.py pin - # read stream from stdin with '-'
```

## Key facts for the SHELL device (this year's target)
- **16-digit numeric PIN = 64 nudges = 16 groups of 4** → use `pin`, it's unambiguous (every digit is exactly 4 nudges).
- The cipher is 1:1 but **NOT prefix-free**, so *mixed* concatenated streams are ambiguous (`LL`=D or A+A). The physical **"trigger key" = a per-character COMMIT action** (plunger/launch/pause). For mixed text, capture that delimiter and use `decode -t <delim>`; greedy decode is a guess, not gospel.

## Posture
Passive source-reads and cipher work only. **Keep hands off the physical SHELL device / any live PIN endpoint** until the organizers' rules explicitly allow it (per the DEF CON Code of Conduct). When the challenge page goes live, do the yearly passive recon (view-source + grep the JS bundle + HTML comments + fetch the standalone challenge `.html`) — see [[defcon-pinball-ctf]].
