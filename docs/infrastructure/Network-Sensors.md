---
title: Network Sensors
tags: [infrastructure, blueteam, sensors, suricata, zeek, bettercap]
updated: 2026-07-27
---

# Network Sensors

Back to [[00-Index]]. The wire-level capture that makes the [[Architecture-Overview|red→blue loop]] possible. Installed 2026-07-27.

## Suricata 7.0.10 (IDS)
- **Built from source** — the Kali arm64 `.deb` is unusable (DPDK deps don't exist for arm64). Configured with `--disable-dpdk --disable-ebpf --disable-geoip`. Build needs Rust (rustup) + `cbindgen`.
- Binary: `/usr/local/bin/suricata` — **version check `suricata -V`** (capital V; `--version` errors)
- Logs: `/var/log/suricata/eve.json`
- Rules: `sudo suricata-update` → ET Open (~45k rules)
- Start: `sudo suricata -c /etc/suricata/suricata.yaml -i eth0 -D --pidfile /var/run/suricata/suricata.pid`
- Build script: `~/build-sensors.sh`

## Zeek 8.2.1 (network analysis)
- **Installed from the OpenSUSE OBS `Debian_12` repo** — the Kali `zeek` needs `libc6 < 2.38` but the system has 2.42.
- Binary: `/opt/zeek/bin/zeek` · PATH via `/etc/profile.d/zeek.sh`
- **Logs: `/opt/zeek/logs/current/`** (conn.log, http.log, dns.log — *not* `/var/log/zeek/`)
- Deploy/start: `source /etc/profile.d/zeek.sh && sudo /opt/zeek/bin/zeekctl deploy`
- JA3/JA3S TLS fingerprinting available (feeds YARA/network rules)
- Install script: `~/zeek-install.sh`

> [!warning] courier-mta side effect
> `zeekctl`'s Recommends dragged in **`courier-mta`** (a full mail server) — unwanted attack surface on a pentest box. Remove/mask it.

## bettercap 2.41.5 (wireless survey)
- Kali apt, `/usr/bin/bettercap`
- Passive survey: `sudo bettercap -eval "wifi.recon on; sleep 30; wifi.show; quit"`

## Consumed by (via Bash log reads, not an MCP)
- [[triage-alerts]] — Suricata/Zeek ↔ Huntress cross-sensor correlation
- [[detection-engineer]] — Suricata log validation (would my rule fire? did an ET rule already catch it?)
- [[debrief]] — sensor evidence for the detection-gap section
- [[engagement-start]] — startup health check
- [[osint-profile]] — bettercap wireless survey (Phase 0W)

## Related
- [[Detection-Library]] · [[Replication-Guide]] (the arm64 gotchas in full)
