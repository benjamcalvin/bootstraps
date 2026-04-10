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
  version: "1.3.1"
  tags: ["implement", "cli", "agent-sdk", "multi-provider", "lifecycle"]
  author: benjamcalvin
---

# Implement (CLI)

Orchestrate the full implementation lifecycle for: $ARGUMENTS

## Context

- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`

## Instructions

<!-- stop-guard:active -->

You are the **orchestrator**. You drive the lifecycle, make referee decisions, and post to GitHub. You delegate heavy work (implementation, review, addressing) to Python Agent SDK subprocesses via the `implement-cli` CLI tool.

**Drive forward autonomously.** Execute all phases without pausing for approval between them.

---

### CLI Reference

All commands output JSON with a `tracking` section containing session IDs, costs, token usage, and the `run_dir` — a unique directory for each invocation that holds all artifacts (findings files, run context). This prevents collisions between concurrent runs.

Resolve the wrapper script path first — it lives at `run.sh` in the plugin root.

Use the Glob tool to find `**/implement-cli/run.sh`, then set:

```bash
CLI="<path returned by Glob>"
```

```bash
# Run a single agent with a prompt
"$CLI" run-agent "prompt" \
  --phase implement --role implementer --cwd "$(pwd)" \
  [--context-files file1.md file2.md] \
  [--session-id <resume-id>] \
  [--model <model>] [--tools Read Write Bash]

# Run a single agent with prompt from a file
"$CLI" run-agent --prompt-file /tmp/task-description.md \
  --phase implement --role implementer --cwd "$(pwd)"

# Run parallel reviewers
"$CLI" run-reviewers --pr 45 --round 1 --cwd "$(pwd)" \
  [--reviewers review-correctness review-security]

# Print a human-readable summary of a completed run
"$CLI" summary <run_dir>/run_context.json

# Debug: list sessions from a run
"$CLI" debug sessions <run_dir>/run_context.json

# Debug: inspect a specific session
"$CLI" debug session <session-id> --cwd "$(pwd)"

# Debug: resume a session with follow-up
"$CLI" debug resume <session-id> "What happened with the null check?" --cwd "$(pwd)"

# Global flags (must come BEFORE the subcommand)
# --version            Print version and exit
# --dry-run            Print resolved config without running agents
# --max-depth 5       Maximum recursion depth (default: 5, must be >= 1)
# --max-cost 50.0     Maximum cumulative cost in USD (default: 50.0, must be > 0)
# --verbose / -v       Verbose logging
```

---

### Entry Point

Parse `$ARGUMENTS` to determine **what to work on** and **what to do**.

**Step 1 — Identify the target** from the leading token:

1. **`#N` (issue number):** Fetch with `gh issue view N --comments` and extract task description and comment context.
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

Write the full task description to a file. Use a unique run directory to prevent collisions with concurrent runs:

```bash
RUN_DIR=$(mktemp -d -t implement-cli-XXXXXX)
cat > "$RUN_DIR/implement-task.md" <<'TASK'
<task description with acceptance criteria>
TASK
```

Invoke the implementer:

```bash
"$CLI" --verbose run-agent \
  --prompt-file "$RUN_DIR/implement-task.md" \
  --phase implement --role implementer --cwd "$(pwd)"
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

Choose reviewers judiciously from the PR summary, changed-file list, and issue/spec context. Use the smallest sufficient set for the PR, not the full pool by default:
- `review-correctness` for production logic changes
- `review-security` for auth/authz, user input, secrets, external integrations, data handling, or spec-sensitive changes
- `review-architecture` for multi-module changes, new abstractions, public APIs, dependency shifts, or structural refactors
- `review-testing` when tests changed, new behavior was added, or regression coverage is a meaningful concern

Skip specialists whose focus clearly does not apply. Then invoke the selected reviewers in parallel:

```bash
"$CLI" --verbose run-reviewers \
  --pr <PR> --round <N> --cwd "$(pwd)" \
  --reviewers <selected-reviewer>...
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
| **Accept** (default) | Finding has merit — you verified by reading the code |
| **Reject** | Incorrect, irrelevant, or ill-considered |

If zero findings survive, post `"Review Round <N>: no actionable findings"` and skip to Phase 4.5.

#### Step C: Post Decisions & Write Findings

Post referee decisions to GitHub. Write filtered findings to a file in the run directory:

```bash
cat > "$RUN_DIR/findings-round-<N>.md" <<'EOF'
<filtered findings table>
EOF
```

#### Step D: Invoke Addresser

```bash
"$CLI" --verbose run-agent \
  --prompt-file "$RUN_DIR/address-prompt.md" \
  --phase address --role addresser --cwd "$(pwd)" \
  --context-files "$RUN_DIR/findings-round-<N>.md"
```

#### Step E: Next Round or Exit

If round 10+, escalate. Otherwise return to Step A.

#### Debugging a Session

If a reviewer or addresser produces unexpected results, use the debug commands:

```bash
# See what happened in the session
"$CLI" debug session <session-id>

# Ask a follow-up
"$CLI" debug resume <session-id> \
  "Why did you flag the null check as a bug? It's guarded by the validator." \
  --cwd "$(pwd)"
```

---

### Phase 4.5: Docs Compliance Gate

After the code review/address loop converges, run a documentation curation check. The docs reviewer doesn't just check docs that were changed — it proactively identifies where documentation is missing, outdated, or contradicted by the final state of the code (including all review fixes). This catches gaps like new CLI commands without usage docs, changed defaults that contradict existing guides, or architectural decisions that need ADRs.

**Do NOT include `review-docs` in the Phase 4 reviewer pool.** It runs only here, after the code review loop is complete.

```bash
"$CLI" --verbose run-reviewers \
  --pr <PR> --round 1 --reviewers review-docs --cwd "$(pwd)"
```

Apply the same referee evaluation and address loop as Phase 4. The round counter starts from 1 (independent of Phase 4 rounds). Same 10-round escalation limit.

---

### Phase 5: Verification

```bash
"$CLI" --verbose run-agent \
  --prompt-file "$RUN_DIR/verify-prompt.md" \
  --phase verify --role verifier --cwd "$(pwd)"
```

---

### Phase 6: Merge

```bash
"$CLI" --verbose run-agent --prompt-file "$RUN_DIR/merge-prompt.md" \
  --phase merge --role merger --cwd "$(pwd)"
```

---

### Tracking & Observability

Every CLI invocation returns a `tracking` section:

```json
{
  "tracking": {
    "run_dir": "/tmp/implement-cli-abc123",
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
        "input_tokens": 30000,
        "output_tokens": 5000,
        "duration_ms": 36000,
        "is_error": false,
        "depth": 1
      }
    ]
  }
}
```

**Run directory isolation:** Each invocation creates a unique directory (shown in `run_dir`) for all artifacts — findings files, prompts, run context. This prevents collisions between concurrent runs. The `run_context.json` file inside the run directory has the full session history for debugging.

Monitor `total_cost_usd` throughout the lifecycle. For a human-readable overview of a completed run, use `summary <run_context.json>`. If costs are unexpectedly high, investigate using `debug sessions` and `debug session` commands.

---

### Escalation

Stop and flag the human when:
- Ambiguous requirements
- Architectural decisions exceeding task scope
- New third-party dependency needed
- Auth, crypto, or PII handling changes
- Unrelated test failures
- Cost ceiling approaching or exceeded
