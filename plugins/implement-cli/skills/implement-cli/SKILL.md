---
name: implement-cli
description: >-
  CLI-based implementation lifecycle using the Python Agent SDK.
  Orchestrates plan, implement, review/address loop, docs gate, verify, and merge
  via claude-agent-sdk subprocesses with native async parallelism.
  Triggers: /implement-cli
argument-hint: <#issue | PR-number | freeform task> [instructions]
license: MIT
metadata:
  version: "1.0.0"
  tags: ["implement", "cli", "agent-sdk", "multi-provider", "lifecycle"]
  author: benjamcalvin
---

# Implement (CLI)

Orchestrate the full implementation lifecycle for: $ARGUMENTS

## Context

- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`

## Instructions

You are the **orchestrator**. You drive the lifecycle, make referee decisions, and post to GitHub. You delegate heavy work (implementation, review, addressing) to Python Agent SDK subprocesses via the `implement-cli` CLI tool.

**Drive forward autonomously.** Execute all phases without pausing for approval between them.

---

### CLI Reference

The `implement-cli` tool lives in `<plugin-dir>/scripts/`. All commands output JSON with a `tracking` section containing session IDs, costs, and token usage. Always inspect the tracking section to monitor costs and identify sessions for debugging.

```bash
SCRIPTS_DIR="<plugin-scripts-dir>"

# Run a single agent with a prompt
uv run --directory "$SCRIPTS_DIR" implement-cli run-agent "prompt" \
  --phase implement --role implementer --cwd "$(pwd)" \
  [--context-files file1.md file2.md] \
  [--session-id <resume-id>] \
  [--model <model>] [--tools Read Write Bash]

# Run a single agent with prompt from a file
uv run --directory "$SCRIPTS_DIR" implement-cli run-agent \
  --prompt-file /tmp/task-description.md \
  --phase implement --role implementer --cwd "$(pwd)"

# Run parallel reviewers
uv run --directory "$SCRIPTS_DIR" implement-cli run-reviewers \
  --pr 45 --round 1 --cwd "$(pwd)" \
  [--reviewers review-correctness review-security]

# Debug: list sessions from a run
uv run --directory "$SCRIPTS_DIR" implement-cli debug sessions /tmp/implement-cli-run-*.json

# Debug: inspect a specific session
uv run --directory "$SCRIPTS_DIR" implement-cli debug session <session-id> --cwd "$(pwd)"

# Debug: resume a session with follow-up
uv run --directory "$SCRIPTS_DIR" implement-cli debug resume <session-id> "What happened with the null check?" --cwd "$(pwd)"

# Global flags (apply to all commands)
# --max-depth 5       Maximum recursion depth (default: 5)
# --max-cost 50.0     Maximum cumulative cost in USD (default: 50.0)
# -v                  Verbose logging
```

---

### Entry Point

Parse `$ARGUMENTS` to determine **what to work on** and **what to do**.

**Step 1 — Identify the target** from the leading token:

1. **`#N` (issue number):** Fetch with `gh issue view N` and extract task description.
2. **Bare number:** Check if it's a PR with `gh pr view N`. If so, record the PR number.
3. **Freeform text:** Use the entire text as the task description.

**Step 2 — Determine scope** from trailing instructions:

| Instructions | Effect |
|-------------|--------|
| *(none)* | Default lifecycle: issue/freeform → Phases 1–6; PR number → Phases 4–6 |
| "just review" / "review only" | Run reviewers only, post findings, stop |
| "address the review feedback" | Run the addresser against existing findings |
| "skip planning" / "just implement" | Skip codebase exploration and planning |

---

### Phase 1-3: Plan, Implement & Create PR

Write the full task description (with acceptance criteria from the issue, if any) to a temp file:

```bash
cat > /tmp/implement-task.md <<'TASK'
<task description with acceptance criteria>
TASK
```

Invoke the implementer:

```bash
uv run --directory "$SCRIPTS_DIR" implement-cli run-agent \
  --prompt-file /tmp/implement-task.md \
  --phase implement --role implementer --cwd "$(pwd)" -v
```

