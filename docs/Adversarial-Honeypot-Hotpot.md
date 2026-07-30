---
title: Adversarial Honeypot — the "Hot-Pot" deception layer
tags: [pi5, testbed, deception, honeypot, blueteam, redteam]
platform: "Raspberry Pi 5 / Kali Rolling / arm64"
updated: 2026-07-30
status: implemented
---

# 🍲 Adversarial Honeypot — the "Hot-Pot"

Back to [[00-Index]]. Sibling of the [[Autonomous-AP-Testbed]]. Where the testbed
*invites* a device to consent and then scans **it**, the hot-pot faces the other
way: it sits on the same isolated AP and waits for something to **poke at us**
unbidden — an enumerator, a scanner, a curious con attendee — and turns that
poking into intelligence.

> [!important] The bright line (read this first)
> The hot-pot **observes and attributes**. It does **not** compromise the prober.
> We serve *fake* services and *instrumented* files. Honeytokens report **to us**
> when opened or used — passive telemetry from files we authored. **Nothing we
> serve executes on, or grants control of, the prober's machine.**
>
> The rejected version of this idea — leaving a share whose payload gives us a
> Sliver/Mythic session on whoever touched it — is **hack-back**: unauthorized
> access to a third-party machine (CFAA and every equivalent worldwide, no
> "they-scanned-me-first" exception), aimed at someone who by definition did
> **not** consent, on a target we cannot even identify (could be a researcher,
> our own phone, or a *compromised victim box*). That crosses the same wall as
> the "allow-by-default" DEF CON switch we already declined — and it is not in
> this design. See "What we deliberately do NOT do" below.

## Why it's worth building

The intelligence you actually want from an adversarial honeypot — *who is poking,
what tools/creds/commands they use, what they'd try to exfiltrate* — is fully
available **without** touching their machine. Better still, it closes a loop we
already have the back half of: real adversary behaviour in → deployable
detections out via [[detection-engineer]]. The hot-pot is a **detection factory**.

## Architecture

Coexists with the consent testbed on the same dongle AP (`wlan1`, subnet
`10.66.66.0/24`, gateway `.1`). The two paths don't collide:

- **Consent path** — a willing device consents in the [[Autonomous-AP-Testbed|captive portal]] → gets a scope-locked [[device-assess]] scan. Ports `:80/:443` on `.1`.
- **Hot-pot path** — anything that connects to the **bait ports** (below) without consenting is logged as *hostile recon*. Different ports, same subnet.

### 1. Bait services (start tight — three)

All bound to the AP IP (`10.66.66.1`) **only**, never the uplink/LAN. All run
unprivileged and jailed. Everything they expose is fake.

| Service | Port | Engine | Captures |
|---------|------|--------|----------|
| SSH / Telnet | 22, 23 | **Cowrie** (medium-interaction) | creds tried, every command run, files fetched (`wget`/`curl` in the fake shell), full session TTYs, client **HASSH** fingerprint |
| SMB share `IT-Backups` | 445 | **impacket `smbserver`**, read-only | share enumeration, file reads → which honeytoken was pulled |
| Fake admin (router/NAS login) | 8080 / 8443 | stdlib `http.server` (portal pattern) | credential-stuffing attempts, User-Agent, path probing, "config download" honeytoken pulls |

Cowrie is the crown jewel — a medium-interaction shell gives you the prober's
actual TTPs, not just a connection record. Keep the set small at first; add
FTP/Redis/etc. only if the events justify it.

### 2. Honeytokens (the instrumented bait)

Seeded into the SMB share, Cowrie's fake filesystem, and the fake-admin "download
config" — each **unique per deployment** so a trip identifies its origin:

- **Homegrown URL/DNS tokens** (default): a unique callback URL / DNS name baked
  into `vpn-config.ovpn`, `passwords.xlsx`, `backup_2026.zip`. Beacons to a tiny
  **collector endpoint on the Pi** (added to the existing admin Flask app), so
  **all telemetry stays local** — no third party. A trip tells you: token X was
  opened, from IP Y, at time Z, with UA/DNS-resolver W.
- **AWS-key canarytoken** (optional, high-signal): a fake `aws_credentials` file.
  If anyone ever *uses* the key, AWS CloudTrail fires an alert. This one can't be
  self-hosted (needs canarytokens.org infra) but is the highest-fidelity "someone
  is actively working my loot" signal. Passive: it reports *use*, it doesn't run
  anything on the prober.

Tokens are **telemetry, not code execution** — this is the whole legal basis.

### 3. Isolation (the load-bearing safety property)

The hot-pot must be *more* locked down than the consent path, because we are
inviting hostile interaction:

