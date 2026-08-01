---
title: /web-assess
tags: [skill, agent, offensive, web, exploitation]
skill_name: web-assess
model: claude-opus-5
file: ~/.claude/agents/web-assess.md
updated: 2026-07-27
---

# /web-assess

Part of [[Operator-Skills]]. **New skill** — fills the exploitation hole between recon and post-exploitation, and activates three previously-orphaned MCPs.

## Purpose
Take a live web target, map its attack surface, test it methodically against the OWASP WSTG with the hexstrike toolset, **verify every finding before logging it**, and record results into [[mcp-wstg-pentest|wstg-pentest]] so [[debrief]] and [[detection-engineer]] inherit the work automatically.

## Why it exists
Before this skill the chain went `osint-profile → generate-payload → …?… → pivot-analysis` with nothing driving actual web-app testing — even though wstg-pentest, hexstrike-web, pentest-ai, and caido were all installed for exactly that. See [[Architecture-Overview]].

## MCPs it drives
[[mcp-wstg-pentest]] (methodology + findings + knowledge graph) · [[mcp-hexstrike]] (web tools: nuclei/ffuf/dalfox/sqlmap/jwt/graphql/api) · [[mcp-pentest-ai]] (alternate automated engine) · [[mcp-playwright]] (browser/DOM verification) · [[mcp-caido]] (request-level verification — replay, diff, race-window, curl repro)

## Workflow
- **Step 0 — Intake:** targets, scope, auth, app type, aggressiveness gate, prior osint-profile. (Auto-seeded from [[engagement-start]]/[[operation]].)
- **Step 1 — Surface mapping** (parallel Haiku): liveness+tech+WAF, content discovery, crawl, parameter surface. Everything logged via `track_tool`/`parse_tool_output`.
- **Step 1b — Prioritize** (Opus): `prioritize_endpoints` → task tree → decide *which bug class each endpoint can plausibly have*; pre-fetch WAF bypass payloads.
- **Step 2 — Methodology-guided testing:** for each priority endpoint, pull the WSTG method + payloads **first**, then run the matched hexstrike tool (dalfox/sqlmap/jwt/graphql/api/nuclei). `track_test` after each.
- **Step 3 — Verification** (mandatory): reproduce every candidate before it counts — Playwright for DOM/XSS + multi-session access-control, Caido (`send_request`/`edit_request`/`diff_responses`/`race_window_send`/`export_curl`) for injection/replay/race proofs. False positives dropped here.
- **Step 4 — Log + chain:** `log_finding` with PoC + evidence; `add_graph_node/edge`; `find_chains` to compose findings into higher-severity paths.
- **Step 5 — Synthesis + handoffs.**

## Output
`~/engagements/web-assess-{target}-{YYYY-MM-DD}.md` + findings persisted in wstg-pentest.

## Safety
Stays in scope; destructive sqlmap / brute force gated behind operator confirmation; rate-limits fragile targets. Authorized-engagement only.

## Handoffs
- Foothold → [[generate-payload]] → [[pivot-analysis]]
- Any exploited TTP → [[detection-engineer]]
- Findings auto-flow to [[debrief]] (they live in wstg-pentest)
