---
title: /device-assess
tags: [skill, agent, offensive, testbed, unattended, device]
skill_name: device-assess
model: claude-opus-5
file: ~/.claude/agents/device-assess.md
updated: 2026-07-29
---

# /device-assess

Part of [[Operator-Skills]]. The scan engine behind the [[Autonomous-AP-Testbed]] —
an **unattended, scope-LOCKED, non-destructive** assessment of a *single* device
that connected to the testbed AP.

## Purpose
Take one authorized device (by IP + MAC) and fully assess it — **network + service
enumeration, device/OS fingerprint, device-level vuln identification** — then hand
off to [[web-assess]] *only if* web ports exist. Writes an evidence-based report.

## Why it exists (vs the alternatives)
- Bare [[web-assess]] is web-only — it under-tests everything else on a device.
- [[operation]] is the **wrong** tool to auto-fire: it's interactive/gated and
  includes weaponization, post-ex and C2 — never point it at "whatever joins".
- So `/device-assess` is the focused, autonomous middle ground: no operator gates,
  makes its own decisions, records ambiguity in the report rather than stopping.

## How it's invoked
`trigger-scan.sh` runs headless `claude -p --dangerously-skip-permissions` (no human
to approve tool prompts in unattended mode) with a prompt that says *"use the Agent
tool (subagent_type: device-assess)"*. It is an **agent**, not a slash "skill".

## MCPs / tools it drives
[[mcp-kali-server]] (nmap, nuclei, command) · [[mcp-hexstrike]] (nmap, nuclei, httpx,
wafw00f, nikto, enum4linux, smbmap, detect_technologies) · [[mcp-wstg-pentest]]
(log_finding) · Agent (optional [[web-assess]] handoff) · Bash/Read/Write.

## Method
1. Liveness + **top-1000 TCP** (`--top-ports 1000`) + light UDP, `-sV`/`-O` on the
   open ports. **Proportional & time-bounded**: escalate to a full `-p-` sweep ONLY
   on a rich, stable surface with time to spare — a low-surface device (a phone with
   a few `tcpwrapped` ports) gets a quick pass. Target a few minutes; don't grind an
   absent/flapping host.
2. Device classification (ports, banners, OS fp, MAC OUI, mDNS/UPnP/NetBIOS).
3. Per-service non-destructive enum (TLS, SMB null-read, SSH algos, SNMP public…).
4. Vuln **identification** (nuclei + safe nmap vuln NSE; version→CVE). No exploitation.
5. Web check if web ports (own httpx/wafw00f/nikto; optional [[web-assess]] escalation).
6. Synthesize report → `~/engagements/auto-<mac>-<ts>.md`.

## Safety
Single-IP scope lock, non-destructive, low aggression, rate-limited. Runs as `tsoyp`.
**Hardening pending**: drop arbitrary `Bash`/`command` to only structured scanners
before running consent-mode against untrusted devices (see [[Autonomous-AP-Testbed]]).

## Handoffs
Report surfaces in the testbed admin console + the per-device `status.test` page;
findings logged to [[mcp-wstg-pentest|wstg-pentest]] flow to [[debrief]] /
[[detection-engineer]].
