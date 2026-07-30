---
title: C2 Frameworks Primer — Sliver & Mythic
tags: [c2, sliver, mythic, redteam, primer, concepts]
platform: "Raspberry Pi 5 / Kali Rolling / arm64"
updated: 2026-07-30
---

# 🎛️ C2 Frameworks Primer — Sliver & Mythic

Back to [[00-Index]]. A conceptual "how does C2 actually work" reference for the
two frameworks in this stack. Pairs with the infra notes [[Sliver-Server]] and
[[Mythic-Server]] (how they're installed/run here) and the MCP notes
[[mcp-sliver-c2]] / [[mcp-mythic]] (the tool surface Claude drives them with).

> [!info] Scope
> Conceptual + operational, for **lab / authorized engagement** use. C2 is remote
> administration built for adversary simulation — the value here is understanding
> the model so the [[Operator-Skills|operator skills]] make sense.

## 1. The mental model every C2 shares

Strip away tradecraft and every C2 framework has the same five parts:

| Piece | What it is | This stack's name for it |
|---|---|---|
| **Team server** | Long-running server holding all state, brokering everything | `sliver-server daemon` / the Mythic Docker stack |
| **Operator client** | What you (or Claude via MCP) drive it with | Sliver client / Mythic web UI + GraphQL |
| **Listener / C2 profile** | The server's "ears" — a port+protocol agents call home to | `sliver_start_https`, Mythic's `http` profile |
| **Payload / implant / agent** | The program run on the target that calls back | Sliver implant, Mythic agent (Apollo, Poseidon…) |
| **Tasking loop** | Queue a command → agent fetches → runs → returns output | `sliver_execute`, `mythic_issue_task` |

### Session vs. Beacon (the concept that matters most)

Both frameworks support both modes:

- **Session (interactive)** — the implant holds a live connection; you type, it
  responds instantly. Great in a lab; loud and fragile on a real network.
- **Beacon (asynchronous)** — the implant **sleeps**, wakes on an **interval** +
  random **jitter**, asks "any tasks?", runs them, sleeps again. This is how real
  intrusions operate: a 60s/30%-jitter beacon checks in every ~42–78s, so there's
  no persistent connection to spot. You **queue** tasks and collect results on the
  next check-in. See [[generate-payload]] for the OPSEC knobs (sleep/jitter/killdate).

Everything else — transports, evasion, pivoting — is variation on those five parts.

## 2. Sliver — the self-contained one

Open-source C2 by Bishop Fox, written in **Go**. Philosophy: *one static binary,
batteries included*; cross-compiles dependency-free implants for Win/Lin/macOS.

- **Server:** `sliver-server` daemon (does **not** survive reboot — see
  [[Reboot-Runbook]]; restart with `nohup ~/.local/bin/sliver-server daemon &`).
- **Operator connection:** mutual-TLS via a `.cfg` (here: `~/sliver-claude.cfg`).
  The [[mcp-sliver-c2]] server is just another mTLS operator client.

**Workflow → MCP tool:**
1. **Listener** — `sliver_start_https` / `_mtls` / `_dns` / `_wg`. mTLS (default,
   encrypted), HTTPS (blends with web traffic), DNS (slow, beats egress filtering),
   WireGuard.
2. **Generate implant** — C2 config baked into the binary. `sliver_implant_profiles`
   = reusable configs; `sliver_implant_builds` = compiled artifacts.
3. **Callback** — appears in `sliver_sessions` (interactive) or `sliver_beacons` (async).
4. **Task** — `sliver_execute`, `sliver_shell`, `sliver_ls/cd/download/upload`,
   `sliver_ps`, `sliver_ifconfig`, `sliver_netstat`, `sliver_screenshot`.
5. **Pivot** — `sliver_pivot_start_tcp`: a compromised host relays C2 for hosts it
   can reach but you can't. See [[pivot-analysis]].

**Extending it:** the **armory** (`armory install`) pulls community BOFs, .NET
assemblies, and aliases — post-ex tooling without recompiling.

**Sweet spot:** fast to stand up, excellent default implant, internal pivoting, and
learning. The grab-and-go C2.

## 3. Mythic — the extensible platform

Open-source C2 by Cody Thomas (`@its_a_feature_`), a **Docker microservices
platform**. `mythic-cli start` brings up Postgres + a GraphQL API + the web UI +
one container **per agent** and **per C2 profile**. (Also reboot-fragile — see
[[Mythic-Server]] / [[Reboot-Runbook]].)

**Key idea — agent-agnostic:** Mythic is the *management plane*; implants are
pluggable "agents" you install with `mythic-cli install github <url>`:
- **Apollo** — Windows/.NET, flagship for AD/Windows work.
- **Poseidon** — Go, cross-platform (Lin/macOS/Win).
- Others: Athena, Medusa, etc.

**C2 profiles are swappable containers** too — `http`, `dynamichttp`, `websocket`,
`tcp` (P2P). A profile defines *how* the agent talks (URIs, headers, UA, jitter) so
traffic can be shaped to look benign. **Translation containers** let an agent speak
a fully custom/encrypted wire format.

**Workflow → MCP tool:**
1. `mythic_login` — authenticate to GraphQL (the [[mcp-mythic]] backbone).
2. `mythic_create_operation` / `_set_current_operation` — an **operation** is the
   engagement container; **operators** join it for team collaboration + deconfliction.
3. Start a C2 profile → `mythic_create_payload` → `mythic_download_payload`.
4. **Callback** — `mythic_get_all_callbacks` / `_get_active_callbacks`.
5. **Task** — `mythic_issue_task`, collect with `mythic_get_task_output`. Every task
   is logged, timestamped, and **auto-mapped to MITRE ATT&CK**.

**Sweet spot:** team operations, tailored agents/profiles per engagement, deep
logging/reporting, collaboration. The platform you build an engagement on.

## 4. Sliver vs. Mythic — when each

| | **Sliver** | **Mythic** |
|---|---|---|
| Setup | One binary, minutes | Docker stack, heavier |
| Model | Self-contained implant | Pluggable agents + profiles |
| Best for | Fast ops, pivoting, learning | Team ops, tailored tradecraft, reporting |
| Traffic shaping | Good (HTTP/DNS/WG) | Excellent (per-profile + translation containers) |
| Logging / ATT&CK | Basic | Rich, first-class |

Red teams often run **both**: Sliver for quick access + internal movement, Mythic as
the durable engagement platform with the audit trail. This stack is set up for that
dual use — see [[Architecture-Overview]].

## 5. How it maps onto this stack

The whole lifecycle is already wired (see [[Operator-Skills]]):

- **[[mcp-sliver-c2]] / [[mcp-mythic]]** expose every operation above as a tool, so C2
  can be driven conversationally through Claude.
- **[[engagement-start]]** creates the Mythic operation, initializes tracking, and
  pre-stages Sliver listeners.
- **[[generate-payload]]** — guided, OPSEC-aware builder for both frameworks
  (transport, sleep/jitter, killdate, evasion).
- **[[pivot-analysis]]** — enumerates all Sliver sessions + Mythic callbacks together,
  maps topology, suggests pivot paths.
- **[[debrief]]** — pulls Mythic task history + Sliver session logs into an
  ATT&CK-mapped report.
- **[[stack-status]]** — verifies both backends are up (both are reboot-fragile).

## 6. A safe first walkthrough (lab only)

Against a throwaway VM you own:

1. **[[stack-status]]** — confirm Sliver + Mythic are up.
2. **Sliver first** (simpler): start an mTLS listener → generate a **beacon** with a
   short interval (~10s so you're not waiting) → run on the VM → watch `sliver_beacons`
   → task `whoami` / `ls` / `ifconfig` to feel the queue-then-collect rhythm. Then try a
   **session** implant to feel the interactive difference.
3. **Then Mythic:** `mythic_login`, create an operation, start the `http` profile, build
   a **Poseidon** agent, run it, watch the callback in the UI, issue a task, and see how
   it logs + ATT&CK-tags everything.
4. **Pivot:** from the first VM, start a TCP pivot and route a second, isolated VM's
   implant through it.

## See also
- [[Sliver-Server]] · [[Mythic-Server]] — install/run specifics on this host
- [[mcp-sliver-c2]] · [[mcp-mythic]] — the MCP tool surfaces
- [[generate-payload]] · [[pivot-analysis]] · [[debrief]] — the C2 operator skills
- [[Architecture-Overview]] — how C2 fits the red→blue loop
