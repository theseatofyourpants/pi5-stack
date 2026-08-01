#!/usr/bin/env bash
# layers/70-automation.sh — timer-driven automation & self-healing:
#   * stack-cron: scheduled /stack-status (boot+daily), /triage-alerts (6h),
#     and a deterministic redacted nightly backup.
#   * stack-watchdog: heals Sliver/Mythic every ~3min + writes backends.json
#     for the admin dashboard / e-ink panel.
# Opt-in (spawns headless `claude` jobs that cost tokens; wants C2 present).
# Idempotent: re-running just re-installs and re-enables.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"

U="$(id -un)"; G="$(id -gn)"

# Install a systemd unit from payload, templating the tsoyp/home defaults to the
# actual install user/HOME (the rest of the repo is tsoyp-centric).
install_unit(){ # $1 = payload unit path
  sed -e "s#/home/tsoyp#$HOME#g" -e "s#User=tsoyp#User=$U#g" \
      -e "s#Group=tsoyp#Group=$G#g" -e "s#tsoyp:tsoyp#$U:$G#g" "$1" \
    | as_root tee "/etc/systemd/system/$(basename "$1")" >/dev/null
}
install_script(){ # $1 = payload script, $2 = dest dir
  mkdir -p "$2"
  sed -e "s#/home/tsoyp#$HOME#g" -e "s#tsoyp:tsoyp#$U:$G#g" "$1" > "$2/$(basename "$1")"
  chmod +x "$2/$(basename "$1")"
}

# 1. stack-cron scripts + logs dir
log "installing stack-cron scripts…"
install_script "$STACK_ROOT/payload/stack-cron/run-agent.sh" "$HOME/stack-cron"
install_script "$STACK_ROOT/payload/stack-cron/backup.sh"     "$HOME/stack-cron"
mkdir -p "$HOME/stack-cron/logs" "$HOME/backups" "$HOME/ap-testbed/state"

# 2. stack-watchdog script (resilience — pairs with sliver.service from 50-c2-sliver)
log "installing stack-watchdog…"
install_script "$STACK_ROOT/payload/stack-resilience/stack-watchdog.sh" "$HOME/stack-resilience"

# 3. systemd units (templated)
for u in "$STACK_ROOT"/payload/stack-cron/systemd/*.service \
         "$STACK_ROOT"/payload/stack-cron/systemd/*.timer \
         "$STACK_ROOT"/payload/stack-resilience/stack-watchdog.service \
         "$STACK_ROOT"/payload/stack-resilience/stack-watchdog.timer; do
  install_unit "$u"
done
as_root systemctl daemon-reload

# 4. enable timers.
#   watchdog + nightly backup: safe to start now (heal / free local tar).
#   status + triage spawn headless `claude` — only ARM them (they'd fail before
#   Claude Code is authed on a fresh box; they fire on schedule / next boot).
as_root systemctl enable --now stack-watchdog.timer stack-backup.timer
as_root systemctl enable stack-status.timer triage-alerts.timer
ok "scheduled jobs installed (watchdog+backup live; status+triage armed for schedule)"

verify "run-agent.sh present"       test -x "$HOME/stack-cron/run-agent.sh"
verify "backup.sh present"          test -x "$HOME/stack-cron/backup.sh"
verify "watchdog timer enabled"     systemctl is-enabled --quiet stack-watchdog.timer
verify "backup timer enabled"       systemctl is-enabled --quiet stack-backup.timer
ok "70-automation done"
