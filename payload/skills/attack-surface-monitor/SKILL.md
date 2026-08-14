---
name: attack-surface-monitor
description: Continuously watch an AUTHORIZED org's external attack surface and diff it for changes — new subdomains, newly-exposed hosts/ports/services, fresh nuclei findings — since the last run. Combines bbot + shodan/censys + httpx + nuclei with a saved baseline, so you see what CHANGED rather than a full re-scan wall of text. Built to run on a cron via the schedule skill. Passive/light-touch recon only, hard-scoped to an authorized domain/ASN allowlist. Use to keep tabs on an engagement scope over time or to monitor your own perimeter.
---

# attack-surface-monitor — diff an external surface over time

Point this at an **authorized** domain/ASN scope on a schedule; each run it re-enumerates
the surface, compares against the saved baseline, and reports **only the delta** plus any
new vulnerabilities. It's the recon layer of the red→blue loop turned into a sensor.

State lives under `~/engagements/asm/<scope>/` — `baseline.json` (last known surface) and
timestamped `run-*.md` reports.

## Scope gate (do this first, every run)
- Read the scope allowlist (`~/engagements/asm/<scope>/scope.txt` — domains/ASNs the
  operator authorized). **Only** enumerate what's listed. No brute-force, no exploitation.
- If no scope file exists, stop and ask the operator to define the authorized scope.

## 1. Enumerate the current surface (light-touch)
```bash
SCOPE=example.com; DIR=~/engagements/asm/$SCOPE; mkdir -p "$DIR"
# subdomains + hosts (bbot passive+light modules; keep it non-aggressive)
bbot -t "$SCOPE" -f subdomain-enum -rf passive -o "$DIR/bbot" -y 2>/dev/null
# live HTTP surface + tech
httpx -l "$DIR/bbot"/*/subdomains.txt -json -tech-detect -status-code -title -o "$DIR/httpx.json"
# internet-exposure view (needs SHODAN_API_KEY / CENSYS creds)
shodan search "hostname:$SCOPE" --fields ip_str,port,product 2>/dev/null > "$DIR/shodan.txt" || true
```

## 2. Diff against the baseline
Compare this run's `{subdomains, live hosts, open ports/services, tech}` to `baseline.json`:
- **NEW** subdomains / live hosts / exposed ports — the important signal.
- **GONE** assets (decommissioned — note, lower priority).
- **CHANGED** tech/version banners (a service got upgraded/downgraded).

## 3. Vuln-check only the NEW/changed surface
Run `nuclei` (severity high,critical + exposures/cve/misconfig tags) against **only the
new or changed** live hosts — not the whole surface every time. That keeps runs fast and
surfaces freshly-introduced risk.

## 4. Report the delta + roll the baseline
Write `run-<date>.md`: a short "since last run" section (NEW / GONE / CHANGED / new
nuclei findings), then the current totals. If nothing changed, say so in one line.
Overwrite `baseline.json` with the current surface. Escalate genuinely new exposures to
`/threat-hunt` or `/detection-engineer` as fits.

## Scheduling
Register with the **schedule** skill (cron), e.g. daily:
`/schedule attack-surface-monitor for <scope> — run daily 07:00`. First run just
establishes the baseline (everything is "new"); subsequent runs report the delta.
