---
title: /identity-osint
tags: [skill, agent, offensive, osint, people, exposure, scope-gated]
skill_name: identity-osint
model: claude-opus-5
file: ~/.claude/agents/identity-osint.md
updated: 2026-08-14
---

# /identity-osint

Part of [[Operator-Skills]]. The **people & exposure** OSINT axis that [[osint-profile]]
(infra/domain) doesn't cover: username enumeration (`sherlock`), social-footprint
(`social-analyzer`), internet exposure (`shodan`/`censys`), breach/enrichment context —
synthesized into a per-identity dossier.

**HARD scope-gated** to a named, operator-confirmed subject list, **passive only**. Two
sanctioned uses: authorized [[phish-sim]] target profiling (pretext material for
consenting participants) and defensive self-exposure review. Refuses stalking/doxxing/
profiling a private individual without authorization — same guardrail spirit as
[[phish-sim]]. Feeds pretext to [[phish-sim]]; never contacts the subject itself.
