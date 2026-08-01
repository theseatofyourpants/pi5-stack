---
title: /phish-sim
tags: [skill, agent, redteam, phishing, initial-access, social-engineering]
skill_name: phish-sim
model: claude-opus-5
file: ~/.claude/agents/phish-sim.md
updated: 2026-08-01
---

# /phish-sim

Part of [[Operator-Skills]]. The **initial-access front door** for the `phish` engagement type — added 2026-08-01. Before it, `phish` was a [[operation|Phase 0]] engagement type with no runner; the chain could only start from an exposed web surface or assumed-breach.

## Purpose
Run an **authorized red-team phishing / social-engineering simulation**: design the sanctioned pretext + lure, coordinate the payload build, stand up the callback listener, and track which authorized participants interacted — landing footholds into the [[Post-Exploitation]] loop.

## Hard authorization gate (refuses without it)
- Written authorization in the RoE + the **explicit participant list** (only agreed accounts are ever in scope).
- The engagement's **own sending infrastructure** (never personal accounts — the [[mcp-huntress|Gmail MCP]] is for *defensive* [[Blue-Team-Tools|phish-analyze]], not sending).
- Never mass-sends, never expands the list, **operator go/no-go on delivery** (prepares the campaign, waits for approval — never auto-blasts).

## Flow
1. **Pretext & lure** — `pentest-ai test_social_engineering` structures the approved scenario.
2. **Delivery mechanism** — one of three per objective (see [[Phishing-Infra]]): (A) implant via [[generate-payload]] + [[Sliver-Server|Sliver]]/[[Mythic-Server|Mythic]] listener; (B) **gophish** campaign (click/cred metrics + landing pages); (C) **evilginx** AiTM (live session/MFA-cookie capture — the sensitive one, absolute scope gate).
3. **Delivery** — operator-gated, sanctioned infra only.
4. **Track & hand off** — landed callback = foothold → [[Post-Exploitation]] loop. Metrics + IOCs → [[detection-engineer]] for email/link detections.

## How it fits
Wired into [[operation]] as **Phase 4b** (parallel to [[web-assess]] as an initial-access route). It's ultimately a defensive exercise — the output includes the awareness/training takeaways, not just the compromise.

## Related
- [[Phishing-Infra]] (gophish + evilginx setup) · [[operation]] · [[generate-payload]] · [[Post-Exploitation]] · [[Blue-Team-Tools|phish-analyze]] (the defensive counterpart)
