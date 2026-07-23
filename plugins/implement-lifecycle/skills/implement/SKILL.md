---
name: implement
description: >-
  Implementation, review, and merge — full lifecycle or any subset.
  Lean orchestrator that delegates all heavy work to forked subagents.
  Triggers: /implement, $implement-lifecycle:implement, implement this, build this feature
license: MIT
metadata:
  version: "3.2.0"
  tags: ["implement", "lifecycle", "review", "tdd"]
  author: benjamcalvin
---

# Implement

Orchestrate the full implementation lifecycle using the task supplied with the skill invocation.

Claude Code expands the invocation payload below. In Codex, it may remain literal; when that happens, use the user's invoking prompt instead.

```text
$ARGUMENTS
```

At runtime, inspect the current branch and recent commits. If the leading input is an issue number, fetch the issue and comments with `gh issue view` before planning the workflow.

## Instructions

<!-- stop-guard:active -->

You are a **lean orchestrator**. Your job is to coordinate — not to implement, review, or address findings yourself. You invoke forked skills for all heavy work and referee review findings.

**Drive forward autonomously.** When you have a plan (from the user or an issue), execute all phases without pausing for approval between them. Do not ask "shall I proceed to the next phase?" — just proceed. Only stop to ask the user when you hit a genuine ambiguity, a blocking decision outside the task's scope, or an escalation condition listed below.

Use the current client's task or plan tracker throughout when one is available. In Claude Code, use the Task tools. In Codex, use the plan-tracking capability. Do not block the workflow merely because a client exposes no tracker.

**Task tracking rules:**
1. **Bootstrap immediately.** Create an item for each phase before starting, using the fields supported by the current client's tracker. With Claude Code Task tools, provide `subject` (imperative), `activeForm` (continuous), and `description`.
2. **One in_progress at a time.** Mark `in_progress` before starting, `completed` the moment it finishes.
3. **Break down dynamically.** Add sub-tasks when entering a phase or when unexpected work surfaces.
4. **Keep the list truthful.** Delete irrelevant tasks, update descriptions if scope changes.

---

### Cross-client delegation

Always delegate implementation, addressing, verification, and specialist review work. Use the mechanism exposed by the current client:

- **Claude Code:** invoke the unqualified skill name or named reviewer agent, such as `implement-code` or `review-correctness`.
- **Codex:** spawn a subagent and explicitly invoke the plugin-namespaced skill, such as `$implement-lifecycle:implement-code` or `$implement-lifecycle:review-correctness`. Ask Codex to run independent reviewer subagents in parallel and wait for all results.

Pass the complete task or PR context in every delegation prompt. Do not assume a child receives the parent's local notes.

### Entry Point

Parse the invocation input to determine **what to work on** and **what to do**.

**Step 1 — Identify the target** from the leading token:

1. **`#N` (issue number):** Fetch the issue body and comments with `gh issue view`, then extract the task description and acceptance criteria.
2. **Bare number:** Run `gh pr view <number> --json number,title,state --jq '.'`. If it matches an open PR, record the PR number.
3. **Freeform text:** Treat the entire invocation input as the task description.

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

Delegate to the implementer. In Claude Code, use `implement-code`. In Codex, explicitly tell the subagent to use `$implement-lifecycle:implement-code`:

```
Payload: <issue-number-or-0> <task description, acceptance criteria, and optional instructions>
```

Pass the full context: task description, acceptance criteria from the issue (if any), and any optional user instructions. If there's a linked issue, pass the issue number as the first arg; otherwise pass `0`.

The implementer will plan internally (if needed), write code, write tests, and return the **PR number** and a summary. Record the PR number for Phase 4.

**Update linked issues.** If the original task was a GitHub issue, write this progress comment to a temporary Markdown file and post it with `gh issue comment <N> --body-file <path>`:

```md
## In Progress

Implementation PR created: #<pr-number> — <PR title>
Entering adversarial review phase.
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
BASE_BRANCH=$(gh pr view --json baseRefName --jq '.baseRefName')
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

**Dynamically select** which specialist reviewers to invoke based on the complexity, risk, and surface area of the changes. Be judicious: use the smallest sufficient reviewer set for the PR, not the full pool by default. Balance thoroughness with efficiency — invoke the subset that matches the change:

- `review-correctness` — Logic bugs, edge cases, error handling, race conditions
- `review-security` — Spec conformance, authZ, PII, injection risks
- `review-architecture` — Pattern consistency, module boundaries, coupling, forward-looking design
- `review-testing` — Test coverage, assertion quality, edge cases, test anti-patterns

Use judgment from the PR summary, changed-file list, and issue/spec context:
- **Always include `review-correctness`** when production logic changed.
- Include **`review-security`** for auth/authz, user input, secrets, external integrations, data handling, permission boundaries, or whenever requirements/spec conformance is important.
- Include **`review-architecture`** for multi-module changes, new abstractions, dependency shifts, public APIs, or structural refactors.
- Include **`review-testing`** when tests changed, new behavior was added, or existing behavior changed without obvious regression coverage.
- Skip reviewers whose specialty clearly does not apply; do not summon them just for ritual coverage.

**Always invoke selected reviewers in parallel.** Use named reviewer agents in Claude Code. In Codex, spawn one subagent per selected specialty and explicitly invoke its matching plugin-namespaced skill:

```
$implement-lifecycle:review-correctness Review PR #<pr-number>, round <round-number>
$implement-lifecycle:review-security Review PR #<pr-number>, round <round-number>
$implement-lifecycle:review-architecture Review PR #<pr-number>, round <round-number>
$implement-lifecycle:review-testing Review PR #<pr-number>, round <round-number>
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