- Reuses [[Autonomous-AP-Testbed|`isolation.sh`]] guarantees: the AP subnet
  cannot reach the LAN, the uplink subnet, or (on the deception path) the
  internet — `EGRESS=0` for probers.
- Bait services run as a dedicated unprivileged user, read-only FS, seccomp where
  the engine supports it; SMB is read-only; Cowrie's "shell" is a jail — a
  "downloaded" tool runs in Cowrie's sandbox, never on the host.
- Token beacons egress via the **Pi's own uplink** from the collector, never from
  the prober's subnet.
- **We never serve a real exploit or a real reverse shell.** If a bait service is
  itself popped, the blast radius is a fake FS in a container.

### 4. Arming & lifecycle

- New config flag **`deception`** in [[device-assess|`store.py`]] config
  (`state/config.json`), **default `false`**, admin-toggleable — mirrors how
  `armed`/`egress`/`auto_abort` already work.
- New unit **`ap-testbed-hotpot.service`**, `WantedBy=ap-testbed.target`, with an
  `ExecStartPre` guard that no-ops when `deception` is off (same pattern as the
  `ARM_OFFENSIVE` gate). Plug the dongle → testbed comes up; the hot-pot only
  actually listens when you've toggled deception on.
- Events (Cowrie sessions, SMB touches, fake-admin logins, token trips) append to
  `logs/hotpot/events.jsonl` and surface through the store.

### 5. Admin console

New **Hot-pot** view alongside Devices/Scans/Consents: on/off toggle, a live feed
of hostile-recon events, a per-source-IP rollup (what each source touched), and a
**"send to triage"** button that hands an event to the blue-team pipeline.

