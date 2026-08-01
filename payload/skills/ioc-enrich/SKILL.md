---
name: ioc-enrich
description: One-shot reputation + intent verdict for a single indicator — an IP, file hash, domain, or URL. Correlates VirusTotal (reputation), GreyNoise (internet-noise vs targeted intent), and Huntress (has it been seen in our environment?) into a single verdict with confidence. Use for quick standalone lookups; /triage-alerts uses the same logic across a whole alert feed.
---

# ioc-enrich — reputation + intent verdict for one indicator

Fast, standalone enrichment. For a full alert feed, use `/triage-alerts`.

## 1. Detect the indicator type
IP / IPv6, sha256|sha1|md5 hash, domain, or URL — route to the right tools.

## 2. Pull the sources (run in parallel)
| Source | Tool | Answers |
|---|---|---|
| **VirusTotal** | `analyze_ip_address` / `analyze_file` / `analyze_domain` / `analyze_url` | reputation — how many engines flag it, categories, first-seen |
| **GreyNoise** (IP only) | `greynoise_context_ip` (keyed) or `greynoise_community_ip` | **intent** — mass internet-noise scanner vs targeted; RIOT (known-benign service); classification/actor |
| **Huntress** | `list_signals` / `list_incident_reports` (filter/grep for the indicator) | has this actually been seen in OUR environment? |

VT and GreyNoise answer different questions — reputation ≠ intent. An IP can be "malicious" reputation but pure internet background noise (GreyNoise), or clean reputation but targeted at you.

## 3. Synthesize a verdict
Combine into one call, most-actionable first:
- **Benign / expected** — GreyNoise RIOT hit (Google/MS/CDN) or clean VT + no Huntress sighting.
- **Noise** — GreyNoise noise=true, mass scanner; VT flags but not targeted. Low priority.
- **Suspicious** — VT detections OR unknown-but-not-noise, no local sighting yet. Watch/block candidate.
- **Malicious + present** — VT-flagged AND a Huntress sighting in-environment → escalate; hand to `/triage-alerts` or an IR flow.

## 4. Output
```
IOC: <value>  (<type>)
VT:        <n>/<m> detections · <categories> · first seen <date>
GreyNoise: <noise/riot/targeted> · <classification> · actor <name>
Huntress:  <seen in env? which org/agent / not seen>
VERDICT:   <benign|noise|suspicious|malicious+present>  (confidence: <lo/med/hi>)
Next:      <block / ignore / watch / escalate>
```
Note any rate-limit degradation (e.g. GreyNoise community mode = 10/day). If enriching several indicators, prefer `/triage-alerts`.
