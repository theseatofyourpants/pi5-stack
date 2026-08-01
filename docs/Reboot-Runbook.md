---
title: Reboot Runbook
tags: [runbook, operations, reboot]
updated: 2026-08-01
---

# Reboot Runbook

Back to [[00-Index]]. What survives a Pi reboot and what has to be brought back by hand. **Much of this became automatic on 2026-08-01** — most of the stack now self-recovers.

## Survives reboot automatically ✅

| Component | Mechanism | Note |
|-----------|-----------|------|
| [[Sliver-Server]] daemon | `sliver.service` (systemd, enabled) + `stack-watchdog.timer` | reboot-resilient since 2026-08-01 |
| [[mcp-kali-server]] backend (:5000) | `kali-server.service` (systemd, enabled) | systemd-ized 2026-08-01 |
| [[Mythic-Server]] (8 containers) | `restart=always` + `docker.service` enabled | auto-restarts on boot (the old "run mythic-cli start" note was stale) |
| [[Autonomous-AP-Testbed]] + [[Adversarial-Honeypot-Hotpot]] | udev + `systemd-udev-trigger` replays the dongle `add` | AP + hot-pot come back if the dongle is attached |
| [[Scheduled-Jobs]] (stack-cron timers) | systemd timers, enabled | stack-status/triage-alerts/backup re-arm on boot |
| [[wifi-failsafe]] | systemd service | survives once installed |
| stack-watchdog | `stack-watchdog.timer` | heals Sliver/Mythic every ~3 min, writes `~/ap-testbed/state/backends.json` |

## Still needs a hand ⚠️

| Component | Restart command | Note |
|-----------|-----------------|------|
| [[Network-Sensors|Suricata]] | `sudo suricata -c /etc/suricata/suricata.yaml -i eth0 -D --pidfile /var/run/suricata/suricata.pid` | not a persistent service (the hot-pot brings up its own instance on wlan1 when armed) |
| [[Network-Sensors|Zeek]] | `source /etc/profile.d/zeek.sh && sudo /opt/zeek/bin/zeekctl deploy` | |
| hexstrike / other MCP backends | see [[Replication-Guide]] | some local HTTP backends still manual |

## Stateless / self-recovering
- **[[mcp-caido|caido-mcp-server]]** — starts fresh each session; auth token persists in `~/.config/caido-mcp-server/` (Caido itself runs off-box on a laptop)
- **MCP servers generally** — spawned on demand by Claude Code; they just need their *backend* alive.

## Quick "is it alive?" checks
```bash
systemctl is-active sliver.service kali-server.service        # C2 + kali backend
systemctl list-timers 'stack-*' 'triage-*' --no-pager | head  # scheduled jobs armed?
docker ps --filter name=mythic_ --format '{{.Names}} {{.Status}}' | wc -l   # want 8
cat ~/ap-testbed/state/backends.json    # watchdog's live view of sliver+mythic
/opt/zeek/bin/zeekctl status 2>/dev/null | head -3 || echo "zeek down"
```

> [!tip]
> `/stack-status` (also driven on boot by the [[Scheduled-Jobs|stack-status timer]]) runs the full health board automatically — the fastest way to confirm the whole stack is up after a reboot. [[engagement-start]] runs the same checks at the top of every engagement.

## Related
- [[Scheduled-Jobs]] · [[Replication-Guide]] · [[Architecture-Overview]]