Parse the JSON output to extract:
- `result.session_id` — record for debugging
- `result.text` — search for `PR_NUMBER: <N>` to get the PR number
- `tracking.total_cost_usd` — monitor spend

If linked to an issue, post a progress comment:
```bash
gh issue comment <N> --body "Implementation PR created: #<pr-number>. Entering review phase."
```

---

### Phase 4: Review/Address Loop

**Before Round 1:** Rebase on main.

#### Step A: Run Reviewers

Invoke parallel reviewers:

```bash
uv run --directory "$SCRIPTS_DIR" implement-cli run-reviewers \
  --pr <PR> --round <N> --cwd "$(pwd)" -v
```

Parse JSON output — each reviewer's result is in `reviewers.<name>`:
- `session_id` — for debugging
- `text` — the review findings
- `cost_usd`, `input_tokens`, `output_tokens` — tracking

**Always check `tracking.total_cost_usd`** after each invocation. If approaching the limit, warn and consider stopping.

#### Step B: Referee Evaluation

**You** evaluate every finding. Read the relevant code yourself. For each finding:

| Decision | When to use |
|----------|-------------|
| **Accept** | Valid — you verified by reading the code |
| **Downgrade** | Has merit but severity is overstated |
| **Reject** | Incorrect, irrelevant, or pure style preference |

If zero findings survive, post `"Review Round <N>: no actionable findings"` and skip to Phase 4.5.

#### Step C: Post Decisions & Write Findings

Post referee decisions to GitHub. Write filtered findings to a temp file.

#### Step D: Invoke Addresser

```bash
uv run --directory "$SCRIPTS_DIR" implement-cli run-agent \
  --prompt-file /tmp/address-prompt.md \
  --phase address --role addresser --cwd "$(pwd)" \
  --context-files /tmp/implement-findings-pr-<PR>-round-<N>.md -v
```

#### Step E: Next Round or Exit

If round 10+, escalate. Otherwise return to Step A.

#### Debugging a Session

If a reviewer or addresser produces unexpected results, use the debug commands:

```bash
# See what happened in the session
uv run --directory "$SCRIPTS_DIR" implement-cli debug session <session-id>

# Ask a follow-up
uv run --directory "$SCRIPTS_DIR" implement-cli debug resume <session-id> \
  "Why did you flag the null check as a bug? It's guarded by the validator." \
  --cwd "$(pwd)"
```

---

### Phase 4.5: Docs Compliance Gate

Same pattern as Phase 4, but only `review-docs`:

```bash
uv run --directory "$SCRIPTS_DIR" implement-cli run-reviewers \
  --pr <PR> --round 1 --reviewers review-docs --cwd "$(pwd)" -v
```

---

### Phase 5: Verification

```bash
uv run --directory "$SCRIPTS_DIR" implement-cli run-agent \
  --prompt-file /tmp/verify-prompt.md \
  --phase verify --role verifier --cwd "$(pwd)" -v
```

---

### Phase 6: Merge

```bash
uv run --directory "$SCRIPTS_DIR" implement-cli run-agent \
  --prompt-file /tmp/merge-prompt.md \
  --phase merge --role merger --cwd "$(pwd)" -v
```

---

### Tracking & Observability

Every CLI invocation returns a `tracking` section:

```json
{
  "tracking": {
    "total_cost_usd": 2.34,
    "total_input_tokens": 150000,
    "total_output_tokens": 25000,
    "total_sessions": 5,
    "max_depth_reached": 1,
    "elapsed_seconds": 180.5,
    "sessions": [
      {
        "session_id": "abc123",
        "phase": "review",
        "role": "review-correctness",
        "cost_usd": 0.45,
        "is_error": false,
        "depth": 1
      }
    ]
  }
}
```

Monitor `total_cost_usd` throughout the lifecycle. If costs are unexpectedly high, investigate using `debug sessions` and `debug session` commands.

Run context is also saved to `/tmp/implement-cli-run-<timestamp>.json` for later inspection.

---

### Escalation

Stop and flag the human when:
- Ambiguous requirements
- Architectural decisions exceeding task scope
- New third-party dependency needed
- Auth, crypto, or PII handling changes
- Unrelated test failures
- Cost ceiling approaching or exceeded
