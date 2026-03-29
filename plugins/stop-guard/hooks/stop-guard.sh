#!/usr/bin/env bash
set -euo pipefail

# stop-guard.sh — Claude Code Stop hook.
#
# Reads JSON from stdin (fields: session_id, last_assistant_message,
# transcript_path, etc.). Evaluates task completion via Gemini CLI.
# Blocks the stop (exit 2) if the task appears incomplete.
#
# Activation: only fires when the session transcript contains
# <!-- stop-guard:active -->. Skills opt in by outputting that marker.
#
# Configuration: reads $HOME/.config/stop-guard/config.json if present,
# otherwise uses sensible defaults.

log()  { echo "$*" >&2; }
die()  { log "error: $*"; exit 0; }  # fail-open: errors allow stop

# Persistent file log
_LOG_DIR="$HOME/.claude/logs"
mkdir -p "$_LOG_DIR" 2>/dev/null || true
_LOG_FILE="$_LOG_DIR/stop-guard.log"
if [ -f "$_LOG_FILE" ] && [ "$(wc -c < "$_LOG_FILE")" -gt 65536 ]; then
  tail -c 32768 "$_LOG_FILE" > "$_LOG_FILE.tmp" && mv "$_LOG_FILE.tmp" "$_LOG_FILE"
fi
dbg() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$_LOG_FILE" 2>/dev/null || true; }

dbg "=== Stop hook fired (pid=$$) ==="

command -v jq >/dev/null 2>&1 || die "jq is required but not found in PATH"
command -v gemini >/dev/null 2>&1 || die "gemini CLI is required but not found in PATH"

# ---------------------------------------------------------------------------
# 1. Parse stdin JSON
# ---------------------------------------------------------------------------
if ! IFS= read -r -t 5 INPUT; then
  [ -n "${INPUT:-}" ] || die "timed out or received no data on stdin"
fi
dbg "input received (${#INPUT} bytes)"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')

# ---------------------------------------------------------------------------
# 2. Activation check — transcript must contain marker
# ---------------------------------------------------------------------------
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  dbg "no transcript file, allowing stop"
  exit 0
fi

if ! grep -q '<!-- stop-guard:active -->' "$TRANSCRIPT" 2>/dev/null; then
  dbg "activation marker not found in transcript, allowing stop"
  exit 0
fi
dbg "activation marker found"

# ---------------------------------------------------------------------------
# 3. Load config (optional file, defaults inline)
# ---------------------------------------------------------------------------
CONFIG="$HOME/.config/stop-guard/config.json"
MAX_CONT=$(jq -r '.max_continuations // 3' "$CONFIG" 2>/dev/null || echo 3)
MODEL=$(jq -r '.model // "gemini-3-flash-preview"' "$CONFIG" 2>/dev/null || echo "gemini-3-flash-preview")

# ---------------------------------------------------------------------------
# 4. Counter check (loop prevention)
# ---------------------------------------------------------------------------
COUNTER_DIR="$HOME/.cache/stop-guard"
mkdir -p "$COUNTER_DIR" 2>/dev/null || true
COUNTER_FILE="$COUNTER_DIR/${SESSION_ID}.count"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)

if [ "$COUNT" -ge "$MAX_CONT" ]; then
  dbg "max continuations ($MAX_CONT) reached, allowing stop"
  rm -f "$COUNTER_FILE"
  exit 0
fi
dbg "continuation $COUNT/$MAX_CONT"

# ---------------------------------------------------------------------------
# 5. Build evaluator context
# ---------------------------------------------------------------------------
TASK_CONTEXT=$(grep -o '<!-- stop-guard:context .* -->' "$TRANSCRIPT" \
  | tail -1 | sed 's/<!-- stop-guard:context //;s/ -->//' 2>/dev/null || echo "")

TRANSCRIPT_TAIL=$(tail -100 "$TRANSCRIPT" 2>/dev/null || echo "")

# ---------------------------------------------------------------------------
# 6. Call Gemini CLI for evaluation
# ---------------------------------------------------------------------------
EVAL_PROMPT=$(cat <<'PROMPT_EOF'
You are a task-completion evaluator for an AI coding assistant. Given the
conversation transcript tail and the assistant's final message, determine
whether the assistant's task is genuinely complete.

Signs of INCOMPLETE work:
- The original request was only partially addressed
- Errors occurred that were not resolved
- The assistant said it would do something but did not finish
- Tests should have been run but were not
- Files were mentioned but not created or modified

Signs of COMPLETE work:
- All requested items were addressed with specifics
- Verification steps (tests, builds) passed
- The assistant provided a clear summary of what was done

Signs the task NEEDS HUMAN input:
- The assistant asked a question and is waiting for an answer
- A decision is needed that only the user can make
- The assistant explicitly requested user feedback

Respond with ONLY a valid JSON object (no markdown fences, no explanation):
{"verdict": "complete", "reason": "one-line explanation"}

Where verdict is exactly one of: "complete", "incomplete", "needs_human"
PROMPT_EOF
)

# Append the actual context
EVAL_PROMPT="$EVAL_PROMPT

<transcript_tail>
$TRANSCRIPT_TAIL
</transcript_tail>

<final_message>
$LAST_MSG
</final_message>"

if [ -n "$TASK_CONTEXT" ]; then
  EVAL_PROMPT="$EVAL_PROMPT

<task_context>
$TASK_CONTEXT
</task_context>"
fi

dbg "calling gemini (model=$MODEL)..."
RAW=$(echo "$EVAL_PROMPT" | timeout 12 gemini -p - -o json -y -m "$MODEL" 2>/dev/null) || {
  dbg "gemini call failed or timed out, allowing stop"
  exit 0
}
dbg "gemini response received (${#RAW} bytes)"

# ---------------------------------------------------------------------------
# 7. Parse verdict
# ---------------------------------------------------------------------------
# gemini -o json wraps output in {"session_id": "...", "response": "..."}
INNER=$(echo "$RAW" | jq -r '.response // ""' 2>/dev/null) || {
  dbg "failed to parse gemini envelope, allowing stop"
  exit 0
}

VERDICT=$(echo "$INNER" | jq -r '.verdict // "complete"' 2>/dev/null) || VERDICT="complete"
REASON=$(echo "$INNER" | jq -r '.reason // ""' 2>/dev/null) || REASON=""

dbg "verdict=$VERDICT reason=$REASON"

if [ "$VERDICT" = "incomplete" ]; then
  echo $((COUNT + 1)) > "$COUNTER_FILE"
  dbg "blocking stop (continuation $((COUNT + 1))/$MAX_CONT)"
  jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}'
  exit 2
fi

dbg "allowing stop (verdict=$VERDICT)"
exit 0
