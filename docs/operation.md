---
title: /operation
tags: [skill, agent, orchestrator, master, lifecycle]
skill_name: operation
model: claude-opus-5
file: ~/.claude/agents/operation.md
updated: 2026-07-27
---

# /operation

Part of [[Operator-Skills]]. **The master orchestrator** — runs a whole engagement by chaining the specialist skills, with operator decision gates between phases.

## Purpose
Be the conductor. `/operation` doesn't do offensive or defensive work itself; it sequences the specialists, carries state between them, and pauses at gates so the operator stays in control. One command to run (or resume) an entire engagement instead of invoking each skill by hand.

## How it invokes specialists
Via the Agent tool, by `subagent_type`. Each specialist is passed the context it needs so it doesn't re-ask the operator; `/operation` reads each one's summary to decide the next gate.

## The lifecycle (gated)
| Phase | Specialist | Gate |
|-------|-----------|------|
| 0 Direct | — (AskUserQuestion) | scope, type, which phases to run |
| 1 Preflight | [[stack-status]] | **stop if stack not ready** |
| 2 Setup | [[engagement-start]] | — |
| 3 Recon | [[osint-profile]] | which targets go active? |
| 4 Web assess | [[web-assess]] | foothold → weaponize now? |
| 5 Weaponize | [[generate-payload]] | — (OPSEC gate inside skill) |
| 6 Post-ex | [[pivot-analysis]] | confirm before creating listeners |
| 7 Blue loop | [[triage-alerts]] → [[detection-engineer]] | optional interval re-run |
| 8 Debrief | [[debrief]] | — |
| 9 Backup | [[engagement-backup]] | confirm before any remote push |

## Subset / resume
Runs any subset in order (always preflight first, always offer backup last). Resumes a partway engagement by reading existing `~/engagements/{op}-*` artifacts.

## Output
A running **operation log** at `~/engagements/{op}-operation-log.md` (one entry per phase: specialist, outputs, gate decision, artifact path) — the spine tying all per-skill artifacts together — plus a final lifecycle board.

## Design stance
A **gated orchestrator, not an autopilot** — every phase transition with offensive impact or scope implications goes through the operator. Goal is control with less manual glue, not unattended speed. See [[Architecture-Overview]].
