---
name: implement
description: >-
  Implementation, review, and merge — full lifecycle or any subset.
  Lean orchestrator that delegates all heavy work to forked subagents.
  Triggers: /implement, implement this, build this feature
argument-hint: <#issue | PR-number | freeform task> [instructions]
license: MIT
metadata:
  version: "3.0.0"
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

<!-- stop-guard:active -->

You are a **lean orchestrator**. Your job is to coordinate — not to implement, review, or address findings yourself. You invoke forked skills for all heavy work and referee review findings.

**Drive forward autonomously.** When you have a plan (from the user or an issue), execute all phases without pausing for approval between them. Do not ask "shall I proceed to the next phase?" — just proceed. Only stop to ask the user when you hit a genuine ambiguity, a blocking decision outside the task's scope, or an escalation condition listed below.

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
| "skip planning" / "just implement" | Pass "skip planning" to implement-code so it skips codebase exploration and plan formulation. |
| Any other specific direction | Use judgment — execute the phases that match the intent, skip the rest. |

The table above is illustrative, not exhaustive. Interpret the user's intent and execute accordingly. When in doubt, do more rather than less — the default full lifecycle is always safe.

---

### Phase 1–3: Plan, Implement & Create PR

Planning is handled internally by `implement-code`. Do **not** invoke a separate planning step — this eliminates the seam where the orchestrator might pause for approval between planning and coding.

Decide whether the task needs planning and pass appropriate instructions:
- **Needs planning** (ambiguous, touches multiple modules, unclear acceptance criteria): pass the task description without "skip planning"
- **Skip planning** (clear, scoped tasks like "fix the typo in config.go"): include "skip planning" in the instructions

Invoke the implementer:

```
Skill tool → skill: "implement-code", args: "<issue-number-or-0> <task description, acceptance criteria, and optional instructions>"
```

Pass the full context: task description, acceptance criteria from the issue (if any), and any optional user instructions. If there's a linked issue, pass the issue number as the first arg; otherwise pass `0`.

The implementer will plan internally (if needed), write code, write tests, and return the **PR number** and a summary. Record the PR number for Phase 4.

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

### Phase 4: Review/Address Loop {#review-loop}

**This is a mandatory loop.** It repeats Steps A → B → C → D → E for each round until one of exactly two exit conditions is met:

1. **Clean exit (Step B):** Zero findings survive referee filtering → skip to Phase 4.5.
2. **Escalation exit (Step E):** Round 10+ reached → escalate and stop.

There is no other way to exit this loop. Each round: Specialist reviewers → Referee (you) → Addresser → next round. **10-round escalation limit.**

#### Before Round 1

**Rebase on the PR's current base branch** to ensure the review runs against current code:

```bash
BASE_BRANCH=$(gh pr view --json baseRefName --jq -r '.baseRefName')
git fetch origin "$BASE_BRANCH"
git rebase "origin/$BASE_BRANCH"
```

If conflicts arise, resolve them, then run the full test suite to catch integration breakage. Force-push the rebased branch:

```bash
git push --force-with-lease
```

Then fetch a lightweight PR summary for your own reference:
```bash
gh pr view <number>
gh pr view <number> --json files --jq '.files[] | "\(.path) (+\(.additions)/-\(.deletions))"'
gh pr view <number> --comments
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
| **Accept** (default) | Finding has merit — you verified by reading the code | Include in addresser action plan at the reviewer's original severity |
| **Reject** | Finding is incorrect, irrelevant, or ill-considered | Exclude from action plan; record your reasoning |

**Default postures** (err on the side of accepting):
- Default to **accept** unless you can demonstrate the finding is wrong by reading the code.
- **Security findings:** Accept by default. Reject only with concrete evidence that the concern does not apply.
- **Convention findings:** Accept if the code violates a documented standard. Reject if purely stylistic preference with no backing standard.
- **Vague "consider" / "might" language:** Accept if you independently agree it matters. Reject if not.

Produce a **filtered action plan** containing only accepted findings.

**Referee mindset:** Think like a principal engineer. Good review isn't just about catching bugs — it's about raising the bar. When the reviewer identifies a legitimate improvement (consolidating duplication, using a more idiomatic API, improving test structure), accept it if it's in scope and doesn't incur technical debt. "Recommended" doesn't mean "optional" — it means "the code would be better for it." Embrace going the extra mile on quality; reject only what is truly out of scope, incorrect, or adds unnecessary complexity.

**If zero findings survive filtering**, post a brief PR comment — `"Review Round <N>: no actionable findings — review loop complete."` — then skip to Phase 4.5.

#### Step C: Post Referee Decisions & Write Findings File

Post referee decisions to GitHub for the audit trail:

```
gh pr comment <number> --body "$(cat <<'EOF'
## Review Round <N> — Referee Decisions

