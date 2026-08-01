---
title: Phishing Infrastructure (gophish + evilginx)
tags: [infrastructure, redteam, phishing, initial-access, aitm]
updated: 2026-08-01
---

# Phishing Infrastructure (gophish + evilginx)

Back to [[00-Index]]. The initial-access tooling behind [[phish-sim]] (the `/operation` Phase 4b agent). **Both are per-engagement infra — started by the operator during an authorized simulation, never run always-on.** Added 2026-08-01.

## gophish — campaign management
- Installed: Kali package, `/usr/bin/gophish`, config `/etc/gophish/config.json`.
- Admin UI/API on `:3333`, phishing web server on `:80`. Drive it from Bash via its **REST API** (curl + admin API key): sending profile → email template → landing page → campaign scoped to the sanctioned participants → launch → poll opens/clicks/submits.
- Role: click/credential-awareness **metrics** + landing pages. Captures *that* a submit happened for the report — not reusable secrets beyond the sanctioned objective.

## evilginx — AiTM session/MFA-cookie capture
- Built from source (Go 1.26.5, arm64) → `~/.local/bin/evilginx`; source + phishlets at `~/evilginx2/` (`phishlets/` dir). Version pinned in `~/pi5-stack/versions.env`.
- Role: adversary-in-the-middle reverse proxy that relays a real login and steals the **post-auth session cookie → bypasses MFA**. Materially more sensitive than gophish; the gate is absolute (authorized target service + participant list only; phishlet **operator-supplied per engagement**, never for out-of-scope services; tokens secured on-stack, destroyed after).

> [!warning] Operational constraints (enforce before starting evilginx)
> - Needs a **phishing domain + valid TLS** (evilginx built-in ACME/Let's Encrypt).
> - Binds **:443 / :53 / :80** — these **collide with the [[Autonomous-AP-Testbed]] on `10.66.66.1`**. Do NOT run evilginx alongside the testbed; use dedicated infra/interface and confirm the ports are free first.
> - A captured session is a foothold → hand to the [[Post-Exploitation]] loop.

## Deploy note
`evilginx` binary install was gated by the safety classifier (AiTM credential-theft tool) — the operator deployed it by hand. Rebuild path is `~/pi5-stack/payload/scripts/install-phish-infra.sh` (apt gophish + `go build` evilginx). See [[Replication-Guide]].

## Related
- [[phish-sim]] (the agent that drives this) · [[generate-payload]] (implant option) · [[Post-Exploitation]] · [[operation]] (Phase 4b)
