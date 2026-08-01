---
name: pi5-stack-sync
description: Keep the ~/pi5-stack rebuild repo current — reflect stack changes into the right layer script / payload template / versions.env pin, mirror the pi_design vault into docs/, run a secret-scan gate, then commit (conventional-commit style) and push to the private GitHub remote. Use after any change that should survive a fresh-box rebuild. Pairs with vault-sync.
---

# pi5-stack-sync — update, commit, and push the rebuild repo

Repo: `~/pi5-stack` (branch `main`, remote `origin` = private GitHub `theseatofyourpants/pi5-stack`, `gh` authenticated). Rebuilds the whole stack on a fresh Kali arm64. Structure: `bootstrap.sh` (conductor), `lib/`, `layers/00..90`, `payload/` (scrubbed configs + scripts), `docs/` (mirror of `~/pi_design`), `versions.env` (pinned commits), `secrets.example.env`. Real secrets live in git-ignored `secrets.env` — **never** committed.

## Procedure
1. **Locate the change → the right home.** Map what changed on the live box to the repo:
   - New/changed **service** → the matching `layers/NN-*.sh` (make it idempotent, end in a `verify()`), and a systemd unit under `payload/` if applicable.
   - New/changed **MCP or tool version** → bump the pin in `versions.env`.
   - New **config** (claude.json entry, unit file, script) → the scrubbed copy under `payload/` with real secrets replaced by `{{PLACEHOLDER}}` tokens.
   - **Docs** → edit `~/pi_design` via `vault-sync`, don't hand-edit `docs/`.
2. **Mirror the vault into docs/.** `rsync -a --delete ~/pi_design/ ~/pi5-stack/docs/` then confirm `diff -rq ~/pi_design ~/pi5-stack/docs` is clean.
3. **SECRET-SCAN GATE (mandatory before commit).** Abort if anything sensitive is staged:
   ```bash
   cd ~/pi5-stack
   git add -A
   # fail the commit if a real secret slipped in (keys, passwords, tokens, the ignored secrets file)
   git diff --cached | grep -nEi 'VIRUSTOTAL_API_KEY"?\s*[:=]\s*"?[A-Za-z0-9]{20}|GREYNOISE_API_KEY"?\s*[:=]\s*"?[A-Za-z0-9]{20}|MYTHIC_PASSWORD|gh[pous]_[A-Za-z0-9]{20}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' \
     && { echo "ABORT: secret detected — unstage and replace with {{PLACEHOLDER}}"; exit 1; }
   git ls-files --cached | grep -qx 'secrets.env' && { echo "ABORT: secrets.env is tracked"; exit 1; }
   ```
   Payload configs must use `{{PLACEHOLDER}}`, not live values. If the gate trips, fix it before proceeding — a leaked key in git history is the worst outcome here.
3b. **Sanity-check scripts** you touched: `bash -n layers/*.sh lib/*.sh` (syntax) before committing.
4. **Commit (conventional-commit style).** Match the repo's history: `feat(scope): …`, `docs(scope): …`, `fix(scope): …`. One logical change per commit; describe what a fresh-box rebuild now gets.
   ```bash
   git commit -m "feat(<layer>): <what changed and why it matters for rebuild>

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
   ```
5. **Push** (only when the operator wants it pushed — pushing publishes to GitHub):
   ```bash
   git push origin main && git log --oneline -1
   ```

## Notes
- Commit/push only on the operator's go — pushing is an outward-facing publish to the private remote.
- The repo is edited **in place**; `.claude/settings.json` there sets `worktree.bgIsolation=none`. If a guard blocks a write mid-session, write to a scratch path and `mv` into the repo.
- Layers are validated syntactically but generally NOT run on this live box (they re-clone/reset live repos — they're for fresh Kali only). Note that when relevant.
