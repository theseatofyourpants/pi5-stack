---
title: VM Lab Clone (Kali on Apple Silicon)
tags: [infra, replication, vm, proposed]
status: proposed
updated: 2026-08-12
---

# VM Lab Clone — Kali on an Apple Silicon MacBook

> [!warning] Proposed / design note — NOT built yet
> This documents a planned `vm` build profile of the [[Replication-Guide|rebuild]].
> Nothing here is deployed. It exists so the build, when we do it, is one-repo and
> low-drift. See [[Architecture-Overview]] for the live Pi stack this mirrors.

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

## Mechanism: a `vm` profile, NOT a fork
A separate fork repo would force every fix (e.g. the Aug-2026 captive-portal DNS
hijack — one commit that fixed the live Pi *and* the rebuild) to be hand-ported to
two places forever. Instead, **one repo, capability-probed layers:**

- `bootstrap.sh` already selects layers (`--layers`, `--from`, `--all`,
  `DEFAULT_LAYERS` vs `OPTIN_LAYERS`). A `vm` build is largely "run the software
  layers, let hardware layers self-skip."
- Add `PROFILE=vm|pi` (env or flag) that (1) picks a layer set and (2) makes each
  hardware layer **early-exit on a capability probe** rather than on a hardcoded host.
- Make `layers/90-verify.sh` **profile-aware** — today it `chk`s `hostapd` and
  hardware services and would *fail the VM build* otherwise.

### Capability probes (per layer)
| Layer | Probe → run if… |
|---|---|
| `30-ap-testbed` (+ hot-pot) | a second wifi iface appears (`iw dev` shows the passed-through `mt76`). Already **udev/event-driven** off the dongle — see [[Autonomous-AP-Testbed]]. |
| `40-failsafe` | a built-in client radio to "lose" exists. **Normally skipped in the VM** (see below). |
| `eink-panel` | `spidev` present. Never true in a VM → always skipped. |

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

## Work items (when we build)
1. `ARCH=$(dpkg --print-architecture)` across the hardcoded `linux-arm64` pulls (`00`, `50`, sensor build).
2. Add `PROFILE=vm|pi` + a `vm` layer set to `bootstrap.sh`.
3. Capability-probe self-skips in `30-ap-testbed`, `40-failsafe`, and the eink install.
4. Make `90-verify.sh` assert only the active profile's expected services.
5. Ensure `mt76` firmware in `00-core`; document the hypervisor + USB-passthrough steps.
6. A short **VM bring-up runbook** (hypervisor, guest install, passthrough, `secrets.env`, `./bootstrap.sh --profile vm`).

## Open risks
- Mythic arm64 payload-type coverage (verify, don't assume).
- USB-passthrough stability for the Wi-Fi dongle under the chosen hypervisor.
- Docker-in-VM resource pressure on smaller MacBooks (16 GB is comfortable; 8 GB is tight).

## Related
[[Replication-Guide]] · [[Reboot-Runbook]] · [[Autonomous-AP-Testbed]] ·
[[Adversarial-Honeypot-Hotpot]] · [[wifi-failsafe]] · [[Eink-Panel]] · [[Architecture-Overview]]
