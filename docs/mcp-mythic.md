---
title: Mythic C2 MCP
tags: [mcp, c2, offensive, mythic]
tool_prefix: "mcp__mythic__"
transport: stdio
updated: 2026-07-27
---

# Mythic C2 MCP

Part of [[MCP-Servers]]. Backend: [[Mythic-Server]].

## What it is
MCP wrapper over the full Mythic C2 GraphQL API. The largest tool surface in the stack (200+ tools) — operations, payloads, callbacks, tasking, artifacts, credentials, MITRE ATT&CK mapping, files, screenshots, keylogs, tags.

## Config (`~/.claude.json`)
```jsonc
"mythic": { "command": "/home/tsoyp/Mythic-MCP/mythic-mcp" }
```
- Source: `nbaertsch/Mythic-MCP` (Go binary, built with [[Replication-Guide|Go 1.26.5]])
- Auth to `https://localhost:7443` as `mythic_admin` (creds live in the MCP env / `~/.claude.json`)
- **Requires all 8 [[Mythic-Server]] Docker containers running.**

## Key tool groups (prefix `mcp__mythic__`)
- **Auth/op:** `mythic_login`, `mythic_is_authenticated`, `mythic_create_operation`, `mythic_set_current_operation`, `mythic_get_current_operation`
- **Payloads:** `mythic_get_payload_types`, `mythic_get_payload_type_build_parameters`, `mythic_create_payload`, `mythic_wait_for_payload`, `mythic_download_payload`
- **C2 profiles:** `mythic_get_c2_profiles`, `mythic_create_c2_instance`, `mythic_start_c2_profile`
- **Callbacks/tasking:** `mythic_get_all_callbacks`, `mythic_get_active_callbacks`, `mythic_issue_task`, `mythic_wait_for_task`, `mythic_get_task_output`
- **Loot:** `mythic_get_credentials`, `mythic_get_artifacts`, `mythic_get_downloaded_files`, `mythic_get_screenshots`, `mythic_get_keylogs`
- **ATT&CK:** `mythic_get_attacks_by_operation`, `mythic_get_attack_technique_by_tnum`, `mythic_add_mitre_attack_to_task`

## Basic usage
```
mythic_is_authenticated / mythic_login
mythic_create_operation("target-YYYY-MM-DD") + set_current_operation
mythic_get_c2_profiles → mythic_create_c2_instance
mythic_create_payload → mythic_wait_for_payload → mythic_download_payload
... callbacks arrive ... mythic_issue_task → mythic_get_task_output
```

## Used by skills
[[engagement-start]] · [[generate-payload]] · [[pivot-analysis]] · [[triage-alerts]] · [[detection-engineer]] · [[debrief]]
