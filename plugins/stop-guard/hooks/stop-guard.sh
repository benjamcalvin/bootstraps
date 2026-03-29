#!/usr/bin/env bash
set -euo pipefail

# stop-guard.sh — Claude Code Stop hook.
#
# Reads JSON from stdin (fields: session_id, last_assistant_message,
# transcript_path, etc.). Evaluates task completion via Gemini CLI.
# Blocks the stop via JSON decision if the task appears incomplete.
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

# Find task list file if available
TASK_LIST_FILE=""
if [ -n "${CLAUDE_CODE_TASK_LIST_ID:-}" ]; then
  TASK_LIST_FILE="$HOME/.claude/tasks/${CLAUDE_CODE_TASK_LIST_ID}/tasks.json"
elif [ -d "$HOME/.claude/tasks/$SESSION_ID" ]; then
  TASK_LIST_FILE="$HOME/.claude/tasks/${SESSION_ID}/tasks.json"
fi

# ---------------------------------------------------------------------------
# 6. Call Gemini CLI for evaluation
# ---------------------------------------------------------------------------
read -r -d '' EVAL_PROMPT <<'PROMPT_EOF' || true
# Role

You are a quality gate in an AI coding agent's workflow. You decide whether
the agent (Claude Code) should be allowed to stop or forced to continue.

# How this works

You are called automatically every time Claude Code is about to end its turn.
Your response is a JSON object that Claude Code's hook system parses directly.
The two possible outcomes are:

- {"decision": "block", "reason": "..."} → Claude is BLOCKED from stopping
  and forced to continue. The reason string is shown to Claude as its next
  instruction. Only use this when work is clearly unfinished.
- {} → Claude is allowed to stop. The conversation ends normally.

Err on the side of allowing the stop. Blocking is disruptive — only do it
when there is clear evidence of unfinished work, not just because the
response could theoretically be better.

# What you have access to

You are running in read-only mode. You CAN read files and access GitHub
but you CANNOT modify anything. Use these capabilities to gather context.

**Session transcript**: A JSONL file (path provided below) where each line
is a JSON object representing messages, tool calls, and tool results.
You'll see role:"user" messages, role:"assistant" messages, and
tool_use/tool_result blocks (file edits, bash commands, etc.). Read this
file to understand what was requested and what was done. Start from the
end and work backwards — the most recent activity matters most.

**Task list**: If provided, a JSON file showing Claude's tracked tasks
with their statuses (pending, in_progress, completed). Tasks still marked
as pending or in_progress are strong signals of incomplete work.

**Final message**: Claude's last response text before it tried to stop,
provided inline below for convenience.

# When to block

Return {"decision": "block", "reason": "..."} ONLY when there is concrete
evidence such as:
- The user asked for X and Claude did not do X (not partially — not at all)
- A command or test failed and Claude did not address the failure
- Claude explicitly said "I will now do Y" but never did Y
- An error was thrown that blocks the user's goal and was not resolved

Do NOT block for:
- Minor polish, style, or optimization opportunities
- Missing tests unless the user specifically requested them
- Claude summarizing what it did (that IS completion)
- Claude asking the user a question (allow the stop — user needs to respond)

# When to allow the stop

Return {} (empty JSON object) when:
- The task appears complete
- Claude asked a question and is waiting for user input
- A decision is needed that only the user can make
- There is no clear evidence of unfinished work

# Response format

Respond with ONLY a valid JSON object. No markdown fences, no commentary,
no text before or after.

To block:  {"decision": "block", "reason": "<1-3 sentences: specific, actionable instruction for what Claude should do next>"}
To allow:  {}

The reason is critical when blocking — it becomes Claude's next instruction.
Make it specific and actionable (e.g., "The tests in auth_test.go failed
with 3 errors that were not addressed. Fix the failing assertions before
stopping." not "Work seems incomplete").
PROMPT_EOF

# Append file paths and inline context
EVAL_PROMPT="$EVAL_PROMPT

<transcript_path>
$TRANSCRIPT
</transcript_path>

Read the transcript file above to understand the full session. Start from
the end and work backwards to find what was requested and what was done."

if [ -n "$TASK_LIST_FILE" ] && [ -f "$TASK_LIST_FILE" ]; then
  EVAL_PROMPT="$EVAL_PROMPT

<task_list_path>
$TASK_LIST_FILE
</task_list_path>

Read the task list file above. Any tasks with status 'pending' or
'in_progress' are strong evidence that work is incomplete."
  dbg "task list found: $TASK_LIST_FILE"
fi

EVAL_PROMPT="$EVAL_PROMPT

<final_message>
$LAST_MSG
</final_message>"

if [ -n "$TASK_CONTEXT" ]; then
  EVAL_PROMPT="$EVAL_PROMPT

<task_context>
The skill that activated this guard provided the following context about
what the task is and what the acceptance criteria are:
$TASK_CONTEXT
</task_context>"
fi

dbg "calling gemini (model=$MODEL)..."
# Yolo mode: auto-approve tool calls (file reads, GitHub lookups)
# The prompt instructs read-only behavior; Claude Code's 60s hook timeout is the safety net
RAW=$(echo "$EVAL_PROMPT" | gemini -p - -o json -y -m "$MODEL" 2>/dev/null) || {
  dbg "gemini call failed or timed out, allowing stop"
  exit 0
}
dbg "gemini response received (${#RAW} bytes)"

# ---------------------------------------------------------------------------
# 7. Parse verdict and stats
# ---------------------------------------------------------------------------
# gemini -o json wraps output in {"session_id": "...", "response": "...", "stats": {...}}
INNER=$(echo "$RAW" | jq -r '.response // ""' 2>/dev/null) || {
  dbg "failed to parse gemini envelope, allowing stop"
  exit 0
}

# Extract token usage and latency from stats
INPUT_TOKENS=$(echo "$RAW" | jq -r ".stats.models.\"$MODEL\".tokens.input // 0" 2>/dev/null) || INPUT_TOKENS=0
OUTPUT_TOKENS=$(echo "$RAW" | jq -r ".stats.models.\"$MODEL\".tokens.candidates // 0" 2>/dev/null) || OUTPUT_TOKENS=0
LATENCY_MS=$(echo "$RAW" | jq -r ".stats.models.\"$MODEL\".api.totalLatencyMs // 0" 2>/dev/null) || LATENCY_MS=0
dbg "tokens: in=$INPUT_TOKENS out=$OUTPUT_TOKENS latency=${LATENCY_MS}ms"

DECISION=$(echo "$INNER" | jq -r '.decision // ""' 2>/dev/null) || DECISION=""
REASON=$(echo "$INNER" | jq -r '.reason // ""' 2>/dev/null) || REASON=""

dbg "decision=$DECISION"
dbg "reason=$REASON"

if [ "$DECISION" = "block" ]; then
  echo $((COUNT + 1)) > "$COUNTER_FILE"
  dbg "blocking stop (continuation $((COUNT + 1))/$MAX_CONT)"
  # Pass through the stop control JSON directly
  echo "$INNER"
  exit 0
fi

dbg "allowing stop"
exit 0
