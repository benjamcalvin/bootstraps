---
name: implement-cli
description: >-
  CLI-based implementation lifecycle using the Python Agent SDK.
  Orchestrates plan, implement, review/address loop, docs gate, verify, and merge
  via claude-agent-sdk subprocesses with native async parallelism.
  Triggers: /implement-cli
argument-hint: <#issue | PR-number | freeform task> [--skip-planning] [--reviewers r1 r2] [--pr N]
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

You are the **CLI orchestrator**. You delegate all heavy work to Python Agent SDK subprocesses and referee review findings.

### Entry Point

Parse `$ARGUMENTS` to build the CLI invocation.

**Step 1 — Identify the target** from the leading token:

1. **`#N` (issue number):** Fetch with `gh issue view N` and extract task description.
2. **Bare number:** Check if it's a PR with `gh pr view N`. If so, pass `--pr N`.
3. **Freeform text:** Use the entire text as the task description.

**Step 2 — Build CLI arguments** from trailing instructions:

| Instructions | CLI flags |
|-------------|-----------|
| "skip planning" / "just implement" | `--skip-planning` |
| "just review" / "review only" | `--phases review` |
| "review and address" | `--phases review` |
| Specific reviewers | `--reviewers <list>` |

### Invocation

Ensure the Python environment is set up, then run the orchestrator:

```bash
cd <plugin-scripts-dir>
uv run implement-cli "<task description>" \
  --cwd "$(pwd)" \
  [--skip-planning] \
  [--pr N] \
  [--reviewers r1 r2 ...] \
  [--phases p1 p2 ...] \
  -v
```

The `<plugin-scripts-dir>` is the `scripts/` directory within this plugin's installation path.

### Interpreting Results

The orchestrator outputs JSON with phase results. Parse and report:

- **PR number** — from the implement phase
- **Review convergence** — whether the review loop exited clean
- **Verification verdict** — PASS/FAIL/N/A
- **Merge status** — success or failure reason

### Escalation

Stop and flag the human when:

- Ambiguous requirements
- Architectural decisions exceeding task scope
- New third-party dependency needed
- Auth, crypto, or PII handling changes
- Unrelated test failures
