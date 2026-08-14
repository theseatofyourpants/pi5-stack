---
title: /container-hygiene
tags: [skill, agent, blue, defensive, container, supply-chain, maintenance]
skill_name: container-hygiene
model: claude-opus-5
file: ~/.claude/agents/container-hygiene.md
updated: 2026-08-14
---

# /container-hygiene

Part of [[Operator-Skills]]. Blue-team **supply-chain check for the stack's OWN Docker
footprint** — [[Mythic-Server|Mythic]]'s containers + the [[Adversarial-Honeypot-Hotpot|hot-pot]]
images are dependencies, so a critical CVE or leaked secret in one is a hole in your
operating platform.

`trivy`-scans every live image (CVEs, secrets, misconfig), runs `docker-bench-security`
(CIS Docker on the host), and confirms the pinned **Cowrie digest** still matches
`versions.env`. **Read/report only** — never pulls, rebuilds, or restarts; fixes flow
through `versions.env` + a rebuild. Run periodically (pairs with the **schedule** skill)
or before an engagement. Complements [[engagement-backup]] and [[hotpot-maintain]].
