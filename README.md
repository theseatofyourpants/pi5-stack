# pi5-stack — an AI-orchestrated red/blue security lab on a Raspberry Pi 5

A self-contained, portable security-operations platform: a Raspberry Pi 5 (arm64,
Kali Rolling) where **Claude Code acts as the operator** — driving offensive *and*
defensive tooling through natural language, using MCP servers as its hands and
custom "operator skills" as its playbooks. It covers the whole engagement lifecycle
(recon → exploitation → C2/post-ex → blue-team triage → detection engineering →
reporting) and includes a novel **autonomous, consent-gated Wi-Fi testbed** that
security-tests devices that connect to it.

**This repo is two things:**
1. **The stack itself** — documented in depth below and mapped note-by-note in `docs/`.
2. **A ground-up rebuild kit** — one conductor script that restores the whole thing
   on a fresh Pi. See [Rebuilding it](#rebuilding-it-this-repo).

---

# What the Pi does — the stack

## The idea
Instead of an operator memorising a hundred CLI tools, the **AI is the operator**.
You talk to Claude Code; it reasons about the engagement and reaches for the right
tool through a structured interface. Two things give it that power:

- **MCP servers** — registered in `~/.claude.json`, these are the typed tools the AI
  can call (scanners, C2 control, proxies, threat-intel, browser automation).
- **Operator skills** — subagents in `~/.claude/agents/*.md`, each encoding a
  methodology (recon, web assessment, detection engineering…), invoked as `/name`.

**Orchestration model:** high-level reasoning runs on **Opus** (5, with 4.8 as a
guardrail fallback); data-heavy mechanical work is delegated to **Haiku** subagents.
Every skill writes its artifact to `~/engagements/`.

## MCP servers — the AI's tool surface
| Server | Role |
|--------|------|
| **hexstrike** | 150+ offensive tool wrappers (nmap, nuclei, ffuf, sqlmap, dalfox, jwt, graphql, api…); local backend on `:8899` |
| **mcp-kali-server** | Kali tool runner + reverse-shell/SSH sessions; backend on `:5000` |
| **wstg-pentest** | OWASP WSTG methodology engine — test cases, payloads, findings, coverage, knowledge-graph chaining |
| **pentest-ai** | Structured engagement scanner (web/api/cloud/AD probes, attack-chain proving) |
| **Sliver C2** | Control of the Sliver C2 (sessions, beacons, pivots, implants) |
| **Mythic C2** | Control of the Mythic C2 (callbacks, tasks, payloads, artifacts, ATT&CK) |
| **Caido** | Web proxy (Burp-style) over its GraphQL API — replay, diff, race-window, findings |
| **Playwright** | Real-browser automation / DOM verification (kills web false positives) |
| **VirusTotal** | File/URL/domain/IP reputation + malware behaviour enrichment |
| **GreyNoise** *(custom, keyless-capable)* | Internet-noise-vs-targeted intent for an IP — complements VT's reputation |
| **Huntress** | Blue-team EDR alert/incident feed |

## Operator skills — the playbooks
| Skill | Phase |
|-------|-------|
| `/operation` | **Master orchestrator** — chains the whole lifecycle with operator decision gates |
| `/stack-status` | Preflight health board (C2 + sensors + MCP backends) |
| `/engagement-start` | Spin up a Mythic op, WSTG tracking, recon plan, C2 listeners |
| `/osint-profile` | Passive→active recon dossier (subdomains, DNS, Shodan, VT + GreyNoise) |
| `/web-assess` | WSTG-guided web exploitation with verify-before-log discipline |
| `/generate-payload` | OPSEC-aware Sliver/Mythic payload builder |
| `/pivot-analysis` | Enumerate implants, map topology, surface pivot paths |
| `/triage-alerts` | Correlate Huntress + C2 + sensors; VT×GreyNoise verdicts |
| `/detection-engineer` | Turn offensive TTPs into Sigma / YARA / network rules |
| `/debrief` | Aggregate all backend data into a structured report |
| `/engagement-backup` | Snapshot deliverables (secrets redacted) to a timestamped archive |
| `/device-assess` | **Unattended** scope-locked scan of a single device (drives the AP testbed) |

## C2 frameworks
- **Sliver** (v1.7.3, Go) — mTLS multiplayer daemon on `127.0.0.1:31337`, operator
  config for the MCP.
- **Mythic** (v3.4.0, 8 Docker containers) — web UI on `https://localhost:7443`.

## Network sensors (blue team)
- **Suricata** (IDS/IPS, ET Open ruleset) · **Zeek** (network security monitoring) ·
  **bettercap** (wireless recon). These feed `/triage-alerts` and `/detection-engineer`
  so offensive activity can be *detected*, not just performed.

## 🛰️ The Autonomous AP Testbed — "Security by The Seat of Your Pants"
The headline capability. Plug a USB Wi-Fi dongle (MediaTek MT7612U) into the Pi and
it becomes a **dongle-triggered, consent-gated access point that automatically
security-tests any device that joins** — an *inverted honeypot* / device-security
bench. Pull the dongle and it fully tears down. Never an "attack anyone who
connects" machine — authorization is the load-bearing wall.

- **Hardware-armed:** a udev rule brings the whole thing up when the dongle is
  present and tears it down when removed. The Pi's real uplink (`wlan0`) is never
  touched; the AP lives on the dongle (`wlan1`, 5 GHz, SSID *Open Security Test*).
- **Hybrid captive portal:** an *unauthorized* device gets a **consent screen** (it
  must tap "I authorize a scan"); an *authorized/allowlisted* device gets clean,
  **LAN-isolated internet** and stays connected. Real DNS + per-MAC egress via
  iptables — internet only for authorized MACs, never a route to your LAN.
- **Autonomous scanning:** on authorization, an unattended **`/device-assess`** run
  fires — network + service enumeration, device/OS fingerprint, device-level vuln
  identification, and a web hand-off if web ports exist. Scope is **locked to the one
  device**, non-destructive, low-aggression, time-bounded.
- **Two front-ends:**
  - **`status.test`** — a per-device page the joiner opens in their browser to watch
    live scan progress and read their own report (MAC-scoped: they see only theirs).
  - **Admin console** (`:8787`, on `wlan0`/Tailscale, Basic-Auth) — device allowlist
    CRUD, consent ledger, scan history + live progress, **HTML/PDF reports**, SSID
    rename, arm/disarm, egress & auto-abort toggles, and **revoke-&-wipe**.
- **Safety rails:** consent-or-allowlist required, single-IP scope lock, isolated
  walled garden, per-device cooldown, a global HALT kill-switch, and a scoped
  `sudoers` helper (`/usr/local/sbin/apt-testbed-authorize`) so the web app can open
  one MAC's egress but nothing else.

### 🍲 The hot-pot — adversarial deception on the same AP
Riding on the testbed is an **opt-in deception layer** (Docker, installed by layer
`30` when Docker is present) that flips the script: instead of scanning devices that
*consent*, it quietly observes devices that probe *uninvited*. It never touches or
attacks the prober — it just watches and attributes.

- **Bait services (Dockerised, on the isolated AP subnet):** **Cowrie** SSH/Telnet
  (captures creds + session transcripts), a read-only **SMB share** of tempting
  files, and a **fake-admin** login page.
- **Honeytokens / canarytokens (the instrumented bait):** the bait files carry
  phone-home tokens with two selectable backends —
  - **local collector** — a homegrown beacon (`10.66.66.1:8686/t/<id>`) that fires
    the instant a token is touched on-net (fully automatic), and
  - **canarytokens** — operator-minted [canarytokens.org](https://canarytokens.org)
    URLs (seeded from `state/canarytokens.json`) for the high-fidelity *"someone
    opened the file **off**-network"* signal (e.g. an AWS-key or `.docx` canary).
- **Isolation is the load-bearing invariant:** the deception subnet can't egress or
  reach your LAN — asserted, not assumed.
- **Kept sharp by [`/hotpot-maintain`](docs/agents/hotpot-maintain.md):** health-checks
  the bait, re-seeds/rotates tokens, and rolls up captured hostile-recon intel for the
  blue-team pipeline. Full writeup: [`docs/infrastructure/Adversarial-Honeypot-Hotpot.md`](docs/infrastructure/Adversarial-Honeypot-Hotpot.md).

## wifi-failsafe
If the Pi loses its Wi-Fi uplink, a systemd watcher stands up a **fallback AP +
captive portal on `wlan0`** so you can pick a new network from your phone — keeping a
headless, monitor-less Pi reachable. (Bound to `10.42.0.1` so it never collides with
the testbed's portal.)

## The red → blue loop
The point of the whole stack: **do something offensive, then detect it.** Skills
1–5 attack (recon → exploit → C2 → pivot); `/triage-alerts` correlates the resulting
telemetry across Huntress + C2 + Suricata/Zeek; `/detection-engineer` converts each
TTP into deployable Sigma/YARA/network rules; `/debrief` folds coverage into the
final report. The `docs/` vault maps every component and this loop in detail.

---

# Rebuilding it (this repo)

Restore the entire stack on a **fresh Kali Rolling arm64 (Pi 5)** with one conductor
script and a set of resumable, idempotent layers, with clear stops wherever a human,
a secret, or hardware is unavoidable.

> **Clean-stack restore.** This rebuilds *infrastructure* to a working state. It does
> **not** restore historical data — Mythic/Sliver come back empty and all
> certs/creds are freshly generated. Deliverables (engagements, detection library,
> docs) are a separate concern — see `/engagement-backup`.

## Quick start
```bash
git clone https://github.com/theseatofyourpants/pi5-stack.git ~/pi5-stack && cd ~/pi5-stack
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
| `00-core` | always | apt base, Go SDK, Rust, python libs, hostapd/dnsmasq/chromium, tailscale |
| `10-skills` | always | operator skills → `~/.claude/agents`; render `~/.claude.json` from `payload/claude.json.tmpl` + secrets |
| `20-mcp-core` | always | build/register greynoise(custom), kali-server, hexstrike, playwright, wstg-pentest, pentest-ai + backends |
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
