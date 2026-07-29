---
title: MCP Servers Index
tags: [moc, mcp]
updated: 2026-07-27
---

# MCP Servers Index

Back to [[00-Index]]. All tool surfaces Claude Code can call. Local servers are registered in global `~/.claude.json` under `mcpServers` (all `stdio` transport); Huntress is a claude.ai-side connector.

## Offensive

| Server | What it gives Claude | Backend it needs | Note |
|--------|----------------------|------------------|------|
| Sliver C2 | Implant/session/beacon control, listeners, pivots | Sliver daemon | [[mcp-sliver-c2]] |
| Mythic C2 | Full Mythic API — payloads, callbacks, tasking, artifacts | Mythic Docker | [[mcp-mythic]] |
| hexstrike | 150+ offensive tool wrappers + AI recon/exploit workflows | hexstrike server :8888 | [[mcp-hexstrike]] |
| MCP-Kali-Server | Kali tool runner, reverse shells, SSH sessions, Shodan | kali-server :5000 | [[mcp-kali-server]] |
| pentest-ai | Structured engagement scanner (recon → findings → report) | ptai venv | [[mcp-pentest-ai]] |
| wstg-pentest | OWASP WSTG methodology, task trees, findings, WAF bypass | uv server | [[mcp-wstg-pentest]] |
| Caido | Web proxy history, replay, intercept, findings | Caido on laptop | [[mcp-caido]] |
| Playwright | Headless browser automation | npx | [[mcp-playwright]] |

## Defensive / enrichment

| Server | What it gives Claude | Note |
|--------|----------------------|------|
| VirusTotal | File/URL/domain/IP **reputation** + file behavior | [[mcp-virustotal]] |
| GreyNoise | IP **intent** — internet-noise vs targeted (custom-built, keyless) | [[mcp-greynoise]] |
| Huntress | EDR alert feed — incidents, signals, escalations, remediations | [[mcp-huntress]] |

## Config shape (local servers)

```jsonc
// ~/.claude.json → mcpServers
"<name>": {
  "command": "<binary or shim>",
  "args": ["..."],
  "env": { "...": "..." }   // e.g. VT_API_KEY
}
```

## Which skills use which servers

- [[engagement-start]] → mythic, sliver-c2, wstg-pentest
- [[osint-profile]] → hexstrike, mcp-kali-server, virustotal, **greynoise**
- [[web-assess]] → wstg-pentest, hexstrike, pentest-ai, playwright, caido
- [[generate-payload]] → mythic, sliver-c2
- [[pivot-analysis]] → mythic, sliver-c2
- [[triage-alerts]] → huntress, mythic, sliver-c2, virustotal, **greynoise**
- [[detection-engineer]] → mythic (ATT&CK), huntress, wstg-pentest, virustotal
- [[debrief]] → mythic, sliver-c2, wstg-pentest, virustotal
- [[stack-status]] → sliver-c2, mythic, greynoise, virustotal (health probes)

> [!note] Orphaned-MCP status
> `pentest-ai`, `caido`, and `playwright` are **no longer orphaned** — [[web-assess]] now orchestrates all three, and hexstrike's web/RE families are exercised too.
