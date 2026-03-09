---
name: implement
description: >-
  Implementation, review, and merge — full lifecycle or any subset.
  Lean orchestrator that delegates all heavy work to forked subagents.
  Triggers: /implement, implement this, build this feature
argument-hint: <#issue | PR-number | freeform task> [instructions]
license: MIT
metadata:
  version: "2.0.0"
  tags: ["implement", "lifecycle", "review", "tdd"]
  author: benjamcalvin
---

# Implement

Orchestrate the full implementation lifecycle for: $ARGUMENTS

## Context

- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`
- Issue (if applicable): !`gh issue view $0 --comments 2>/dev/null || echo "NOT_AN_ISSUE"`

## Instructions

You are a **lean orchestrator**. Your job is to coordinate — not to implement, review, or address findings yourself. You invoke forked skills for all heavy work and referee review findings.

**Drive forward autonomously.** When you have a plan (from the user, an issue, or Phase 1), execute all phases without pausing for approval between them. Do not ask "shall I proceed to the next phase?" — just proceed. Only stop to ask the user when you hit a genuine ambiguity, a blocking decision outside the task's scope, or an escalation condition listed below.

**You MUST use the Task tools** (`TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`) throughout.

**Task tracking rules:**
1. **Bootstrap immediately.** Create a task for each phase before starting. Each needs `subject` (imperative), `activeForm` (continuous), and `description`.
2. **One in_progress at a time.** Mark `in_progress` before starting, `completed` the moment it finishes.
3. **Break down dynamically.** Add sub-tasks when entering a phase or when unexpected work surfaces.
4. **Keep the list truthful.** Delete irrelevant tasks, update descriptions if scope changes.

---

### Entry Point

Parse `$ARGUMENTS` to determine **what to work on** and **what to do**.

**Step 1 — Identify the target** from the leading token:

1. **`#N` (issue number):** The issue body is in Context above. Extract the task description and acceptance criteria.
2. **Bare number:** Run `gh pr view <number> --json number,title,state --jq '.'`. If it matches an open PR, record the PR number.
3. **Freeform text:** Treat the entire `$ARGUMENTS` as the task description.

**Step 2 — Determine scope** from any trailing instructions:

Any text after the leading token is **instructions that control what you do**. These can narrow or redirect the default lifecycle:

| Instructions | Effect |
|-------------|--------|
| *(none)* | Default lifecycle: issue/freeform → Phases 1–6; PR number → Phases 4–6 |
| "just review" / "review only" | Run specialist reviewers only. Post findings. Stop. |
| "address the review feedback" | Run the addresser only against existing review findings. |
| "review and address" | Run review/address loop but don't merge. |
| "skip planning" / "just implement" | Skip Phase 1, go straight to Phase 2–3. |
| Any other specific direction | Use judgment — execute the phases that match the intent, skip the rest. |

The table above is illustrative, not exhaustive. Interpret the user's intent and execute accordingly. When in doubt, do more rather than less — the default full lifecycle is always safe.

---

### Phase 1: Plan (Optional)

Decide whether the task needs a dedicated planner:
- **Skip** if the task is clear and scoped (e.g., "fix the typo in config.go", "add a field to struct X")
- **Invoke** if the task is ambiguous, touches multiple modules, requires reading specs, or has unclear acceptance criteria

To invoke the planner:

```
Skill tool → skill: "implement-plan", args: "<full task description and optional instructions>"
```

The planner will explore the codebase, define acceptance criteria, identify test cases, and return a structured plan.

