# pi5-stack — ground-up rebuild for the Pi 5 red/blue operator stack

Rebuild the whole stack on a **fresh Kali Rolling arm64 (Raspberry Pi 5)** with one
conductor script and a handful of resumable, idempotent layers. Designed so you can
restore a working Pi quickly, with clear stops wherever a human, a secret, or
hardware is unavoidable.

> **Clean-stack restore.** This rebuilds *infrastructure* to a working state. It does
> **not** restore historical data — Mythic/Sliver come back empty and all
> certs/creds are freshly generated. Your deliverables (engagements, detection
> library, docs) are a separate concern — see `/engagement-backup`.

## Quick start
```bash
git clone <this-repo> ~/pi5-stack && cd ~/pi5-stack
cp secrets.example.env secrets.env && chmod 600 secrets.env   # fill what you have
./bootstrap.sh            # default layers (core → failsafe), ~20 min
./bootstrap.sh --all      # everything incl. C2 + sensors, ~1–2 hr
./bootstrap.sh --check    # verify a build
```

## How it works
`bootstrap.sh` runs numbered layers in order. Each is **idempotent** (completed
layers are recorded in `.bootstrap-state` and skipped on re-run — delete it to force
a rebuild), **logged** to `logs/<layer>.log`, and ends in a **verify**. Failures stop
the run with a clear message; resume with `--from <layer>`.

| Flag | Effect |
|------|--------|
| *(none)* | default layers: `00-core 10-skills 20-mcp-core 30-ap-testbed 40-failsafe` |
| `--all` | + opt-in `50-c2-sliver 51-c2-mythic 60-sensors` |
| `--layers a,b` | run exactly these |
| `--from L` | resume the full ordered run from layer `L` |
| `--check` | run `90-verify` only |
| `--dry-run` | print the plan |

## Layers
| Layer | Set | Does |
|-------|-----|------|
| `00-core` | always | apt base, Go SDK, pipx, cargo, python libs, hostapd/dnsmasq/ipset/chromium, tailscale |
| `10-skills` | always | operator skills → `~/.claude/agents`; render `~/.claude.json` from `payload/claude.json.tmpl` + secrets |
| `20-mcp-core` | always | build/register greynoise(custom), kali-server, hexstrike, playwright, wstg-pentest, pentest-ai |
| `30-ap-testbed` | always | deploy the autonomous AP testbed (wraps `ap-testbed/install-testbed.sh`) |
| `40-failsafe` | always | wifi-failsafe service |
| `50-c2-sliver` | opt-in | Sliver server + operator certs (manual) + sliver MCP |
| `51-c2-mythic` | opt-in | Mythic docker stack + admin-pw capture (manual) + mythic MCP + caido MCP |
| `60-sensors` | opt-in | Suricata (source), Zeek (OBS), bettercap |
| `90-verify` | verify | full stack health check |

## Secrets
`secrets.env` is **git-ignored**; only `secrets.example.env` (blank) is tracked. The
conductor loads `secrets.env` and prompts for anything a selected layer needs,
offering to save it. These are **generated fresh** each rebuild and never stored in
the repo: AP-testbed admin password, Sliver mTLS config, Caido MCP token.

## Manual stops (the conductor pauses and tells you exactly what to do)
`claude login` · VirusTotal/GreyNoise keys · `tailscale up` · Sliver operator certs ·
Mythic first-boot admin password · Caido laptop login (`caido-setup.sh http://<laptop-ip>:8080`) ·
plug in the MT7612U Wi-Fi dongle for the AP testbed.

## Layout
```
bootstrap.sh          conductor
versions.env          pinned versions/refs
secrets.example.env   secrets template (real one is git-ignored)
lib/                  common.sh (helpers) + preflight.sh
layers/               00..90 layer scripts
payload/              scrubbed source copied into place (ap-testbed, agents, wifi-failsafe, greynoise-mcp, claude.json.tmpl)
docs/                 the pi_design Obsidian vault (architecture reference)
```

## Status
**All 9 layers implemented.** `bootstrap.sh` (default + `--all`), `versions.env`
(real URLs pinned to deployed commits), and the payload/docs are complete. Each
layer is idempotent and ends in a `verify()`. `90-verify` has been validated green
against a live full stack. Layers are syntax-checked but only fully exercised on a
*fresh* Kali box — running them on an already-built Pi would re-clone/reset things.