The **Operations dashboard** (the `/` landing page) is the deep-monitoring view:
KPI tiles, a 24h stacked **hostile-recon activity** timeline, **findings-by-severity**
bars (parsed from device-assess reports), **deception-events-by-type** bars, a ranked
**probers** table, a color-coded **alerts** feed (token trips / loot pulls / cred
bursts, plus a best-effort Suricata `eve.json` hook that degrades to a one-line fix
if the log isn't readable by the admin user), and a **canary-token** grid that flags
tripped tokens. It renders from a `/api/dashboard` JSON endpoint and live-polls every
7s — all inline SVG/JS, no external libraries. Chart palettes were validated with the
dataviz method (categorical hues CVD-checked on the dark surface; severity is a
labeled ordinal status ramp).

## The maintenance skill — [[hotpot-maintain]]

`~/.claude/agents/hotpot-maintain.md`. **Read / inspect / rotate / report only** —
no offensive action, never touches the prober. It:

1. **Health** — bait services (Cowrie/SMB/fake-admin) + token collector up and
   bound to the AP IP only?
2. **Isolation assertion** — *actively verifies* the deception subnet cannot
   egress or reach the LAN, and fails loud on drift. This is the safety invariant.
3. **Honeytoken lifecycle** — lists deployed tokens, verifies each beacon path
   resolves to the live collector, rotates/regenerates on request, re-seeds the
   SMB share and Cowrie FS.
4. **Intel rollup** — summarizes recent captures: top source IPs, creds tried,
   commands run, files fetched, tokens tripped.
5. **Hand-off** — enriches source IPs via [[mcp-greynoise|GreyNoise]], hashes
   dropped files via [[mcp-virustotal|VirusTotal]], and recommends
   [[triage-alerts]] + [[detection-engineer]] for anything real.
6. **Hygiene** — rotates/prunes logs, checkpoints intel to `~/engagements/`.

Its tools are deliberately scoped to Bash/Read/Write + GreyNoise/VirusTotal —
**no** kali/hexstrike offensive tools, **no** Sliver/Mythic. It cannot attack.

## Blue-team / IR monitoring (existing stack)

The hot-pot's output plugs straight into tooling we already run — this is where it
pays off:

- **[[Network-Sensors|Suricata]]** — custom rules: *any* connection to the
  honeypot IP/bait ports is an alert. A honeypot sees zero legitimate traffic, so
  these are ~zero-false-positive, high-fidelity signals. **Wired into the lifecycle:**
  `hotpot-ctl.sh` starts a **dedicated** Suricata on the AP interface (`wlan1`) when
  the hot-pot arms — its own pidfile (`suricata-hotpot.pid`) + log dir
  (`/var/log/suricata/hotpot/`) so it never collides with a host-wide Suricata — and
  auto-grants the admin user read (`setfacl`) so the dashboard Alerts panel populates.
  It defers to any Suricata already watching `wlan1`, and tears down on disarm/unplug.
  The dashboard reads the **freshest** of the host-wide / hot-pot `eve.json` logs, so
  it follows the live sensor even after handing off from a manual instance to the
  managed one (a stale default-path log never wins).
- **[[Network-Sensors|Zeek]]** — `conn`/`ssh`/`http`/`x509` logs on the AP subnet
  give rich attribution metadata and **JA3/JA4/HASSH** client fingerprints of the
  prober's tooling.
- **[[mcp-greynoise|GreyNoise]]** — context on any routable source / callback IP:
  known mass-scanner vs. targeted, RIOT-benign vs. malicious.
- **[[mcp-virustotal|VirusTotal]]** — hash any tool/file the prober drops into
  Cowrie or the SMB share; detonate any URL they fetch.
- **[[triage-alerts]]** — the natural consumer. Extend it to ingest hot-pot
  events, correlate with GreyNoise/VT, classify **targeted vs. noise**, and draft
  an IR runbook.
- **[[detection-engineer]]** — turn observed prober TTPs (the commands they ran,
  the tools they pulled) into **Sigma/YARA/Suricata** rules for the
  [[Detection-Library]]. The detection-factory loop.
- **[[mcp-huntress|Huntress]]** — if deployed alongside Huntress agents, correlate
  hot-pot trips with EDR signals.
- **[[debrief]]** — end-of-event synthesis of everything the hot-pot caught.

## Deployment notes (learned building it)

- **Docker on this host / port publishing.** Bait containers publish on
  `10.66.66.1:<port>` only (never `0.0.0.0`), on a dedicated bridge
  `172.31.66.0/24`. The isolation invariant is enforced in `DOCKER-USER`:
  container sources may reply to established prober flows but **cannot initiate
  outbound** — no internet, no LAN, no exfil, no attacker-URL fetch. This is the
  container-layer guarantee `hotpot-ctl.sh` applies on start and asserts thereafter.
- **Port 22 authenticity.** The Pi's real `sshd` holds the `0.0.0.0:22` wildcard,
  so a `10.66.66.1:22` publish can't bind (userland-proxy on). `hotpot-ctl.sh`
  detects this and falls back to publishing Cowrie SSH on **2222** so the stack
  always comes up. To serve the bait on a true `:22` (more convincing to a
  scanner), free `:22` first — bind `sshd` to specific management addresses via
  `ListenAddress`, or set docker `userland-proxy: false` — then leave
  `COWRIE_SSH_PORT` unset. AP clients can't reach the host `sshd` regardless
  (`isolation.sh` drops `:22` from the AP interface).
- **Honeytoken reach — the two backends.** `local` catches trips while the client
  can still reach `10.66.66.1` (in-situ opens) plus **server-side loot pulls**
  (a download is logged the instant it happens, no client cooperation). For a
  beacon that fires *after* the file is carried off-network, use `canarytokens`
  (public collector, and the only path for Office/PDF/AWS-key tokens). The two are
  a config switch (`token_backend`), re-seed to apply.
- **Smoke-tested 2026-07-30** on the live AP: all four services bound to
  `10.66.66.1`; fake-admin logged probe/cred/loot, the collector logged a token
  trip, Cowrie accepted and logged SSH/Telnet connections. Full authenticated
  Cowrie session capture is exercised in the dongle end-to-end test.

## What we deliberately do NOT do

- ❌ Serve a payload that runs on / gives us control of the prober's machine
  (Sliver/Mythic implant, reverse shell, browser/RCE exploit). That's hack-back.
- ❌ Attack, scan back, or "counter-exploit" the source. The maintenance skill has
  no offensive tools by design.
- ❌ Enable egress for the prober. The deception subnet stays `EGRESS=0`.
- ✅ We serve fakes, instrument our own files, observe, attribute, alert, and mint
  detections. Deception on our own systems — legal, standard, and the whole point.

## Build status

**Implemented + smoke-tested, 2026-07-30.** Lives in `~/ap-testbed/hotpot/`
(Docker Compose: Cowrie, impacket SMB, fake-admin, collector), gated by the
`deception` config flag, wired into `ap-testbed.target` via
`ap-testbed-hotpot.service` + `hotpot-ctl.sh`, seeded by `seed-tokens.py`, and
surfaced in the admin console **Hot-pot** tab (arm/disarm, backend switch, live
hostile-recon feed, per-source rollup, deployed-token list). Install with
`sudo bash ~/ap-testbed/install-hotpot.sh`. Maintain/monitor with
[[hotpot-maintain]]. See the [[Autonomous-AP-Testbed]] for the base it extends and
the [[Replication-Guide]]/`pi5-stack` repo for the rebuild path.
