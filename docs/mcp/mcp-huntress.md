---
title: Huntress MCP
tags: [mcp, edr, blueteam, huntress]
tool_prefix: "mcp__claude_ai_Huntress_MCP__"
transport: "claude.ai connector (remote)"
updated: 2026-07-27
---

# Huntress MCP

Part of [[MCP-Servers]]. The EDR / managed-detection feed that closes the [[Architecture-Overview|red→blue loop]].

## What it is
Read access to a Huntress tenant — incident reports, signals/detections, escalations, agents, organizations, and remediations. This is the "what did the defender catch?" side of the stack.

> [!info] Not a local server
> Huntress is a **claude.ai-side remote connector**, so its tools are namespaced `mcp__claude_ai_Huntress_MCP__*` and it is **not** an entry in `~/.claude.json`. It's enabled on the Claude account, not installed on the Pi.

## Key tools
- **Detections:** `list_signals`, `get_signal`, `list_incident_reports`, `get_incident_report`
- **Escalations:** `list_escalations`, `get_escalation`
- **Assets:** `list_agents`, `get_agent`, `list_organizations`, `get_organization`, `list_identities`
- **Response:** `list_remediations`, `get_remediation`, `list_unwanted_access_rules`
- **Attack surface:** `list_external_ports`, `get_external_port`, `list_known_vpns`

## Basic usage
```
list_incident_reports → recent incidents (severity, host, status)
list_signals          → raw detections w/ timestamps, process, cmdline
get_signal(<id>)      → full detail for correlation
```

## Used by skills
- [[triage-alerts]] — the primary feed; correlated against Mythic/Sliver telemetry to classify TP vs noise vs unknown
- [[detection-engineer]] — coverage check: did Huntress flag this TTP? → COVERED vs GAP verdict