| # | Finding | Reviewer Severity | Decision | Reasoning |
|---|---------|-------------------|----------|-----------|
| 1 | <brief description> | Action Required / Recommended / Minor | Accept / Reject | <why> |
| ... | ... | ... | ... | ... |

**Findings forwarded to addresser:** <count>
EOF
)"
```

Write the filtered findings (accepted only) to a temp file for the addresser:

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

#### Step E: Next Round

The addresser has pushed fixes. Check the escalation limit, then continue.

1. **Check escalation limit:** If this was round 10 or higher, escalate — do **not** continue to another round:

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

2. **Continue:** Re-fetch the changed files summary, increment the round counter, and **return to Step A immediately.** Do not pause, do not ask for confirmation, do not evaluate whether to continue — the loop continues unconditionally until a clean exit in Step B or the escalation limit above.

---

### Phase 4.5: Docs Compliance Gate

After the code review/address loop converges, run the docs curation gate. **This gate is mandatory even if the PR contains no documentation file changes.** The docs reviewer is a curator, not a diff checker — it proactively identifies where documentation is missing, outdated, or contradicted by the code changes. A PR that adds a new CLI command, changes a default, or restructures internals may need docs updates even though no `.md` files were touched.

**Do NOT include `review-docs` in the Phase 4 reviewer pool.** It runs only here, after the code review loop is complete. **Do NOT skip this phase** based on the file list — the reviewer itself will determine if no docs updates are needed.

#### Step A: Invoke Docs Reviewer

```
Agent tool → agent: "review-docs", prompt: "Review PR #<pr-number> for documentation compliance, round <round-number>"
```

The docs reviewer fetches PR context, maps code changes to existing documentation, and identifies gaps — not just inaccuracies in changed docs, but missing docs for new behavior and stale docs contradicted by code changes.

#### Step B: Referee Evaluation

Apply the same accept/reject evaluation as Phase 4. Read the relevant docs and code yourself.

| Decision | When to use | Effect |
|----------|-------------|--------|
| **Accept** (default) | Finding has merit — you verified by reading the docs/code | Include in addresser action plan at the reviewer's original severity |
| **Reject** | Finding is incorrect, irrelevant, or demands docs for trivial changes | Exclude from action plan; record your reasoning |

**If zero findings survive filtering**, post a brief PR comment — `"Docs Compliance Gate: no actionable findings — proceeding to verification."` — then skip to Phase 5.

#### Step C: Post Referee Decisions & Invoke Addresser

Post referee decisions to GitHub (same table format as Phase 4):

```
gh pr comment <number> --body "$(cat <<'EOF'
## Docs Compliance Gate Round <N> — Referee Decisions

| # | Finding | Reviewer Severity | Decision | Reasoning |
|---|---------|-------------------|----------|-----------|
| 1 | <brief description> | Action Required / Recommended / Minor | Accept / Reject | <why> |
| ... | ... | ... | ... | ... |

**Findings forwarded to addresser:** <count>
EOF
)"
```

Write findings to a temp file and invoke the addresser:

```bash
cat > /tmp/implement-docs-findings-pr-<PR>-round-<N>.md <<'EOF'
# Docs Compliance Findings — Round <N>

| # | Finding | Severity | Details |
|---|---------|----------|---------|
| 1 | <description> | <severity> | <file:line + what to fix> |
| ... | ... | ... | ... |
EOF
```

```
Skill tool → skill: "implement-address", args: "<pr-number> docs-<round-number> /tmp/implement-docs-findings-pr-<PR>-round-<N>.md"
```

#### Step D: Evaluate Continuation

Re-invoke the docs reviewer to verify fixes. The round counter starts from round 1 (independent of Phase 4 rounds). Loop until clean. **Same 10-round escalation limit as Phase 4** — if docs review does not converge, escalate with the same format.

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
