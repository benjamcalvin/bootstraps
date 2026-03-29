# stop-guard

A Claude Code Stop hook that uses Gemini CLI as an independent evaluator to determine whether a task is truly complete before allowing Claude to stop. When work is incomplete, it blocks the stop and tells Claude what to finish.

## How it works

```
Claude tries to stop
        ↓
Stop hook fires
        ↓
Check transcript for activation marker  →  not found → allow stop
        ↓ found
Check continuation counter  →  max reached → allow stop
        ↓ under limit
Check task list  →  all tasks completed → allow stop (fast-path)
        ↓ has pending/in-progress tasks (or no task list)
Call Gemini CLI to evaluate completion
        ↓
Gemini reads transcript + task list + final message
        ↓
┌─────────────┬──────────────────────────────────┐
│ {} (allow)  │ {"decision":"block","reason":"…"} │
│ Claude stops│ Claude continues with reason      │
└─────────────┴──────────────────────────────────┘
```

## Install

```
/plugin install stop-guard@bootstraps
```

### Prerequisites

- [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`npm install -g @google/gemini-cli`)
- [jq](https://jqlang.github.io/jq/) (`brew install jq`)

## Activation

The hook is **opt-in per session**. It only evaluates when the session transcript contains an activation marker. Any skill, hook, or prompt that wants stop-guard protection includes this text in its output:

```
<!-- stop-guard:active -->
```

You can type this directly in a Claude Code conversation to activate it, or have a skill output it automatically.

### Optional: Task context

Provide structured context for the evaluator to improve its judgment:

```
<!-- stop-guard:context {"task": "implement user auth", "criteria": ["tests pass", "PR created", "no security warnings"]} -->
```

The evaluator uses this to understand what "done" means for the current task.

### Why opt-in?

- Avoids unnecessary Gemini API calls on casual conversations
- Each session has its own transcript — parallel sessions don't interfere
- Skills can selectively enable it for complex workflows

## Configuration

Create `~/.config/stop-guard/config.json` (optional — sensible defaults are used if absent):

```json
{
  "max_continuations": 5,
  "model": "gemini-3-flash-preview"
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `max_continuations` | `5` | Maximum times the hook will block a stop per session before giving up |
| `model` | `gemini-3-flash-preview` | Gemini model for evaluation |

## Safety mechanisms

| Mechanism | Description |
|-----------|-------------|
| **Activation marker** | Hook is inert unless `<!-- stop-guard:active -->` appears in the transcript |
| **Continuation counter** | Hard cap (default 5) per session — prevents infinite loops |
| **Fail-open** | Hard errors (Gemini timeout, missing tools, parse failure) allow the stop. Empty Gemini responses (≤5 output tokens) are treated as evaluation failures and block within the continuation budget |
| **60s timeout** | Claude Code kills the hook process if it exceeds the timeout |

## What the evaluator sees

The Gemini evaluator receives:

1. **Transcript path** — the full session JSONL file, which it reads directly to understand what was requested and done
2. **Task list** — Claude's tracked tasks (`~/.claude/tasks/`), if available. Pending/in-progress tasks are strong incompleteness signals
3. **Final message** — Claude's last response before attempting to stop
4. **Task context** — optional structured context from the activation marker

The evaluator runs in yolo mode (`-y`) with auto-approved tool calls so it can read files and access GitHub. It returns a JSON decision that Claude Code's hook system parses directly.

## Logs

All hook activity is logged to `~/.claude/logs/stop-guard.log`:

```
[2026-03-29T14:33:20Z] === Stop hook fired (pid=12232 session=8e82687e-3d55-4e4f-a22f-1815843dc8ef) ===
[2026-03-29T14:33:20Z] input received (335 bytes)
[2026-03-29T14:33:20Z] activation marker found
[2026-03-29T14:33:20Z] continuation 0/5
[2026-03-29T14:33:20Z] calling gemini (model=gemini-3-flash-preview, prompt_bytes=12847)...
[2026-03-29T14:33:50Z] gemini response received (1024 bytes)
[2026-03-29T14:33:50Z] tokens: in=33581 out=290 latency=58702ms
[2026-03-29T14:33:50Z] decision=block
[2026-03-29T14:33:50Z] reason=4 pending tasks not completed
[2026-03-29T14:33:50Z] blocking stop (continuation 1/5)
```

The log includes token usage and API latency for each evaluation. Log file auto-rotates at ~64 KB.

## Testing

Test the evaluator against any Claude Code session transcript without triggering the actual hook:

```bash
# Test against a specific session
./plugins/stop-guard/hooks/test-stop-guard.sh ~/.claude/projects/<project>/<session-id>.jsonl

# With full prompt output for debugging
./plugins/stop-guard/hooks/test-stop-guard.sh <transcript> --verbose

# Find recent sessions for a project
ls -lt ~/.claude/projects/-Users-you-code-myproject/*.jsonl | head -5
```

Example output:

```
=== Stop Guard Test ===
Transcript:  /Users/ben/.claude/projects/.../8e82687e.jsonl
Session ID:  8e82687e-3d55-4e4f-a22f-1815843dc8ef
Lines:       30
Model:       gemini-3-flash-preview
Task list:   (none found)
Activation:  marker found

--- Calling Gemini (gemini-3-flash-preview) ---

=== Result ===

Decision:    block
Reason:      4 pending tasks (#1-#4) related to testing and documenting
             the plugin have not been completed.

--- Stats ---
Tokens in:   33581
Tokens out:  290
Latency:     58702ms
Wall time:   63s
```

## Integration with other plugins

Any skill can activate stop-guard by including the activation marker in its output. For example, an `/implement` skill could start with:

```markdown
<!-- stop-guard:active -->
<!-- stop-guard:context {"task": "implement #42", "criteria": ["tests pass", "PR created"]} -->
```

This ensures the stop-guard evaluates completion against the specific task criteria.

## Files

```
plugins/stop-guard/
├── .claude-plugin/
│   └── plugin.json       # Plugin metadata
├── hooks/
│   ├── hooks.json         # Stop hook registration
│   ├── stop-guard.sh      # The hook script
│   └── test-stop-guard.sh # Test script
└── README.md
```

## License

MIT
