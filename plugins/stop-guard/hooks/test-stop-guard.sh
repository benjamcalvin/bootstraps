#!/usr/bin/env bash
set -euo pipefail

# test-stop-guard.sh — Test the stop-guard evaluator against a real session.
#
# Usage:
#   ./test-stop-guard.sh <transcript_path>
#   ./test-stop-guard.sh <transcript_path> [--verbose]
#
# Examples:
#   # Test against a specific session transcript
#   ./test-stop-guard.sh ~/.claude/projects/-Users-ben-code-hcc-app/00b69ee4.jsonl
#
#   # List recent sessions for a project and pick one
#   ls -lt ~/.claude/projects/-Users-ben-code-myproject/*.jsonl | head -5

usage() {
  echo "Usage: $0 <transcript_path> [--verbose]"
  echo ""
  echo "Test the stop-guard evaluator against a Claude Code session transcript."
  echo ""
  echo "Arguments:"
  echo "  transcript_path   Path to a .jsonl session transcript"
  echo "  --verbose         Show the full prompt sent to gemini"
  exit 1
}

TRANSCRIPT="${1:-}"
VERBOSE=false
[ "${2:-}" = "--verbose" ] && VERBOSE=true

[ -z "$TRANSCRIPT" ] && usage
[ ! -f "$TRANSCRIPT" ] && { echo "error: file not found: $TRANSCRIPT"; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "error: jq is required"; exit 1; }
command -v gemini >/dev/null 2>&1 || { echo "error: gemini CLI is required"; exit 1; }

# ---------------------------------------------------------------------------
# Extract session info
# ---------------------------------------------------------------------------
SESSION_ID=$(basename "$TRANSCRIPT" .jsonl)
LINES=$(wc -l < "$TRANSCRIPT" | tr -d ' ')

# Extract the last assistant message from the transcript
LAST_MSG=$(grep '"role":"assistant"' "$TRANSCRIPT" | tail -1 | jq -r '.content // .message // ""' 2>/dev/null || echo "(could not extract)")

echo "=== Stop Guard Test ==="
echo "Transcript:  $TRANSCRIPT"
echo "Session ID:  $SESSION_ID"
echo "Lines:       $LINES"
echo "Last msg:    $(echo "$LAST_MSG" | head -c 200)..."
echo ""

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------
CONFIG="$HOME/.config/stop-guard/config.json"
MODEL=$(jq -r '.model // "gemini-3-flash-preview"' "$CONFIG" 2>/dev/null || echo "gemini-3-flash-preview")
echo "Model:       $MODEL"

# ---------------------------------------------------------------------------
# Check for task list
# ---------------------------------------------------------------------------
TASK_LIST_FILE=""
if [ -n "${CLAUDE_CODE_TASK_LIST_ID:-}" ]; then
  TASK_LIST_FILE="$HOME/.claude/tasks/${CLAUDE_CODE_TASK_LIST_ID}/tasks.json"
elif [ -d "$HOME/.claude/tasks/$SESSION_ID" ]; then
  TASK_LIST_FILE="$HOME/.claude/tasks/${SESSION_ID}/tasks.json"
fi

if [ -n "$TASK_LIST_FILE" ] && [ -f "$TASK_LIST_FILE" ]; then
  echo "Task list:   $TASK_LIST_FILE"
else
  echo "Task list:   (none found)"
  TASK_LIST_FILE=""
fi

# ---------------------------------------------------------------------------
# Check activation marker
# ---------------------------------------------------------------------------
if grep -q '<!-- stop-guard:active -->' "$TRANSCRIPT" 2>/dev/null; then
  echo "Activation:  marker found"
else
  echo "Activation:  marker NOT found (hook would skip this session)"
fi

# Extract task context if present
TASK_CONTEXT=$(grep -o '<!-- stop-guard:context .* -->' "$TRANSCRIPT" \
  | tail -1 | sed 's/<!-- stop-guard:context //;s/ -->//' 2>/dev/null || echo "")
if [ -n "$TASK_CONTEXT" ]; then
  echo "Context:     $TASK_CONTEXT"
fi

echo ""
echo "--- Calling Gemini ($MODEL) ---"
echo ""

# ---------------------------------------------------------------------------
# Build the same prompt the hook would use
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

