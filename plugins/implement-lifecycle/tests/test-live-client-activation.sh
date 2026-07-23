#!/bin/bash
# Opt-in live acceptance: exercises actual Claude Code and Codex plugin activation.
set -euo pipefail

if [ "${LIVE_CLIENT_ACCEPTANCE:-}" != "1" ]; then
  echo "Set LIVE_CLIENT_ACCEPTANCE=1 to run live client activation checks." >&2
  exit 2
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
PLUGIN_DIR="$ROOT_DIR/plugins/implement-lifecycle"
PROMPT='Activate the implement-lifecycle implement skill. Do not run commands, delegate, access GitHub, or change files. Read its shared dispatch contract and reply with exactly two lines: CLAUDE_TARGET=implement-code and CODEX_TARGET=$implement-lifecycle:implement-code'

claude_output=$(claude -p --plugin-dir "$PLUGIN_DIR" --permission-mode plan --no-session-persistence --max-budget-usd 0.25 "/implement-lifecycle:implement $PROMPT")
printf '%s\n' "$claude_output" | grep -Fxq 'CLAUDE_TARGET=implement-code'
printf '%s\n' "$claude_output" | grep -Fxq 'CODEX_TARGET=$implement-lifecycle:implement-code'

codex_output=$(codex exec --ephemeral --sandbox read-only -C "$ROOT_DIR" "Use \$implement-lifecycle:implement. $PROMPT")
printf '%s\n' "$codex_output" | grep -Fxq 'CLAUDE_TARGET=implement-code'
printf '%s\n' "$codex_output" | grep -Fxq 'CODEX_TARGET=$implement-lifecycle:implement-code'

echo "PASS: Claude Code and Codex activated the installed plugin skill and consumed its shared dispatch contract."
