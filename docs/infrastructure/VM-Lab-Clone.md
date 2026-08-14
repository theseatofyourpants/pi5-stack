---
title: VM Lab Clone (Kali on Apple Silicon)
tags: [infra, replication, vm]
status: validated
updated: 2026-08-13
---

# VM Lab Clone — Kali on an Apple Silicon MacBook

> [!success] Built & validated on a real VM (2026-08-13)
> The `pi|vm` selector is merged, and the **full stack installs end-to-end on a fresh
> Kali arm64 VM** (`kalivm`) — every layer `00`–`70` (minus the Pi-only failsafe), C2 +
> MCP + sensors + hot-pot, 9/10 MCPs green. The clean-room run found & fixed **13
> fresh-box bugs** (see below). Only remaining: the **MT7612U USB-passthrough** test
> (needs the dongle on the Mac). See [[Architecture-Overview]] for the Pi stack this mirrors.

## Purpose
A Kali arm64 VM on an Apple Silicon MacBook that runs the **software + USB-hardware
half** of the Pi 5 stack: C2 ([[Sliver-Server]], [[Mythic-Server]]), the MCP layer,
operator skills/agents, phishing, CTF + bench tooling, sensors, and — via USB
passthrough — the [[Autonomous-AP-Testbed]] and its [[Adversarial-Honeypot-Hotpot|hot-pot]].
It becomes a **portable dev/lab mirror**: build and test skills/agents/MCP wiring and
run engagements without the physical Pi, and carry the hardware bench to wherever the
Mac is. The Pi stays the always-on, board-anchored node.

## Host & hypervisor
- **Chip:** Apple Silicon (M-series) → the VM is **arm64, same arch as the Pi**. This
  is the whole reason it's low-effort: the repo's arm64 assumptions already hold.
- **Hypervisor (pick for USB-passthrough reliability):**
  - **Parallels** — smoothest USB passthrough, paid.
  - **VMware Fusion** (13.5+) — free personal use, solid arm64 + USB. Recommended default.
  - **UTM/QEMU** — free, but fussier with Wi-Fi adapters. Fallback.
- **Guest:** Kali Linux arm64 (installer or prebuilt arm64 image). Keep the login user
  **`tsoyp`** — the stack hardcodes `/home/tsoyp/...` paths and a `tsoyp` sudoers file.

## Architecture parity (arm64 = easy)
The repo already targets Kali arm64, so these are **already correct** on Apple Silicon:
- `layers/00-core.sh` → `go…linux-arm64`
- `layers/50-c2-sliver.sh` → `sliver-server_linux-arm64`
- `layers/60-sensors.sh` → Suricata built from source (arm64 apt DPDK-dep workaround)

Only real arch risk: **Mythic on arm64.** The server containers are multi-arch, but a
few agent payload types cross-compile inside Docker and can assume amd64 — verify
per payload type, not a blocker. (Precedent: the stack already splits arch for Caido,
which "has no arm64 build, runs on the x86 laptop.")

> Make the hardcoded strings `ARCH=$(dpkg --print-architecture)`-driven anyway, so the
> same profile also survives an Intel/amd64 host later. Cheap insurance.

## Mechanism: a selector in `main`, NOT a fork or branch (decided 2026-08-12)
> [!success] Decision — locked
> **Selector in the main repo, capability-probed. No fork, no permanent `vm` branch.**
> The Pi-vs-VM delta is a handful of conditionals (arch var, 3 self-skipping hardware
> layers, profile-aware verify), not a divergent codebase — so it's expressed as
> runtime selection, not structural separation. A fork/branch would impose a perpetual
> port/merge tax and let the two targets drift; single-repo means a fix like the
> Aug-2026 captive-portal DNS hijack lands on both in **one commit**. The only branch
> used is a *temporary* feature branch to develop the refactor, then merged and deleted.

**Design — auto-detect first, `--profile` as override:**
- `bootstrap.sh` already selects layers (`--layers`, `--from`, `--all`,
  `DEFAULT_LAYERS` vs `OPTIN_LAYERS`) — the seed of this. Add a `--profile vm|pi`
  (default: **auto**) that mainly drives what `verify` expects.
- **Lead with capability auto-detection** so the *same* `./bootstrap.sh` runs correctly
  on either host — each hardware layer self-skips when its device is absent:
  ```bash
  ARCH=$(dpkg --print-architecture)          # arm64 on both Pi + Apple-Silicon VM
  # 40-failsafe.sh
  have_builtin_wifi || { log "no built-in wlan0 → skip failsafe (VM)"; exit 0; }
  # 30-ap-testbed.sh  (already udev-gated; guard the installer too)
  have_ap_dongle    || { log "no MT7612U present → skip testbed"; exit 0; }
  ```
- Make `layers/90-verify.sh` **profile-aware** — today it `chk`s `hostapd` and
  hardware services and would *fail the VM build* otherwise; it should assert only
  what the active profile's host is expected to have.
- `PROFILE` stays a thin override: force-skip a present-but-unwanted layer, or make
  verify strict. It is **not** the primary gate — the capability probe is.

