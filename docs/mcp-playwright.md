---
title: Playwright MCP
tags: [mcp, browser, automation, playwright]
tool_prefix: "mcp__playwright__"
transport: stdio
updated: 2026-07-27
---

# Playwright MCP

Part of [[MCP-Servers]].

## What it is
Official Playwright MCP — headless/headed browser automation. Navigate, click, type, fill forms, snapshot the accessibility tree, screenshot, read console + network, and run JS in-page.

## Config (`~/.claude.json`)
```jsonc
"playwright": {
  "command": "/usr/share/nodejs/corepack/shims/npx",
  "args": ["-y", "@playwright/mcp"]
}
```

## Key tools (prefix `mcp__playwright__`)
- **Navigate:** `browser_navigate`, `browser_navigate_back`, `browser_tabs`
- **Interact:** `browser_click`, `browser_type`, `browser_fill_form`, `browser_select_option`, `browser_hover`, `browser_press_key`, `browser_drag`
- **Observe:** `browser_snapshot`, `browser_take_screenshot`, `browser_console_messages`, `browser_network_requests`, `browser_find`
- **Advanced:** `browser_evaluate`, `browser_run_code_unsafe`, `browser_file_upload`, `browser_handle_dialog`

## Basic usage
```
browser_navigate(url) → browser_snapshot → browser_click(ref)
→ browser_fill_form(...) → browser_network_requests
```

## Notes
- General-purpose: authenticated-app walkthroughs, reproducing web findings visually, scraping JS-rendered content. Complements [[mcp-caido]] (proxy-level) and [[mcp-hexstrike]] (scanner-level). Not bound to a named skill.
