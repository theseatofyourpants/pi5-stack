#!/usr/bin/env bash
# layers/60-sensors.sh — Suricata (from source), Zeek (OBS repo), bettercap. [opt-in,
# slow — Suricata compiles from source because the Kali arm64 apt pkg is unusable]
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"

log "Suricata — building from source (Kali arm64 apt pkg has an unusable DPDK dep)…"
bash "$STACK_ROOT/payload/scripts/build-sensors.sh" || warn "suricata build had issues — see output above"

log "Zeek — installing from the OpenSUSE OBS repo (NOT Kali apt: broken libc6 dep)…"
bash "$STACK_ROOT/payload/scripts/zeek-install.sh" || warn "zeek install had issues"

log "bettercap (apt)…"
as_root apt-get install -y bettercap || warn "bettercap install failed"

# Suricata ET Open ruleset (~45k rules). suricata-update isn't bundled with a source
# build; install it (independent Python tool, from Kali apt) so the rules get pulled.
need_cmd suricata-update || as_root apt-get install -y suricata-update || warn "suricata-update install failed"
if need_cmd suricata-update; then as_root suricata-update || warn "suricata-update failed"; fi

verify "suricata" bash -lc 'command -v suricata || test -x /usr/local/bin/suricata'
verify "zeek"     bash -lc 'test -x /opt/zeek/bin/zeek || command -v zeek'
verify "bettercap" command -v bettercap
ok "60-sensors done. Start manually per the Reboot-Runbook (suricata -D / zeekctl deploy)."
