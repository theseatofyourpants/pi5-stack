#!/usr/bin/env bash
# layers/55-ctf-tools.sh — CTF / badge-hacking toolchain for the ctf-* agents & skills
# (ctf-crypto, ctf-rev, ctf-forensics, fw-triage, rf-decode, hw-bench, andxor-ctf).
# Opt-in. apt packages + a user-space ztools build. See docs/ctf-references/.
# NOTE: pulls Ghidra (a JDK + a few hundred MB) — the slow part of this layer.
set -euo pipefail
source "$STACK_ROOT/lib/common.sh"

log "apt: CTF toolchain (RE / crypto / stego / RF / serial)…"
as_root apt-get update -qq
as_root apt-get install -y \
  frotz multimon-ng steghide sox foremost picocom \
  rtl-sdr rtl-433 sigrok-cli ghidra \
  python3-pycryptodome python3-gmpy2 python3-pwntools \
  || warn "some CTF apt packages failed — see output above"

log "building ztools (infodump/txd — not apt-installable)…"
bash "$STACK_ROOT/payload/scripts/install-ztools.sh" || warn "ztools build had issues — see output above"

verify "dfrotz present"   bash -lc 'command -v dfrotz'
verify "infodump present" bash -lc 'command -v infodump'
verify "multimon-ng"      bash -lc 'command -v multimon-ng'
verify "ghidra present"   bash -lc 'command -v ghidra'
# Debian ships pycryptodome under the 'Cryptodome' namespace, not 'Crypto':
verify "pycryptodome"     python3 -c 'import Cryptodome'
ok "55-ctf-tools done — solve scripts import from 'Cryptodome' (not 'Crypto') on this box"
