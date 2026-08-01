---
title: /generate-payload
tags: [skill, agent, weaponization, opsec]
skill_name: generate-payload
model: claude-opus-5
file: ~/.claude/agents/generate-payload.md
updated: 2026-07-27
---

# /generate-payload

Part of [[Operator-Skills]]. OPSEC-aware payload builder for Sliver and Mythic.

## Purpose
Not just "spit out a command" — surface every build decision with its tradeoffs so the operator understands what they're deploying. Never skips the OPSEC checklist; never generates a payload without a killdate.

## MCPs it drives
[[mcp-sliver-c2]] · [[mcp-mythic]]

## Workflow
1. **Target context:** OS/arch, delivery mechanism, environment (EDR? egress filtering? proxy?), duration, objective, constraints.
2. **C2 selection:** recommends Sliver (fast/simple/interactive) vs Mythic (complex post-ex, multi-operator, specific agents like Apollo/Poseidon/Medusa) — with reasoning, not a blind choice.
3. **Transport selection:** HTTPS / DNS / mTLS / WireGuard / HTTP walked through with when-to-use / when-not, plus a redirector nudge (direct C2 IP is an IOC).
4. **OPSEC checklist:** sleep (60–300s ext / 30s int), jitter (20–40%), killdate (end + 7d), custom UA, spawn-to process (svchost/explorer, never powershell/cmd), format vs delivery, staged vs stageless, evasion flags, persistence (only if required — high noise).
5. **Generate build command** (Haiku subagent formats it; verifies a matching listener exists).
6. **OPSEC summary** with residual risks + recommended next steps.

## Output
`~/engagements/payload-{name}-{timestamp}.md` (parameters + OPSEC summary).

## Detection handoff (added 2026-07-27)
- **Step 7:** after writing the spec, offers to seed a **detection stub** via [[detection-engineer]] — pre-filling the TTP intake with the exact callback host, UA, TLS/JA3 profile, sleep pattern, and spawn-to process it just chose. This means blue-team coverage exists *before* the implant is even deployed, so [[triage-alerts]] and [[debrief]] have a candidate rule to compare against the moment it lands.

## Notes
- Enforced rule: **always a killdate.** Offers to start a listener if none matches the chosen transport.
- The TTPs chosen here are exactly what [[detection-engineer]] later turns into rules, and what [[triage-alerts]] expects to see in the alert feed.