### Capability probes (per layer)
| Layer | Probe → run if… |
|---|---|
| `30-ap-testbed` (+ hot-pot) | a second wifi iface appears (`iw dev` shows the passed-through `mt76`). Already **udev/event-driven** off the dongle — see [[Autonomous-AP-Testbed]]. |
| `40-failsafe` | a built-in client radio to "lose" exists. **Normally skipped in the VM** (see below). |
| `eink-panel` | not a main-build layer at all — it's a **separate companion Pi Zero 2 W**, so nothing to skip in the Pi/VM bootstrap. (`has_spidev` probe exists for future use.) |

## Layer disposition
| Layer | VM? | Note |
|---|---|---|
| 00-core | ✅ | arm64 Go URL already right; ensure `firmware-misc-nonfree`/`linux-firmware` for the `mt76` dongle |
| 10-skills | ✅ | pure files |
| 20-mcp-core | ✅ | Python/npx, arch-agnostic |
| 50-c2-sliver | ✅ | arm64 binary already right |
| 51-c2-mythic | ✅ | Docker; verify arm64 per payload type |
| 52-phishing | ✅ | software |
| 55-ctf-tools | ✅ | software + **hw-bench** works once bench gear is passed through |
| 60-sensors | ✅ | runs; value depends on network position |
| **30-ap-testbed** | ⚠️→✅ | needs the **MT7612U** passed through; then the existing udev bring-up + [[Adversarial-Honeypot-Hotpot|hot-pot]] (Docker) come with it |
| **40-failsafe** | ❌ | no built-in radio to fail; a VM's uplink is the host vNIC. See exception below |
| **eink-panel** | ❌ | SPI/GPIO HAT — nothing to pass through |