Write referee decisions to a temporary Markdown file and post them with `gh pr comment <number> --body-file <path>` for the audit trail:

```md
## Review Round <N> — Referee Decisions

| # | Finding | Reviewer Severity | Decision | Reasoning |
|---|---------|-------------------|----------|-----------|
| 1 | <brief description> | Action Required / Recommended / Minor | Accept / Reject | <why> |
| ... | ... | ... | ... | ... |

**Findings forwarded to addresser:** <count>
```

Write the filtered findings (accepted only) to a temp file for the addresser using the current client's file-editing capability:

```md
# Filtered Findings — Round <N>

| # | Finding | Severity | Details |
|---|---------|----------|---------|
| 1 | <description> | <severity> | <file:line + what to fix> |
| ... | ... | ... | ... |
```

#### Step D: Invoke Addresser

Delegate to a subagent using `implement-address` in Claude Code or `$implement-lifecycle:implement-address` in Codex, with `<pr-number> <round-number> /tmp/implement-findings-pr-<PR>-round-<N>.md`.

The addresser will fix issues, run tests, commit, push, and return a summary.

#### Step E: Next Round

The addresser has pushed fixes. Check the escalation limit, then continue.

1. **Check escalation limit:** If this was round 10 or higher, escalate — do **not** continue to another round:

Write this escalation comment to a temporary Markdown file and post it with `gh pr comment <number> --body-file <path>`:

```md
## Escalation — Review Loop Limit

<N> review rounds completed without convergence.

### Unresolved items
<list each unresolved item with context on what was attempted>

Requesting human review.
```

Then stop and inform the user directly.

2. **Continue:** Re-fetch the changed files summary, increment the round counter, and **return to Step A immediately.** Do not pause, do not ask for confirmation, do not evaluate whether to continue — the loop continues unconditionally until a clean exit in Step B or the escalation limit above.

---

### Phase 4.5: Docs Compliance Gate

After the code review/address loop converges, run the docs curation gate. **This gate is mandatory even if the PR contains no documentation file changes.** The docs reviewer is a curator, not a diff checker — it proactively identifies where documentation is missing, outdated, or contradicted by the code changes. A PR that adds a new CLI command, changes a default, or restructures internals may need docs updates even though no `.md` files were touched.

**Do NOT include `review-docs` in the Phase 4 reviewer pool.** It runs only here, after the code review loop is complete. **Do NOT skip this phase** based on the file list — the reviewer itself will determine if no docs updates are needed.

#### Step A: Invoke Docs Reviewer

Use the named `review-docs` agent in Claude Code. In Codex, spawn a subagent and explicitly invoke `$implement-lifecycle:review-docs` with: `Review PR #<pr-number> for documentation compliance, round <round-number>`.

The docs reviewer fetches PR context, maps code changes to existing documentation, and identifies gaps — not just inaccuracies in changed docs, but missing docs for new behavior and stale docs contradicted by code changes.

#### Step B: Referee Evaluation

Apply the same accept/reject evaluation as Phase 4. Read the relevant docs and code yourself.

| Decision | When to use | Effect |
|----------|-------------|--------|
| **Accept** (default) | Finding has merit — you verified by reading the docs/code | Include in addresser action plan at the reviewer's original severity |
| **Reject** | Finding is incorrect, irrelevant, or demands docs for trivial changes | Exclude from action plan; record your reasoning |

**If zero findings survive filtering**, post a brief PR comment — `"Docs Compliance Gate: no actionable findings — proceeding to verification."` — then skip to Phase 5.

#### Step C: Post Referee Decisions & Invoke Addresser

Write referee decisions to a temporary Markdown file and post them with `gh pr comment <number> --body-file <path>`:

```md
## Docs Compliance Gate Round <N> — Referee Decisions

| # | Finding | Reviewer Severity | Decision | Reasoning |
|---|---------|-------------------|----------|-----------|
| 1 | <brief description> | Action Required / Recommended / Minor | Accept / Reject | <why> |
| ... | ... | ... | ... | ... |

**Findings forwarded to addresser:** <count>
```

Write findings to a temp file and invoke the addresser:

```md
# Docs Compliance Findings — Round <N>

| # | Finding | Severity | Details |
|---|---------|----------|---------|
| 1 | <description> | <severity> | <file:line + what to fix> |
| ... | ... | ... | ... |
```

Delegate to a subagent using `implement-address` in Claude Code or `$implement-lifecycle:implement-address` in Codex, with `<pr-number> docs-<round-number> /tmp/implement-docs-findings-pr-<PR>-round-<N>.md`.

#### Step D: Evaluate Continuation

Re-invoke the docs reviewer to verify fixes. The round counter starts from round 1 (independent of Phase 4 rounds). Loop until clean. **Same 10-round escalation limit as Phase 4** — if docs review does not converge, escalate with the same format.

---

### Phase 5: Manual Verification Gate

After the review loop completes, invoke the verification agent to test the PR's changes with real-world execution before merging:

Delegate to a subagent using `verify` in Claude Code or `$implement-lifecycle:verify` in Codex, with `<pr-number>`.

The verification agent will classify the change type, devise a verification plan, execute it, and report structured evidence. If the verdict is **FAIL**, address the issues (invoke the addresser or fix directly) and re-verify. If **PASS** or **N/A**, proceed to Phase 6.

---

### Phase 6: Merge & Finalize

Use `merge-pr` in Claude Code or `$implement-lifecycle:merge-pr` in Codex with `<pr-number>` in the main thread. Merging is an external state change, so honor the current client's approval and repository-policy requirements.

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
