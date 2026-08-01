---
name: sensor-tune
description: Tune the Suricata + Zeek sensor layer — reduce false positives, add/threshold rules, refresh the ruleset, and check coverage gaps against recent traffic. Use when the sensors are noisy, after adding new services/subnets (like the AP testbed or hot-pot), or periodically to keep detections sharp. Read-only analysis + config edits; never disables detection wholesale.
---

# sensor-tune — keep Suricata/Zeek sharp

Sensors on this box (see [[project-c2-stack]]): **Suricata 7.0.10** (`/usr/local/bin/suricata`, log `/var/log/suricata/eve.json`, hot-pot instance under `/var/log/suricata/hotpot/`), **Zeek 8.2.1** (`/opt/zeek/bin/zeek`, logs `/opt/zeek/logs/current/`). Rules via `sudo suricata-update` (ET Open).

## 1. Measure the noise first
```bash
# top alerting signatures (last N events) — where the FP pain is
jq -r 'select(.event_type=="alert")|.alert.signature' /var/log/suricata/eve.json 2>/dev/null | sort | uniq -c | sort -rn | head -20
# top src/dst for the noisiest sig — is it one benign host?
```
Distinguish **true noise** (benign scanner/health-check/your own AP traffic) from **real low-severity hits**. Never suppress by muting severity globally.

## 2. Suppress / threshold precisely
Edit `/etc/suricata/threshold.config` — target the specific SID + host, not the rule class:
```
# suppress a benign internal source for one noisy sig
suppress gen_id 1, sig_id <SID>, track by_src, ip <benign-ip>
# or rate-limit a chatty-but-useful sig
threshold gen_id 1, sig_id <SID>, type limit, track by_src, count 1, seconds 300
```
Reload: `sudo suricatasc -c reload-rules` (or restart the instance). Document every suppression + why (a silent suppression is a detection gap).

## 3. Refresh + add coverage
```bash
sudo suricata-update && sudo suricatasc -c reload-rules      # pull latest ET Open (~45k)
```
For a new service/subnet (AP testbed 10.66.66.0/24, hot-pot bait), confirm the sensor is actually on that interface and add local rules for expected-bad (any hit on bait = alert). Local rules → `/etc/suricata/rules/local.rules`.

## 4. Coverage-gap check
Cross-reference against `~/engagements/detection-library/` and `/detection-engineer`: for TTPs you've run in engagements, is there a network sig that would have caught them? Zeek's JA3/JA4/HASSH logs (`/opt/zeek/logs/current/ssl.log`, `conn.log`) fill gaps Suricata sigs miss. List what's uncovered and feed it to `/detection-engineer` to author rules.

## 5. Report
Summarize: top FPs suppressed (with justification), rules added, ruleset freshness, and remaining coverage gaps. This pairs with `/triage-alerts` (consumes cleaner alerts) and `/hotpot-maintain` (bait-hit alerting).