EVAL_PROMPT="$EVAL_PROMPT

<transcript_path>
$TRANSCRIPT
</transcript_path>

Read the transcript file above to understand the full session. Start from
the end and work backwards to find what was requested and what was done."

if [ -n "$TASK_LIST_FILE" ]; then
  EVAL_PROMPT="$EVAL_PROMPT

<task_list_path>
$TASK_LIST_FILE
</task_list_path>

Read the task list file above. Any tasks with status 'pending' or
'in_progress' are strong evidence that work is incomplete."
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

if [ "$VERBOSE" = true ]; then
  echo "=== PROMPT ==="
  echo "$EVAL_PROMPT"
  echo "=== END PROMPT ==="
  echo ""
fi

# ---------------------------------------------------------------------------
# Call Gemini
# ---------------------------------------------------------------------------
START_TIME=$(date +%s)
RAW=$(echo "$EVAL_PROMPT" | gemini -p - -o json -y -m "$MODEL" 2>/dev/null) || {
  echo "ERROR: gemini call failed"
  exit 1
}
END_TIME=$(date +%s)

# ---------------------------------------------------------------------------
# Parse and display results
# ---------------------------------------------------------------------------
INNER=$(echo "$RAW" | jq -r '.response // ""' 2>/dev/null) || { echo "ERROR: failed to parse response"; exit 1; }

INPUT_TOKENS=$(echo "$RAW" | jq -r ".stats.models.\"$MODEL\".tokens.input // 0" 2>/dev/null) || INPUT_TOKENS=0
OUTPUT_TOKENS=$(echo "$RAW" | jq -r ".stats.models.\"$MODEL\".tokens.candidates // 0" 2>/dev/null) || OUTPUT_TOKENS=0
LATENCY_MS=$(echo "$RAW" | jq -r ".stats.models.\"$MODEL\".api.totalLatencyMs // 0" 2>/dev/null) || LATENCY_MS=0

# Extract decision — try multiple strategies
DECISION=""
REASON=""
PARSE_METHOD=""

# Strategy 1: direct jq parse
if DECISION=$(echo "$INNER" | jq -r '.decision // empty' 2>/dev/null) && [ -n "$DECISION" ]; then
  REASON=$(echo "$INNER" | jq -r '.reason // ""' 2>/dev/null) || REASON=""
  PARSE_METHOD="direct jq"
else
  DECISION=""
  # Strategy 2: extract JSON from mixed content
  JSON_BLOCK=""
  while IFS= read -r candidate; do
    if echo "$candidate" | jq -e '.decision' >/dev/null 2>&1; then
      JSON_BLOCK="$candidate"
    fi
  done < <(echo "$INNER" | grep -o '{[^{}]*}' 2>/dev/null || true)

  if [ -n "$JSON_BLOCK" ]; then
    DECISION=$(echo "$JSON_BLOCK" | jq -r '.decision // ""' 2>/dev/null) || DECISION=""
    REASON=$(echo "$JSON_BLOCK" | jq -r '.reason // ""' 2>/dev/null) || REASON=""
    PARSE_METHOD="grep+jq extraction"
  else
    # Strategy 3: legacy verdict format
    VERDICT=$(echo "$INNER" | jq -r '.verdict // empty' 2>/dev/null) || VERDICT=""
    if [ "$VERDICT" = "incomplete" ]; then
      DECISION="block"
      REASON=$(echo "$INNER" | jq -r '.reason // ""' 2>/dev/null) || REASON=""
      PARSE_METHOD="legacy verdict"
    else
      DECISION="(allow)"
      REASON="(none)"
      PARSE_METHOD="no decision found"
    fi
  fi
fi

echo "=== Result ==="
echo ""
echo "Decision:    $DECISION"
echo "Reason:      $REASON"
echo "Parsed via:  $PARSE_METHOD"
echo ""
echo "--- Stats ---"
echo "Tokens in:   $INPUT_TOKENS"
echo "Tokens out:  $OUTPUT_TOKENS"
echo "Latency:     ${LATENCY_MS}ms"
echo "Wall time:   $((END_TIME - START_TIME))s"
echo ""
echo "--- Raw Response ---"
echo "$INNER"
