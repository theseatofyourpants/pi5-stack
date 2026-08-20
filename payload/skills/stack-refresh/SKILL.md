---
name: stack-refresh
description: Periodically review and bump the pinned dependencies of the pi5-stack — run the freshness report, triage what is security-driven vs merely stale vs a Kali-compatibility break, then bump ONE pin at a time with a verify and a rollback path between each. Use on the weekly stack-freshness report, after a Kali dist-upgrade, before an engagement, or when an advisory lands. Pairs with container-hygiene (CVEs), mcp-doctor (a bump that broke an MCP), and pi5-stack-sync (landing the change).
---

# stack-refresh — keep the pins current without breaking a working lab

Everything in `versions.env` is pinned so a rebuild is reproducible. The cost of that
is entropy: a pin is a decision that was correct once, and left alone it becomes an
unpatched, abandoned, or no-longer-buildable dependency. This skill is the scheduled
counterweight.

**The governing rule: one pin at a time, verified before the next.** A batch bump that
breaks something gives you N suspects and no bisect. This lab is the platform the rest
of the work runs on — a broken MCP layer costs more than a slightly stale one.

## 1. Get the facts

```bash
~/pi5-stack/tools/stack-freshness.sh          # read-only, ~20s, changes nothing
```

Reads `freshness.conf` (which pin comes from which upstream) and reports each as:

| | meaning |
|---|---|
| `[ALERT]` | the pinned ref no longer exists upstream — **a rebuild would fail today** — or a behind-by-N pin is over a year old. Exits non-zero. |
| `[stale]` | behind upstream. A queue item, not an emergency. |
| `[float]` | no pin at all. A standing decision to revisit, not a bug to fix. |
| `[warn]` | could not be queried. Offline or rate-limited — **never** treated as stale. |
| `[ok]` | current. Includes "is upstream HEAD but upstream is unmaintained", which is worth knowing and is not fixed by bumping. |

## 2. Triage — order matters

1. **`[ALERT]` first.** A dead ref means the rebuild is already broken; fix before anything else.
2. **Security-driven.** Cross-check with `/container-hygiene` for image CVEs and any advisory you were sent. A CVE in a network-facing component (mythic_nginx, the portal, Cowrie) outranks everything below.
3. **Kali-compatibility.** Kali rolls; a Python or Node major bump can strand a venv. The `ptai` pin is the worked example — releases before 1.2.1 cap at Python <3.14, so a Kali python bump broke it and the fix was to move *forward*. Check `requires_python` in the report against the box's `python3 --version`.
4. **Plain staleness.** Everything else. Batch these into a maintenance window, still one at a time.

**Do not bump `NPM_PIN`.** It is deliberately held below latest for node 22 compatibility; raising it reintroduces a warning on every npx MCP launch. See the node-toolchain note.

## 3. Before you touch anything

```bash
~/stack-cron/backup.sh                      # or the engagement-backup agent
~/pi5-stack/tools/stack-drift.sh            # start from a known-clean baseline
```
If drift is non-zero, resolve that first — you cannot tell a bump's breakage from
pre-existing divergence.

## 4. Bump one pin

Editing `versions.env` only changes what a **rebuild** produces. The live box keeps
running the old version until you update it too. Do both, or the next `stack-drift`
run will be comparing against a lie.

**git-ref MCP servers** (`HEXSTRIKE_REF`, `KALI_MCP_REF`, `WSTG_REF`, `SLIVER_MCP_REF`, `MYTHIC_MCP_REF`, `CAIDO_MCP_REF`, `EVILGINX_COMMIT`)
```bash
# 1. read what you are adopting — 588 commits is a code review, not a version bump
gh api repos/<OWNER>/<REPO>/compare/<OLD>...<NEW> --jq '.commits[].commit.message' | head -40
# 2. repo pin
sed -i 's/^HEXSTRIKE_REF=.*/HEXSTRIKE_REF="<new>"/' ~/pi5-stack/versions.env
# 3. live clone (fetch + checkout, same as clone_ref; does NOT hard-reset)
git -C ~/hexstrike-ai-community-edition fetch origin && git -C ~/hexstrike-ai-community-edition checkout <new>
~/hexstrike-ai-community-edition/hexstrike-env/bin/pip install -q -r ~/hexstrike-ai-community-edition/requirements.txt
# 4. restart its backend, then prove the MCP still answers
```

**Release-tag builds** (`SLIVER_VERSION`, `MYTHIC_VERSION`, `SURICATA_VERSION`, `ZEEK_VERSION`, `GO_VERSION`, `DOCKER_COMPOSE_VERSION`) — bump `versions.env`, then re-run only that layer: `./bootstrap.sh --layers 50-c2-sliver`. Read the release notes for a schema or config-format change first; Mythic in particular has migrations.

**Container digest** (`COWRIE_DIGEST`) — pull the tag, read back the new digest, pin it explicitly, never leave `:latest`:
```bash
docker pull cowrie/cowrie:latest
docker inspect --format='{{index .RepoDigests 0}}' cowrie/cowrie:latest
# update COWRIE_DIGEST in versions.env AND payload/ap-testbed/hotpot/docker-compose.yml
```

**pip / npm pins** — bump, recreate the venv if the Python major moved, re-run the MCP.

**Tag schemes lie.** `zeek/zeek`'s `releases/latest` can report an LTS *below* our pin, and OISF tags `suricata-X.Y.Z`. The report shows both values and deliberately does not decide which is newer. Confirm on the project's release page before "upgrading" backwards.

## 5. Verify, then decide

```bash
./bootstrap.sh --check                      # 90-verify: claude, npx paths, npm pin, MCPs
~/pi5-stack/tools/stack-drift.sh
```
Then exercise the thing you actually changed — an MCP that loads but returns errors
on every call still counts as broken. If an MCP misbehaves, `/mcp-doctor`. If it
cannot be made to work, **roll back the pin**: reverting one line and re-running one
layer is the whole reason for the one-at-a-time rule.

## 6. Land it

Propagate and commit:
```bash
~/pi5-stack/tools/stack-apply.sh --host vm --apply    # the VM needs it too
```
Then the `pi5-stack-sync` skill: secret-scan gate, conventional commit, push. Record
*why* in the commit — a pin held back deliberately is indistinguishable from a
forgotten one six months later, and that ambiguity is what this skill exists to
prevent. If you decide NOT to bump something, say so in `freshness.conf` as a `#`
note on that line; the note is printed with every future report.

## Floating dependencies

`@burtthecoder/mcp-virustotal` and `@playwright/mcp` are launched with `npx -y`,
resolving to whatever is newest at spawn time — no pin, no review, no rollback, in a
repo whose entire premise is reproducibility. Pinning them means writing an exact
version into `payload/claude.json.tmpl` and accepting responsibility for bumping it.
It is a real trade-off: the virustotal MCP's tool names changed once already and
silently broke nine agents. Decide deliberately; the report will keep listing them
until you do.