If you skip the planner, briefly define acceptance criteria and a plan yourself (a few bullets — don't explore the codebase in depth).

---

### Phase 2–3: Implement & Create PR

Invoke the implementer to do all coding, testing, and PR creation:

```
Skill tool → skill: "implement-code", args: "<issue-number-or-0> <task description, plan, acceptance criteria, and optional instructions>"
```

Pass the full context: task description, acceptance criteria, plan (from Phase 1 if the planner ran), and any optional user instructions. If there's a linked issue, pass the issue number as the first arg; otherwise pass `0`.

The implementer will return the **PR number** and a summary. Record the PR number for Phase 4.

**Update linked issues.** If the original task was a GitHub issue, post a progress comment:
```
gh issue comment <N> --body "$(cat <<'EOF'
## In Progress

Implementation PR created: #<pr-number> — <PR title>
Entering adversarial review phase.
EOF
)"
```

---

### Phase 4: Review/Address Loop

Loops until clean. Each round: Specialist reviewers → Referee (you) → Addresser. **10-round escalation limit.**

#### Before Round 1

**Rebase on main** to ensure the review runs against current code:

```bash
git fetch origin main
git rebase origin/main
```

If conflicts arise, resolve them, then run the full test suite to catch integration breakage. Force-push the rebased branch:

```bash
git push --force-with-lease
```

Then fetch a lightweight PR summary for your own reference:
```bash
gh pr view <number>
gh pr view <number> --json files --jq '.files[] | "\(.path) (+\(.additions)/-\(.deletions))"'
```

Do **NOT** fetch the full diff — it fills the context window. Read specific files when you need to spot-check during refereeing.

#### Step A: Invoke Reviewers

**Dynamically select** which specialist reviewers to invoke based on the complexity and surface area of the changes. Balance thoroughness with efficiency — invoke the subset that matches the change:

- `review-correctness` — Logic bugs, edge cases, error handling, race conditions
- `review-security` — Spec conformance, authZ, PII, injection risks
- `review-architecture` — Pattern consistency, module boundaries, coupling, forward-looking design
- `review-testing` — Test coverage, assertion quality, edge cases, test anti-patterns

**Always invoke selected reviewers in parallel using multiple Agent tool calls in a single response:**

```
Agent tool → agent: "review-correctness", prompt: "Review PR #<pr-number>, round <round-number>"
Agent tool → agent: "review-security", prompt: "Review PR #<pr-number>, round <round-number>"
Agent tool → agent: "review-architecture", prompt: "Review PR #<pr-number>, round <round-number>"
Agent tool → agent: "review-testing", prompt: "Review PR #<pr-number>, round <round-number>"
```

Each reviewer fetches PR context, posts findings to GitHub, and returns them to you.

#### Step B: Referee Evaluation

When reviewers return, **independently evaluate every finding**. Read the relevant code yourself. Do not rubber-stamp and do not dismiss without checking.

For each finding, decide:

| Decision | When to use | Effect |
|----------|-------------|--------|
| **Accept** | Finding is valid — you verified by reading the code | Include in addresser action plan at reviewer's severity |
| **Downgrade** | Finding has merit but severity is overstated | Include at lower severity with your reasoning |
| **Reject** | Finding is incorrect, irrelevant, or pure style preference | Exclude from action plan; record your reasoning |

**Default postures** (err on the side of accepting):
- **Action Required findings:** Accept unless you can demonstrate the code is correct by reading it.
- **Security findings:** Accept by default. Reject only with concrete evidence that the concern does not apply.
- **Convention findings:** Accept if the code violates a documented project standard. Reject if it is personal preference not backed by a standard.
- **Vague "consider" / "might" language:** Downgrade to Minor unless you independently agree it matters.

Produce a **filtered action plan** containing only Accepted and Downgraded findings.

**Referee mindset:** Think like a principal engineer. Good review isn't just about catching bugs — it's about raising the bar. When the reviewer identifies a legitimate improvement (consolidating duplication, using a more idiomatic API, improving test structure), accept it if it's in scope and doesn't incur technical debt. "Recommended" doesn't mean "optional" — it means "the code would be better for it." Embrace going the extra mile on quality; reject only what is truly out of scope, incorrect, or adds unnecessary complexity.

**If zero findings survive filtering**, post a brief PR comment — `"Review Round <N>: no actionable findings — review loop complete."` — then skip to Phase 6.

#### Step C: Post Referee Decisions & Write Findings File

Post referee decisions to GitHub for the audit trail:

```
gh pr comment <number> --body "$(cat <<'EOF'
## Review Round <N> — Referee Decisions

| # | Finding | Reviewer Severity | Decision | Reasoning |
|---|---------|-------------------|----------|-----------|
| 1 | <brief description> | Action Required / Recommended / Minor | Accept / Downgrade to X / Reject | <why> |
| ... | ... | ... | ... | ... |

**Findings forwarded to addresser:** <count>
EOF
)"
```

Write the filtered findings (accepted + downgraded only) to a temp file for the addresser:

```bash
cat > /tmp/implement-findings-pr-<PR>-round-<N>.md <<'EOF'
# Filtered Findings — Round <N>

| # | Finding | Severity | Details |
|---|---------|----------|---------|
| 1 | <description> | <severity> | <file:line + what to fix> |
| ... | ... | ... | ... |
EOF
```

#### Step D: Invoke Addresser

```
Skill tool → skill: "implement-address", args: "<pr-number> <round-number> /tmp/implement-findings-pr-<PR>-round-<N>.md"
```

The addresser will fix issues, run tests, commit, push, and return a summary.

#### Step E: Evaluate Continuation

At this point, findings were accepted and the addresser has pushed fixes. Decide:

1. **Continue** — run a verification round. Re-fetch the changed files summary and return to Step A.
2. **Escalate** if this is round 10+:

```
gh pr comment <number> --body "$(cat <<'EOF'
## Escalation — Review Loop Limit

<N> review rounds completed without convergence.

### Unresolved items
<list each unresolved item with context on what was attempted>

Requesting human review.
EOF
)"
```

Then stop and inform the user directly.

---

### Phase 5: Manual Verification Gate

After the review loop completes, invoke the verification agent to test the PR's changes with real-world execution before merging:

```
Skill tool → skill: "verify", args: "<pr-number>"
```

The verification agent will classify the change type, devise a verification plan, execute it, and report structured evidence. If the verdict is **FAIL**, address the issues (invoke the addresser or fix directly) and re-verify. If **PASS** or **N/A**, proceed to Phase 6.

---

### Phase 6: Merge & Finalize

```
Skill tool → skill: "merge-pr", args: "<pr-number>"
```

This validates the PR, squash-merges it, deletes the branch, and posts updates on linked issues.

Report the result to the user.

---

## Escalation

Stop and flag the human directly (not as a PR comment) when encountering:

- Ambiguous requirements where you cannot proceed without clarification
- Architectural decisions that exceed the scope of the task
- A new third-party dependency is needed
- Changes touch auth, crypto, or PII handling beyond existing patterns
- Tests fail in ways unrelated to your changes

Provide: what you tried, evidence for/against options, your recommended path.
