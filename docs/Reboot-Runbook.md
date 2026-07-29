---
title: Reboot Runbook
tags: [runbook, operations, reboot]
updated: 2026-07-27
---

# Reboot Runbook

Back to [[00-Index]]. What survives a Pi reboot and what has to be brought back by hand.

## Does NOT survive reboot — restart manually

| Component | Restart command | Note |
|-----------|-----------------|------|
| [[Sliver-Server]] daemon | `nohup ~/.local/bin/sliver-server daemon > /tmp/sliver-server.log 2>&1 &` | needed for [[mcp-sliver-c2]] |
| [[Mythic-Server]] (8 containers) | `cd ~/Mythic && ./mythic-cli start` | needed for [[mcp-mythic]] |
| [[Network-Sensors|Suricata]] | `sudo suricata -c /etc/suricata/suricata.yaml -i eth0 -D --pidfile /var/run/suricata/suricata.pid` | |
| [[Network-Sensors|Zeek]] | `source /etc/profile.d/zeek.sh && sudo /opt/zeek/bin/zeekctl deploy` | |

## Stateless / self-recovering

- **[[mcp-caido|caido-mcp-server]]** — starts fresh each session; auth token persists in `~/.config/caido-mcp-server/`
- **MCP servers generally** — spawned on demand by Claude Code; no daemon to babysit (they just need their *backend* alive, e.g. Sliver/Mythic/Caido running)
- **wifi-failsafe systemd service** — survives reboot once installed

## Quick "is it alive?" checks

```bash
# Sliver
~/.local/bin/sliver-server version 2>/dev/null || echo "sliver down"
# Mythic
cd ~/Mythic && ./mythic-cli status
# Suricata
systemctl is-active suricata 2>/dev/null || pgrep -x suricata || echo "suricata down"
# Zeek
/opt/zeek/bin/zeekctl status 2>/dev/null | head -3 || echo "zeek down"
```

> [!tip]
> [[engagement-start]] runs these backend + sensor health checks automatically at the top of every engagement — running it after a reboot is the fastest way to confirm the whole stack is up.

## Related
- [[Replication-Guide]] · [[Architecture-Overview]]