## Hardware passthrough plan
The dividing line is **USB-attached (crosses) vs. board-bonded (doesn't):**
- **MT7612U dongle** (`wlan1`, ap-testbed AP) → USB passthrough. `mt76` AP mode is
  actually *more* reliable than the Pi's brcmfmac — this is an upgrade, not a compromise.
  > [!note] One shared dongle, moved between hosts
  > Plan is to physically move the **same** MT7612U between the Pi and the Mac VM — so
  > **only one host runs the AP-testbed at a time**, whichever holds the dongle. This is
  > already handled cleanly by the capability design: unplugging it fires the Pi's udev
  > **teardown**, and plugging it into the VM (passthrough) fires the same **bring-up**
  > there. No config toggle needed — the hardware's presence *is* the selector. Just
  > don't expect both boxes to have a live testbed simultaneously.
- **hw-bench gear** (CH341A flash programmer, logic analyzer, Bus Pirate, UART
  adapters) → all USB → passthrough. The VM becomes a portable [[CTF-Toolkit|bench]].
- **[[wifi-failsafe]]** (built-in `wlan0`) → does not cross. It solves the *headless-Pi-
  loses-Wi-Fi* problem, which doesn't exist in a VM. **Exception:** to *test failsafe
  code changes* before pushing to the Pi, pass a cheap second USB Wi-Fi as `wlan0` and
  enable the layer explicitly. Dev use only.
- **[[Eink-Panel]]** (SPI/GPIO HAT) → does not cross. Pi-only.

Net: a **~90% clone** — everything except the two things that *are* the Pi's physical
signature (built-in failsafe radio + e-ink HAT).

## Networking, identity, resources, secrets
- **Tailscale:** the VM joins the tailnet as its own node (e.g. `tsoyp-vm`). Admin
  console is then `http://<vm-tailscale-ip>:8787`. No failsafe needed for reachability.
- **Resources:** Mythic is a multi-container Docker stack (Postgres/RabbitMQ/…). With
  Sliver + sensors up too, budget **≥ 6–8 GB RAM / 4 vCPU / 60 GB disk**.
- **Secrets:** the VM needs its **own** git-ignored `secrets.env`. Reusing the same
  API keys on two live nodes can trip provider rate limits / ToS — prefer separate keys.

## Work items
**Selector implemented 2026-08-12** (branch `feat/vm-profile` → PR, tracks issue #1):
- [x] `ARCH=$(dpkg --print-architecture)` for the arch-specific pulls — **`00-core`** (Go) and **`50-c2-sliver`** (Sliver binary). *(Realization: `60-sensors`' Suricata source-build is arch-agnostic and already correct for arm64 — no change needed.)*
- [x] `PROFILE=pi|vm` (+ `--profile`, auto-detected) and a profile-specific default layer set in `bootstrap.sh`; capability probes (`have_builtin_wifi` / `have_ap_dongle` / `has_spidev`, `ARCH`) live in `lib/common.sh`.
- [x] Capability self-skip on **`40-failsafe`** (`have_builtin_wifi`). *(Realization: **`30-ap-testbed` installs on both** — it's files + a udev rule that fires when the dongle appears, so a build-time probe would wrongly skip it; and **eink has no build layer** — it's a separate companion Pi — so neither needs a guard.)*
- [x] `90-verify.sh` profile-aware — the `wifi-failsafe` hard-check runs only on `pi`.
- [x] `mt76`/`firmware-misc-nonfree` best-effort install in `00-core` for the dongle.

**Validated on `kalivm` 2026-08-13:**
- [x] Full install: every layer `00`–`70` (minus Pi-only failsafe) installs + `./bootstrap.sh --check` passes on Kali arm64 / Python 3.14.
- [x] **Mythic on arm64** — 8 containers healthy on 5.8 GB RAM (no OOM); mythic-mcp + caido-mcp build on arm64.
- [x] Bring-up runbook written (below).
- [ ] **MT7612U USB-passthrough** test — still pending the dongle on the Mac.

### Fresh-box bugs found & fixed (PRs #2–#6, all merged)
The Pi masked all of these (it already had the deps / wlan0 / Docker / working versions):
1. `00-core` missing `cmake`/`libpq-dev`/`python3-dev` (hexstrike native deps).
2. `ptai==1.1.0` caps at Python <3.14 → bump `1.2.1`.
3. `install-testbed.sh` aborted on missing `wlan0` under `set -e` → `|| true`.
4. `30-ap-testbed` hard-verified the hot-pot unit without Docker → conditional.
5. `claude.json.tmpl` hardcoded `/home/tsoyp` → `{{HOME}}` (broke every local MCP).
6–7. greynoise **and** kali-server MCPs pulled `mcp 2.0` (fastmcp removed) → pin `mcp<2`.
8. Sliver `operator` needs `--permissions all` (v1.7.3).
9. `get.docker.com` sets suite `kali-rolling` (unpublished) → Kali-native `docker.io` + compose v2 plugin.
10–11. mythic-mcp & caido-mcp build from `./cmd/...` (not top-level); caido made non-fatal (x86-only).
12. hexstrike backend unit missing `HOME` → `/.hexstrike_data` PermissionError.
13. `suricata-update` not installed → zero rules; install from Kali apt.

## VM bring-up runbook
Reproduces the `kalivm` build. **~45–60 min** end to end on an M-series Mac.

1. **Create the VM** (hypervisor: VMware Fusion / Parallels / UTM). Kali arm64.
   - **Disk ≥ 64 GB** (Kali's 20 GB default fills up — the stack needs ~25 GB; growing later means swap-partition surgery). RAM **6–8 GB**, 4 vCPU.
   - Keep the login user simple; the stack is now user-agnostic (validated under `kalivm`, not just `tsoyp`).
2. **First boot — make Tailscale survive reboots** (the #1 gotcha): `sudo systemctl enable --now tailscaled && sudo tailscale up`. Without `enable`, `tailscaled` isn't running on boot and the node keeps dropping offline.
3. **SSH + passwordless sudo** (for a driven install): `sudo systemctl enable --now ssh`; add your key to `~/.ssh/authorized_keys`; `echo "<user> ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/<user>-nopasswd && sudo chmod 440 …`.
4. **Get the repo** — `rsync` from the Pi (no GitHub auth on the VM) or `git clone` the private repo. Seed a git-ignored **`secrets.env`** (`VT_API_KEY`, `GREYNOISE_API_KEY`; Mythic's is captured during layer 51).
5. **Build** — `./bootstrap.sh --profile vm` (auto-detects `vm`; feed `yes` if non-interactive, for the preflight confirm). `--all` (or `--layers …`) for the opt-in C2/sensors/phishing/ctf/automation. Docker gets installed by layer 51.
6. **Post-install:** restart Claude Code to load `~/.claude.json` (9/10 MCPs connect; `caido` needs the x86 laptop). Install the hot-pot once Docker's up: `sudo bash ~/ap-testbed/install-hotpot.sh`. Start sensors per [[Reboot-Runbook]].

> [!note] Admin console (the "testbed link")
> `http://<vm-tailscale-ip>:8787` — user `admin`, password in `~/ap-testbed/state/admin.pass`. Binds `0.0.0.0`, so also reachable on the VM's LAN IP.

## Open risks
- USB-passthrough stability for the Wi-Fi dongle under the chosen hypervisor (untested).
- Docker-in-VM resource pressure on smaller MacBooks (16 GB comfortable; 8 GB tight; Mythic ran on 5.8 GB but with little headroom).
- `Mythic` clone: the `v3.4.0` tag checkout warned and fell back to the default branch — pin/verify the Mythic version if exact reproducibility matters.
- Mythic arm64 payload-type coverage (verify, don't assume).
- USB-passthrough stability for the Wi-Fi dongle under the chosen hypervisor.
- Docker-in-VM resource pressure on smaller MacBooks (16 GB is comfortable; 8 GB is tight).

## Related
[[Replication-Guide]] · [[Reboot-Runbook]] · [[Autonomous-AP-Testbed]] ·
[[Adversarial-Honeypot-Hotpot]] · [[wifi-failsafe]] · [[Eink-Panel]] · [[Architecture-Overview]]
