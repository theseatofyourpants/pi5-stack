#!/usr/bin/env bash
# Headless runner for a scheduled operator agent (stack-status / triage-alerts).
# Mirrors the proven ap-testbed/trigger-scan.sh invocation: absolute claude bin,
# restored PATH, --dangerously-skip-permissions (unattended = no human to approve),
# stream-json piped through the readable filter, per-run + latest log.
#
# Usage: run-agent.sh <subagent_type> <timeout_sec> <task line>
set -uo pipefail

AGENT="${1:?agent name required}"
TMO="${2:?timeout seconds required}"
TASK="${3:?task line required}"

# systemd gives a minimal PATH; restore the user tool dirs so `claude` and any
# MCP-spawned tools resolve. HOME comes from the unit (User=tsoyp).
export HOME="${HOME:-/home/tsoyp}"
export PATH="$HOME/.local/bin:$HOME/go/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
CLAUDE_BIN="$HOME/.local/bin/claude"
[ -x "$CLAUDE_BIN" ] || CLAUDE_BIN="$(command -v claude || echo claude)"

BASE="$HOME/stack-cron"; LOGDIR="$BASE/logs"; mkdir -p "$LOGDIR"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGDIR/${AGENT}-${TS}.log"
FILTER="$HOME/ap-testbed/lib/stream-filter.py"

PROMPT="You are running UNATTENDED as a scheduled systemd job on the Pi 5 operator \
stack. Use the Agent tool to launch the ${AGENT} agent (subagent_type: ${AGENT}). \
${TASK} Assume sensible defaults, never ask questions, and finish non-interactively."

echo "=== ${AGENT} scheduled run @ ${TS} ===" > "$LOG"

rc=0
if [ -f "$FILTER" ]; then
  timeout "$TMO" "$CLAUDE_BIN" -p --dangerously-skip-permissions \
    --output-format stream-json --verbose "$PROMPT" \
    2>>"$LOG" | python3 "$FILTER" >> "$LOG"
  rc=${PIPESTATUS[0]}
else
  timeout "$TMO" "$CLAUDE_BIN" -p --dangerously-skip-permissions "$PROMPT" >> "$LOG" 2>&1
  rc=$?
fi

echo "=== exit ${rc} @ $(date +%H:%M:%S) ===" >> "$LOG"
ln -sfn "$LOG" "$LOGDIR/${AGENT}-latest.log"
# retention: keep last 20 per-agent logs
ls -1t "$LOGDIR/${AGENT}-"2*.log 2>/dev/null | tail -n +21 | xargs -r rm -f
exit "$rc"
