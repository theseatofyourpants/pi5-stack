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
  # STACK_ROOT first: it contains /home/tsoyp, so rewriting the home would otherwise
  # mangle a unit that ExecStarts a tool out of the repo (e.g. stack-drift).
  sed -e "s#/home/tsoyp/pi5-stack#$STACK_ROOT#g" \
      -e "s#/home/tsoyp#$HOME#g" -e "s#User=tsoyp#User=$U#g" \
      -e "s#Group=tsoyp#Group=$G#g" -e "s#tsoyp:tsoyp#$U:$G#g" "$1" \
    | as_root tee "/etc/systemd/system/$(basename "$1")" >/dev/null
}
install_script(){ # $1 = payload script, $2 = dest dir
  mkdir -p "$2"
  sed -e "s#/home/tsoyp#$HOME#g" -e "s#tsoyp:tsoyp#$U:$G#g" "$1" > "$2/$(basename "$1")"
  chmod +x "$2/$(basename "$1")"
}

# 1. stack-cron scripts + logs dir.
# Glob, not a hand-kept list: this used to name run-agent.sh and backup.sh
# explicitly while installing the UNITS by glob, so cert-watch and stack-drift
# arrived as services pointing at scripts that were never copied.
log "installing stack-cron scripts…"
for s in "$STACK_ROOT"/payload/stack-cron/*.sh; do install_script "$s" "$HOME/stack-cron"; done
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

# 4. enable timers — derived from what is actually in payload, so adding a timer
# there is enough to get it scheduled. The only hand-kept list is the exception
# set: those spawn headless `claude`, which would fail before Claude Code is authed
# on a fresh box, so they are ARMED for their schedule but not started now.
ARM_ONLY=(stack-status.timer triage-alerts.timer)
START_NOW=(); ARMED=()
for t in "$STACK_ROOT"/payload/stack-cron/systemd/*.timer \
         "$STACK_ROOT"/payload/stack-resilience/*.timer; do
  [ -e "$t" ] || continue
  n="$(basename "$t")"
  if printf '%s\n' "${ARM_ONLY[@]}" | grep -qx "$n"; then ARMED+=("$n"); else START_NOW+=("$n"); fi
done
[ ${#START_NOW[@]} -gt 0 ] && as_root systemctl enable --now "${START_NOW[@]}"
[ ${#ARMED[@]} -gt 0 ]     && as_root systemctl enable "${ARMED[@]}"
ok "scheduled jobs installed (live: ${START_NOW[*]:-none}; armed: ${ARMED[*]:-none})"

verify "run-agent.sh present"       test -x "$HOME/stack-cron/run-agent.sh"
verify "backup.sh present"          test -x "$HOME/stack-cron/backup.sh"
verify "cert-watch.sh present"      test -x "$HOME/stack-cron/cert-watch.sh"
verify "drift detector present"     test -x "$STACK_ROOT/tools/stack-drift.sh"
# Catch the class of bug this layer just had: a unit whose ExecStart does not exist.
verify "no unit points at a missing script" bash -c '
  bad=0
  for u in /etc/systemd/system/{stack-,cert-,triage-}*.service; do
    [ -e "$u" ] || continue
    x="$(awk -F= "/^ExecStart=/{print \$2}" "$u" | awk "{print \$1}")"
    [ -n "$x" ] && [ ! -x "$x" ] && { echo "  !! $(basename "$u") -> missing $x"; bad=1; }
  done
  [ $bad -eq 0 ]'
verify "cert-watch timer enabled"   systemctl is-enabled --quiet cert-watch.timer
verify "drift timer enabled"        systemctl is-enabled --quiet stack-drift.timer
verify "watchdog timer enabled"     systemctl is-enabled --quiet stack-watchdog.timer
verify "backup timer enabled"       systemctl is-enabled --quiet stack-backup.timer
ok "70-automation done"
