---
name: rf-decode
description: Capture and decode RF for CTF / badge challenges and sensor work — SDR capture (RTL-SDR/HackRF) then POCSAG/FLEX pager decode via multimon-ng, plus the recurring T9-number→phone-call→reversed-audio pattern, sub-GHz (315/433/915 MHz) capture/replay, and LoRa/Meshtastic (915 MHz US) BBS interaction. Use when a challenge hands you a frequency, a pager reference, an audio clip, or a Meshtastic/LoRa hint. Read/decode oriented; only transmit where explicitly authorized.
---

# rf-decode — SDR capture → decode

For badge/CTF RF challenges (POCSAG pagers recur nearly every AND!XOR year) and bench RF work. Requires an RTL-SDR (or HackRF). Scratch dir: `~/engagements/ctf/<name>/`.

> [!warning] TX is regulated. Capture/decode freely; **only transmit** (replay, LoRa, IR) where the contest/lab explicitly allows it and on legal frequencies. Never de-auth WiFi or jam.

## 1. Find the signal
Frequency usually comes from the challenge (a cracked pager screen, a hint like "~925 MHz ISM"). Survey the band first:
```bash
gqrx                                   # GUI waterfall — visually find the burst, note center freq + mode
rtl_power -f 900M:930M:1k -g 30 -i 10 out.csv   # headless power sweep to spot activity
```

## 2. POCSAG / FLEX pager decode (the staple)
```bash
# pipe FM demod straight into multimon-ng
rtl_fm -f 929.6M -s 22050 -g 40 - | multimon-ng -t raw -a POCSAG512 -a POCSAG1200 -a POCSAG2400 -a FLEX -f alpha -
# or decode a saved capture:
multimon-ng -t wav -a POCSAG1200 -a FLEX -f alpha capture.wav
```
Try all three POCSAG baud variants — you don't know which. Output is often a **T9-encoded phone number** or a numeric code.

## 3. The T9 → phone → reversed-audio pattern
Recurs in AND!XOR (DC28/DC33): decoded message → a real phone number → **call it** → voicemail plays a message **reversed**. Record it, then:
```bash
# reverse an audio clip; also open in Audacity for spectrogram/tone view
sox voicemail.wav reversed.wav reverse
```
The reversed audio yields the 5n4ck3y dispense code (or the flag). Check the **spectrogram** too — flags are sometimes drawn in it, and DTMF/coin-tones decode to digits/ASCII.

## 4. Sub-GHz capture/replay & LoRa
- **315/433/915 MHz OOK/ASK** (remotes, sensors): `rtl_433 -A` to auto-decode known devices; capture raw with `rtl_fm`/`gqrx` and inspect timing. Replay only if authorized (Flipper Zero is the easy path).
- **LoRa / Meshtastic (915 MHz US):** DC33 used a Meshtastic BBS. Connect a node (Heltec/T-Beam/RAK), DM the contest node (`?` for help), read "Mail". Radio inputs can be exploitable (DC33: `4294967295` = max uint32 buffer overflow via message).

## 5. Record
Save captures (`.wav`/`.cf32`), the decoded text, and the frequency/mode in the scratch dir. Gear + buy links: [[AND-XOR-Hardware-Gear]]. Deeper badge context: [[AND-XOR-5n4ck3y]] §3.3.
