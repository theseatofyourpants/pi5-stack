---
title: Operator Skills Index
tags: [moc, skills, agents]
updated: 2026-07-27
---

# Operator Skills Index

Back to [[00-Index]]. The custom subagents in `~/.claude/agents/`. Each is a single `.md` file: YAML frontmatter (`name`, `description`, `model`, `tools`) + a body that is the agent's operating manual. Invoked as `/name`.

## The shared pattern
Every skill uses **Opus 5 as orchestrator** + **Haiku 4.5 subagents** for data-heavy work, and writes its artifact to `~/engagements/`. See [[Architecture-Overview]] for the orchestration model.

## The lifecycle skills, by phase

| Order | Skill | Phase | MCPs it drives | Output |
|-------|-------|-------|----------------|--------|
| 1 | [[engagement-start]] | Setup | mythic, sliver, wstg-pentest | `~/engagements/{op}-brief.md` |
| 2 | [[osint-profile]] | Recon | hexstrike, kali-server, virustotal, greynoise | `~/engagements/osint-{domain}-{date}.md` |
| 3 | [[web-assess]] ⭐ | Exploitation | wstg, hexstrike, pentest-ai, playwright, caido | `~/engagements/web-assess-{target}-{date}.md` |
| 4 | [[generate-payload]] | Weaponization | mythic, sliver | `~/engagements/payload-{name}-{ts}.md` |
| 5 | [[pivot-analysis]] | Post-exploitation | mythic, sliver | `~/engagements/pivot-{ts}.md` |
| 6 | [[triage-alerts]] | Blue-team correlation | huntress, mythic, sliver, virustotal, greynoise, sensors | `~/engagements/triage-{ts}.md` |
| 7 | [[detection-engineer]] | Detection eng | mythic(ATT&CK), huntress, wstg, virustotal | [[Detection-Library]] |
| 8 | [[debrief]] | Reporting | mythic, sliver, wstg, virustotal, sensors | `~/engagements/{op}-debrief-{date}.md` |

## Ops + orchestration skills

| Skill | Role | Output |
|-------|------|--------|
| [[operation]] ⭐ | **Master orchestrator** — chains all the above with decision gates | `~/engagements/{op}-operation-log.md` |
| [[stack-status]] ⭐ | Preflight health check of the whole stack | status board |
| [[engagement-backup]] ⭐ | Snapshot deliverables (secrets redacted) | `~/backups/pi5-stack-backup-{ts}.tar.gz` |

⭐ = added in the 2026-07-27 gap-closure pass.

## Autonomous / testbed skills

| Skill | Role | Output |
|-------|------|--------|
| [[device-assess]] | **Unattended** scope-locked network+device assessment of one connected device; drives the [[Autonomous-AP-Testbed]] | `~/engagements/auto-{mac}-{ts}.md` |
| [[hotpot-maintain]] | Keeper/monitor for the [[Adversarial-Honeypot-Hotpot]] deception layer — health, isolation assertion, honeytoken rotation, hostile-recon intel rollup. Read/rotate/report only, no offensive tools | `~/engagements/hotpot-{ts}.md` |

Unlike the lifecycle skills, `/device-assess` runs headless (no operator gates) — launched by the testbed's `trigger-scan.sh`, not by hand. `/hotpot-maintain` is operator-run and deliberately has **no** attack tooling — it observes and attributes, it never touches the prober.

## The red → blue loop
Skills 1–5 are offensive; 6–8 turn that activity into detections and a client report. [[triage-alerts]] and [[detection-engineer]] both read the [[Network-Sensors|Suricata/Zeek]] logs, [[triage-alerts]] now adds [[mcp-greynoise|GreyNoise]] noise-vs-targeted context, and [[debrief]] folds the [[Detection-Library]] coverage into the final report. [[web-assess]] closed the exploitation gap that used to sit between recon and post-ex. This loop is the whole point of the build — see [[Architecture-Overview]].
