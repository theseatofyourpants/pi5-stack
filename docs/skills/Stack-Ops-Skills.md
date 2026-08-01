---
title: Stack-Ops Skills
tags: [skill, ops, maintenance, meta, mcp]
updated: 2026-08-01
---

# Stack-Ops Skills

Part of [[Operator-Skills]]. Maintenance/meta **SKILL.md skills** (in `~/.claude/skills/`, not agents) added 2026-08-01 — inline runbooks that codify the stack-keeping procedures this build kept doing by hand. Unlike agents, a skill loads its procedure into the current session rather than spawning a subagent.

## The skills
| Skill | Does | Codifies |
|-------|------|----------|
| `mcp-doctor` | Repair a broken/keyless MCP: check the env-var name the package reads, validate the key against a **live authenticated** endpoint, check for a deprecated upstream API, patch `~/.claude.json`, note the restart caveat | the VirusTotal ([[mcp-virustotal]]) + GreyNoise ([[mcp-greynoise]]) fixes of 2026-08-01 |
| `add-mcp` | Onboard a *new* MCP end-to-end (install → config → key → validate → document) | the greenfield sibling of mcp-doctor |
| `stack-restore` | Recover from a [[Scheduled-Jobs\|backup.sh]] archive; re-add the secrets redacted at backup time | the recovery half of the backup job |
| `vault-sync` | Keep **this vault** (`~/pi_design`) current — per-component notes, [[00-Index]] MOC, wikilinks, reconcile vs reality | this very procedure |
| `pi5-stack-sync` | Reflect changes into `~/pi5-stack` (layers/payload/`versions.env`), mirror the vault into `docs/`, secret-scan gate, conventional-commit + push | [[Replication-Guide]] repo upkeep |

## The two-step doc workflow
Stack changed → **`vault-sync`** (edit notes here) → **`pi5-stack-sync`** (`rsync ~/pi_design → ~/pi5-stack/docs/`, secret-scan, commit, push). Never hand-edit `~/pi5-stack/docs/` — it's a mirror of this vault.

## Related
- [[Replication-Guide]] · [[MCP-Servers]] · [[Blue-Team-Tools|ioc-enrich]] (also a skill, but defensive)
