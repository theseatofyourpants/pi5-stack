---
name: vault-sync
description: Keep the ~/pi_design Obsidian architecture vault up to date when the stack changes — add/update the note for a new MCP server, operator skill/agent, service, or config change, maintain wikilinks + frontmatter + the 00-Index MOC, and reconcile the vault against reality. Use after adding or changing any stack component. Pairs with pi5-stack-sync (which mirrors the vault into the repo's docs/).
---

# vault-sync — keep the pi_design Obsidian vault current

The vault at `~/pi_design/` (38+ notes) is the human-facing architecture doc; the project memory (`project_c2_stack.md`) is the machine source of truth. This skill reconciles the vault to reality after a change.

## Vault structure (conventions to preserve)
Notes live in folders (for GitHub browsing; Obsidian resolves `[[links]]` by name, so folder ≠ link path). **Put a new note in the right folder:**
- **root** — the maps only: `00-Index.md` (the MOC), `Architecture-Overview.md`, `Operator-Skills.md`, `MCP-Servers.md`, `Replication-Guide.md`, `Reboot-Runbook.md`.
- **`agents/`** — one note per autonomous operator agent (matches `~/.claude/agents/`): operation, web-assess, phish-sim, etc.
- **`skills/`** — capability-group writeups (Post-Exploitation, Blue-Team-Tools, CTF-Toolkit, Stack-Ops-Skills).
- **`mcp/`** — one `mcp-<name>.md` per MCP server.
- **`infrastructure/`** — servers, sensors, testbed, e-ink panel, scheduled jobs (`Sliver-Server.md`, `Network-Sensors.md`, `Scheduled-Jobs.md`, …).
- **Obsidian idioms:** `[[Wikilinks]]` between notes (bidirectional — link both ways, by **name only**, never a path), YAML frontmatter where present, `#tags`. Match the tone/format of the existing notes.

## Procedure
1. **Diff reality vs vault.** From what changed (this session's work / `project_c2_stack.md` / `claude mcp list` / `ls ~/.claude/agents ~/.claude/skills`), list components that are new, changed, or removed but still documented.
2. **Update the per-component note.**
   - New MCP server → new `mcp-<name>.md` + a row/link in `MCP-Servers.md` and `00-Index.md`.
   - New operator skill/agent → new `<name>.md` + a link in `Operator-Skills.md` (note skill-vs-agent, and any `/operation` phase it plugs into).
   - Changed service/config (e.g. a backend became a systemd unit, an API migrated versions) → update its note **and** `Reboot-Runbook.md` / `Replication-Guide.md` if reboot/rebuild behavior changed.
3. **Fix the links.** Add `[[...]]` both directions; update `00-Index.md` so nothing is orphaned. Cross-link related notes (e.g. a new red-team agent ↔ `operation.md` ↔ `C2-Primer.md`).
4. **Keep it truthful.** The vault must not claim something exists that doesn't (verify file/service/flag before documenting it) or say "not yet installed" for something now live.

## After updating
The repo's `docs/` is a mirror of this vault — run **`pi5-stack-sync`** to copy the changes into `~/pi5-stack/docs/`, commit, and push. Don't hand-edit `~/pi5-stack/docs/` directly; edit the vault here, then sync.
