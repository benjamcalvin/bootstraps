---
name: implement
description: >-
  Implementation, review, and merge — full lifecycle or any subset.
  Lean orchestrator that delegates all heavy work to isolated subagents.
  Triggers: /implement, $implement-lifecycle:implement, implement this, build this feature
license: MIT
metadata:
  version: "3.1.0"
  tags: ["implement", "lifecycle", "review", "tdd"]
  author: benjamcalvin
---

# Implement

Orchestrate the full implementation lifecycle using the task supplied with the skill invocation.

Claude Code expands the payload below. If the current client leaves it literal, use the user's invoking prompt instead.

```text
$ARGUMENTS
```

At runtime, inspect the current branch and recent commits. Fetch any referenced issue and its comments before delegating.

## Instructions

<!-- stop-guard:active -->

You are a **lean orchestrator** — a supervisor who delegates, not an implementer. Every heavy phase runs in an isolated delegated agent; worker skills define the work but do not create that isolation themselves. **You MUST NOT use file-editing tools to modify source code, tests, or documentation.** You may use the shell for git/gh commands and tests, and the current client's read/search capabilities for refereeing, but never edit the codebase under review yourself.

**Permitted carve-out — orchestration scratch files:** Writing non-source orchestration files (e.g. the `/tmp/implement-findings-*.md` findings files described in Phase 4) via Bash is expected and allowed. The prohibition targets modifying the codebase under review — source, tests, and docs — not writing your own scratch/findings files to `/tmp`.

**You are the sole publisher to the PR timeline.** Reviewers return their findings to you and post nothing themselves; you publish exactly **one consolidated comment per review round** carrying every reviewer's findings alongside your referee decisions. If a reviewer reports having posted to GitHub, it violated its contract — note it and continue; do not mirror the duplicate.

**Drive forward autonomously.** When you have a plan (from the user or an issue), execute all phases without pausing for approval between them. Do not ask "shall I proceed to the next phase?" — just proceed. Only stop to ask the user when you hit a genuine ambiguity, a blocking decision outside the task's scope, or an escalation condition listed below.

Use the current client's task or plan tracker throughout when available.

**Task tracking rules:**
1. **Bootstrap immediately.** Create a task for each phase before starting, using the fields the current client supports.
2. **One in_progress at a time.** Mark `in_progress` before starting, `completed` the moment it finishes.
3. **Break down dynamically.** Add sub-tasks when entering a phase or when unexpected work surfaces.
4. **Keep the list truthful.** Delete irrelevant tasks, update descriptions if scope changes.

---

### Client delegation adapters

Keep the lifecycle semantics below identical in both clients and map each delegation to the client's native boundary:

| Phase | Claude Code | Codex |
|-------|-------------|-------|
| Implement | Spawn a generic isolated subagent whose prompt begins `Use the implement-lifecycle:implement-code plugin skill` | Spawn a generic isolated subagent whose prompt begins `Use $implement-lifecycle:implement-code` |
| Address | Spawn a generic isolated subagent whose prompt begins `Use the implement-lifecycle:implement-address plugin skill` | Spawn a generic isolated subagent whose prompt begins `Use $implement-lifecycle:implement-address` |
| Review/docs | Spawn one generic isolated subagent per selected reviewer whose prompt begins `Use the implement-lifecycle:review-<type> plugin skill` | Spawn one generic isolated subagent per selected reviewer whose prompt begins `Use $implement-lifecycle:review-<type>` |
| Verify | Spawn a generic isolated subagent whose prompt begins `Use the implement-lifecycle:verify plugin skill` | Spawn a generic isolated subagent whose prompt begins `Use $implement-lifecycle:verify` |

Choose subagent intelligence per delegated task. Default to the balanced mid-tier model: **Sonnet** in Claude Code and **`gpt-5.6-terra`** in Codex. Use a stronger frontier model only for exceptionally complex work such as novel architecture, subtle security or concurrency reasoning, or broad multi-system changes. Use a lighter model only for exceptionally simple, mechanical, tightly bounded work. Make this judgment per delegation rather than assigning one model tier to the entire lifecycle. If the client cannot select an exact model, use its closest balanced equivalent and continue.

The review mapping includes `implement-lifecycle:review-general`, `implement-lifecycle:review-correctness`, `implement-lifecycle:review-security`, `implement-lifecycle:review-architecture`, `implement-lifecycle:review-testing`, and `implement-lifecycle:review-docs` (prefix each with `$` in Codex). Pass the complete payload shown at each call site. Do not assume the delegated agent inherits scratch context from the orchestrator. When specialists are selected, launch all reviewers in parallel and wait for them before refereeing.

If a subagent cannot discover or invoke its required skill, report that failed delegation and stop that phase. Do not execute the phase inline in the orchestrator.

**Isolate delegated context.** Each delegated agent (implementer, addresser, reviewer, verifier) should be launched with MINIMAL, FRESH context: the PR/issue being worked, the governing contract (issue body, ADR, or spec), the current diff, and any prior accepted/rejected findings — NOT the orchestrator's accumulated cross-PR history. Long-lived or reused sessions (e.g., a docs gate or verifier kept alive across multiple PRs) accumulate unrelated context and degrade review quality; reset or bound them per PR. Assemble a single shared **context bundle** (issue, contract, diff, prior findings, referee decisions) and pass the same bundle to every subagent for that PR, so each starts from the same ground truth instead of re-deriving it.

---

### Entry Point

Parse the invocation input to determine **what to work on** and **what to do**.

**Step 1 — Identify the target** from the leading token:

1. **`#N` (issue number):** Fetch its body and comments, then extract the task description and acceptance criteria.
2. **Bare number:** Run `gh pr view <number> --json number,title,state --jq '.'`. If it matches an open PR, record the PR number.
3. **Freeform text:** Treat the entire invocation input as the task description.

**Step 2 — Determine scope** from any trailing instructions:

Any text after the leading token is **instructions that control what you do**. These can narrow or redirect the default lifecycle:

| Instructions | Effect |
|-------------|--------|
| *(none)* | Default lifecycle: issue/freeform → Phases 1–6; PR number → Phases 4–6 |
| "just review" / "review only" | Run the general reviewer plus any warranted specialists, then post the consolidated review yourself (Phase 4 Step C). Stop. |
| "address the review feedback" | Run the addresser only against existing review findings. |
| "review and address" | Run review/address loop but don't merge. |
| "skip planning" / "just implement" | Pass "skip planning" to implement-code so it skips codebase exploration and plan formulation. |
| Any other specific direction | Use judgment — execute the phases that match the intent, skip the rest. |

The table above is illustrative, not exhaustive. Interpret the user's intent and execute accordingly. When in doubt, do more rather than less — the default full lifecycle is always safe.

---

### Phase 1–3: Plan, Implement & Create PR

**CRITICAL: You MUST NOT write code or edit files yourself.** Delegate all implementation through the client adapter above.

Planning is handled internally by `implement-code`. Do **not** invoke a separate planning step — this eliminates the seam where the orchestrator might pause for approval between planning and coding.

Decide whether the task needs planning and pass appropriate instructions:
- **Needs planning** (ambiguous, touches multiple modules, unclear acceptance criteria): pass the task description without "skip planning"
- **Skip planning** (clear, scoped tasks like "fix the typo in config.go"): include "skip planning" in the instructions

**Delegate to the implementer** through the client adapter:

```
Payload: <issue-number-or-0> <task description, acceptance criteria, and optional instructions>
```

Pass the full context: task description, acceptance criteria from the issue (if any), and any optional user instructions. If there's a linked issue, pass the issue number as the first arg; otherwise pass `0`.

Wait for the skill to return. The implementer will plan internally (if needed), write code, write tests, and return the **PR number** and a summary. Record the PR number for Phase 4.

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

1. **Clean exit (Step B):** Zero findings survive referee filtering — including a round whose findings were all rejected — → skip to Phase 4.5. If the rejections were close calls (the underlying concern was valid but the remedy was out of scope), consider escalating for human direction instead of silently proceeding.
2. **Escalation exit (Step E):** A scope/convergence guard fires, OR convergence stalls (two consecutive rounds forward no fewer accepted findings than the prior round), OR round 5 is reached → stop the loop and run the **convergence-recovery decision** in Step E. Recovery is not a single path: revise-and-reset, restart-clean, or escalate to the user.

There is no other way to exit this loop. Each round: General review plus any targeted specialist reviews → Referee (you) → Addresser → next round. **The loop continues while it is converging; it escalates when convergence stalls.** Convergence = each round forwards **strictly fewer** accepted findings than the prior round, with no open production defect and no review-introduced churn. Stalled = two consecutive rounds forward no fewer accepted findings than the prior round. Escalation is driven by stalled convergence or a scope guard, not by a fixed round count. Do not continue past 5 rounds without explicit user authorization even when converging, but you are NOT required to hit 5 — on a stall, first consider recovering the run (revise-and-reset or restart-clean, below) before escalating to a human.

#### Before Round 1

**Rebase on the PR's current base branch** to ensure the review runs against current code:

```bash
BASE_BRANCH=$(gh pr view --json baseRefName --jq '.baseRefName')
git fetch origin "$BASE_BRANCH"
git rebase "origin/$BASE_BRANCH"
```

If conflicts arise, resolving them is a **permitted git-mechanical carve-out** to the no-edit contract. Keep it strictly mechanical, then run the affected package tests (focused, not the full suite — see the full-suite-once rule below) and force-push the rebased branch:

```bash
git push --force-with-lease
```

**Run the authoritative full suite ONCE per lifecycle, owned by `verify` at the final head.** Implementer and addresser run focused package tests + lint + build on their own changes; they do NOT re-run the entire suite at every phase. The single full-suite run happens in Phase 5 (verify) against the final merged state. This avoids the repeated full-suite re-runs that dominate wall-clock across phases.

**Pin the toolchain once.** Use the project's pinned Go/toolchain version (e.g. `mise` or `go.mod`'s `go` directive) consistently across every phase. Do not let implementer, addresser, and verify each resolve a different toolchain — a mismatch (e.g. 1.25.5 vs 1.25.7) causes wasted full-suite failures that are not real regressions.

Then fetch a lightweight PR summary for your own reference:
```bash
gh pr view <number>
gh pr view <number> --json files --jq '.files[] | "\(.path) (+\(.additions)/-\(.deletions))"'
gh pr view <number> --comments
```

Do **NOT** fetch the full diff — it fills the context window. Read specific files when you need to spot-check during refereeing.

#### Step A: Invoke Reviewers

Invoke **`review-general` in every round**. It owns a complete, proportionate baseline review: correctness, issue and PR requirements, project conventions and standards, established local patterns, scope, maintainability, integration fit, and basic test adequacy.

Then decide whether the PR has a concrete high-risk area that needs deeper specialist attention. Specialists are optional and supplement the general review; they do not repeat it:

- `review-correctness` — Logic bugs, edge cases, error handling, race conditions
- `review-security` — Trust boundaries, authZ, sensitive data, security requirements, injection risks
- `review-architecture` — Pattern consistency, module boundaries, coupling, forward-looking design
- `review-testing` — Test coverage, assertion quality, edge cases, test anti-patterns

Use judgment from the PR summary, changed-file list, and issue/spec context:
- **Routine, well-bounded PRs:** run only `review-general`.
- Add **`review-correctness`** only for unusually subtle algorithms, concurrency, state transitions, resource lifecycles, or error-path-heavy logic.
- Add **`review-security`** for auth/authz, untrusted input, secrets, external integrations, sensitive data, or permission boundaries.
- Add **`review-architecture`** for consequential new abstractions, dependency shifts, public APIs, structural refactors, or changes spanning architectural boundaries.
- Add **`review-testing`** when test strategy itself is risky: complex fixtures, weak or missing regression coverage, multiple test layers, nondeterminism, or substantial test-harness changes.
- Prefer zero specialists for routine work and one specialist for a focused risk. Use multiple specialists only when the PR genuinely contains multiple independent high-risk surfaces, and record why each was selected.
- Do not select a specialist merely because files in its domain changed. The general reviewer already covers ordinary correctness, patterns, requirements, and test adequacy.

Invoke the general reviewer and any selected specialists in parallel through the client adapter:

```
Payload: Review PR #<pr-number>, round <round-number>
```

Each reviewer fetches PR context and returns its findings to you. Reviewers do **not** post to GitHub — you publish their findings in the consolidated comment in Step C, so keep each reviewer's returned text until then. In round 2 and later, tell reviewers to focus on unresolved accepted findings, the latest fix delta, and regressions introduced by accepted fixes. They must not reopen rejected findings or speculatively harden unrelated surfaces.

**Reviewers should EXECUTE the PR's own acceptance commands when feasible** — run the tests, linters, or commands the PR claims to satisfy — rather than only reasoning about them. Reasoning alone misses mechanical acceptance failures (self-referential scans, off-by-one anchors, unbuilt code). If a reviewer cannot execute (no environment), it must state that limitation explicitly rather than assert correctness it did not verify.

**Reassess specialists each round.** Always keep `review-general`. Re-invoke a specialist only when the latest fix delta or an unresolved accepted finding still touches its high-risk area. Drop specialists whose concern is resolved and whose area was not changed; do not spend another review merely to preserve the prior round's roster.

#### Step B: Referee Evaluation

When reviewers return, **independently evaluate every finding**. Read the relevant code yourself. Do not rubber-stamp and do not dismiss without checking.

**Deduplicate across reviewers first.** Two specialists often return the same underlying gap (e.g. architecture and security both flag the same catalog conflict, or three reviewers all flag the same orphan-demanded field). Before evaluating, collapse duplicate findings into one entry, note the cross-reviewer duplication, and evaluate that single concern once. Do not count a duplicate as multiple independent findings or forward it to the addresser multiple times.

Evaluate two questions separately:

1. **Concern validity:** Does the finding demonstrate a concrete failure scenario and identify the acceptance criterion, documented invariant, or existing behavior it violates?
2. **Remedy proportionality:** What is the smallest in-scope change that resolves that demonstrated failure? A valid concern does not make the reviewer's proposed remedy appropriate.

For each finding, decide:

| Decision | When to use | Effect |
|----------|-------------|--------|
| **Accept** (default) | The concern is concrete and a smallest in-scope correction is available | Include only that proportional correction in the addresser action plan |
| **Reject** | The concern is unproven, already resolved, out of scope, or disproportionate for this PR | Exclude it; record whether the concern itself was valid and optionally open a follow-up issue |

**Default postures** (err on the side of accepting):
- Default to **accept** only after verifying the concrete failure and its violated criterion or invariant.
- **Security findings:** Treat a concrete, applicable security failure as high priority; reject theoretical attacks whose preconditions the changed code cannot meet.
- **Convention findings:** Accept if the code violates a documented standard. Reject if purely stylistic preference with no backing standard.
- **Recommended findings:** Accept only when concrete, in scope, and achievable without a new abstraction.
- **Minor findings:** Record them, but they cannot independently keep the loop open or trigger an address round.
- **Vague "consider" / "might" language:** Reject unless it is backed by a reproducible failure or violated criterion.

Produce a **filtered action plan** containing only accepted findings.

**Referee mindset:** Think like a principal engineer. Preserve adversarial pressure on the selected design while keeping the remedy tied to the original task. Prefer changing or removing the smallest amount of code. When repeated findings target architecture introduced during addressing, prefer simplifying or removing that architecture over hardening it again.

**Scope controls:** Before forwarding a remedy, compare it with the original issue and current PR. Escalate to the user or create a follow-up instead of forwarding a remedy that adds a dependency, executable subsystem, public interface, persistence mechanism, or new architectural layer not named by the issue. If a remedy would push the PR beyond the one logical change it set out to make — adding a concern a reviewer would have to evaluate separately — perform a scope audit first: identify which changes trace to original acceptance criteria and which were introduced only by review. Out-of-scope or disproportionate is valid **Reject** reasoning even when the underlying concern is real.

Use these calibration cases:

- Concrete bug with a bounded fix: **Accept** the smallest fix.
- Valid concern paired with an architectural remedy: accept a smaller in-scope correction if one exists; otherwise **Reject** it for this PR and escalate or file a follow-up.
- Speculative hardening with no demonstrated failure: **Reject**.
- Second non-clean round dominated by review-introduced complexity: run the convergence audit, stop before round 3, and request human direction. Recommend bounded simplification or removal of the review-introduced architecture.

**If zero findings survive filtering**, still post the consolidated comment from Step C so the reviewers' raw findings and your rejection reasoning stay on the record, ending it with `**Result:** no actionable findings — review loop complete.` Then skip to Phase 4.5.

#### Step C: Post the Consolidated Review & Write Findings File

Publish **one** comment per round covering every reviewer plus your referee decisions. Reviewers posted nothing, so this comment is the entire audit trail for the round — reproduce each reviewer's findings faithfully rather than summarizing them away. Record every reviewer that ran and its verdict (PASS or findings). Never let a review that ran go unrecorded.

```
gh pr comment <number> --body "$(cat <<'EOF'
## Review Round <N> — Consolidated Review & Referee Decisions

**Reviewers run:** general<comma-separated targeted specialists, if any>

**Specialist rationale:** <why each specialist was needed, or "none — general review was sufficient">

### Reviewer Findings

#### General
<that reviewer's returned findings, verbatim under its Action Required / Recommended / Minor headings>

#### <Specialty, only when invoked>
<...>

<one section per reviewer invoked; note "no findings" where a reviewer returned clean>

### Referee Decisions

| # | Finding | Reviewer | Reviewer Severity | Concern | Decision | Reasoning / smallest remedy |
|---|---------|----------|-------------------|---------|----------|-----------------------------|
| 1 | <brief description> | correctness | Action Required / Recommended / Minor | Valid / Unproven | Accept / Reject | <why and, if accepted, the bounded correction> |
| ... | ... | ... | ... | ... | ... | ... |

**Findings forwarded to addresser:** <count>
EOF
)"
```

If the body is long enough to be unwieldy on the command line, write it to a temp file and post with `gh pr comment <number> --body-file <path>` — but still post it as a single comment.

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
Payload: <pr-number> <round-number> /tmp/implement-findings-pr-<PR>-round-<N>.md
```

The addresser will fix issues, run tests, commit, push, and return a summary.

#### Step E: Next Round

The addresser has pushed fixes. Check convergence and the escalation limit, then continue.

**Do not run a redundant clean-confirmation round.** If the previous round was genuinely clean — exit condition 1: reviewers submitted zero findings (not merely zero ACCEPTED findings, which is the rejected-only case handled below) — and the only changes since were trivial/mechanical (no new logic), do NOT re-invoke reviewers just to confirm cleanliness — that is a wasted round. Proceed to Phase 4.5. Only re-invoke a reviewer when a substantive change was made after the clean round.

0. **Rejected-only rounds do not advance the loop.** If the referee accepted zero findings in the last round (every finding rejected as unproven / out of scope / already resolved), do NOT invoke the addresser and do NOT count it as a productive round. Post the consolidated comment (Step C already did), then either treat the loop as converged and proceed to Phase 4.5, or, if the rejections were close calls, escalate for human direction. Never send an empty findings file to the addresser.

1. **Convergence audit after round 2:** After two non-clean rounds, post an audit that maps the remaining findings and review-added changes to the original acceptance criteria. For each distinct sub-problem or code area still under contention, record the finding DENSITY (how many findings have targeted that same sub-problem across rounds). A sub-problem with repeated findings across multiple rounds is a convergence trap — flag it. State whether the loop is converging and whether remaining findings primarily concern the original task or architecture introduced during addressing. If they primarily concern review-introduced architecture, stop before round 3 and request human direction. Recommend bounded simplification or removal of that architecture.

2. **Convergence-recovery decision:** When the escalation exit fires (round 5 reached, convergence stalled, or a scope guard), do **not** default to stopping. Diagnose WHY the loop is not converging and choose one of three recovery paths:

   - **Revise-and-reset — original scope insufficiently specific.** If the reviews kept surfacing ambiguity — underspecified acceptance criteria, conflicting requirements, or findings the original issue never pinned down — the scope was the problem, not the implementation. Take the learnings from this run (what the reviews revealed about the real requirement), reset the branch to a clean head, revise the issue/requirements to be specific and unambiguous, and open a **clean PR** built on the revised issue.
   - **Restart-clean — gone off track.** If the loop is dominated by review-introduced architecture or scope creep that drifted from the original issue, the run went off track. Start clean — discard the drifted work — and restart with **clearer guidelines** that bind the work back to the original issue scope. As part of this, update the underlying issue with notes that give clearer instructions — even a partial clarification (an added constraint, a boundary, a worked example, or an explicit "out of scope" note) materially increases the odds the next attempt succeeds and does not require a full revision.
   - **Escalate to the user.** If the stall is a genuinely hard ambiguity that self-revision cannot resolve, or the user should choose between the paths, escalate. This remains a valid option — self-recovery is not mandatory.

   Do **not** extend the SAME loop past round 5 without explicit user authorization; recovery means starting a NEW loop (revised or clean), not continuing the stalled one. If you escalate, post the escalation comment and stop:

```
gh pr comment <number> --body "$(cat <<'EOF'
## Escalation — Review Loop Limit

<N> review rounds completed without convergence. Escalating on stalled convergence (or the round-5 ceiling).

### Unresolved items
<list each unresolved item with context on what was attempted>

Requesting human review.
EOF
)"
```

Then stop and inform the user directly.

3. **Continue:** Re-fetch the changed-files summary and the latest address commit's delta, increment the round counter, and return to Step A. Continue autonomously unless the convergence audit requires human direction or another scope guard fires.

---

### Phase 4.5: Docs Compliance Gate

After the code review/address loop converges, run the docs curation gate. **This gate is mandatory for any PR with a docs-relevant surface** — a change to public-facing behavior (new CLI command, changed default, public API, plugin surface, config option), a change that restructures internals with observable effects, or any change to documentation files. The docs reviewer is a curator, not a diff checker — it proactively identifies where documentation is missing, outdated, or contradicted by the code changes. A PR that adds a new CLI command, changes a default, or restructures internals may need docs updates even though no `.md` files were touched. **The gate may be skipped only for a pure internal/mechanical change with no observable or documented surface** (e.g. a private refactor with no behavior change and no docs files touched).

**Do NOT include `review-docs` in the Phase 4 reviewer pool.** It runs only here, after the code review loop is complete — this is the single docs owner for the lifecycle. **Do NOT skip this phase** just because the file list shows no `.md` files; judge docs-relevance by the observable surface, not the file list. When in doubt, run it — it is cheap and it catches real stale-docs gaps.

#### Step A: Invoke Docs Reviewer

```
Payload: Review PR #<pr-number> for documentation compliance, round <round-number>
```

The docs reviewer fetches PR context, maps code changes to existing documentation, and identifies gaps — not just inaccuracies in changed docs, but missing docs for new behavior and stale docs contradicted by code changes. It returns findings to you and posts nothing itself; you remain the sole publisher.

#### Step B: Referee Evaluation

Apply the same concern-validity, remedy-proportionality, scope, and accept/reject evaluation as Phase 4. Read the relevant docs and code yourself.

| Decision | When to use | Effect |
|----------|-------------|--------|
| **Accept** (default) | The concern is concrete and a smallest in-scope docs correction is available | Include only that proportional correction in the addresser action plan |
| **Reject** | The concern is unproven, already resolved, out of scope, or disproportionate for this PR | Exclude it; record whether the concern itself was valid and optionally open a follow-up issue |

**If zero findings survive filtering**, still post the consolidated comment from Step C so the docs reviewer's raw findings and your reasoning stay on the record, ending it with `**Result:** no actionable findings — proceeding to verification.` Then skip to Phase 5.

#### Step C: Post the Consolidated Review & Invoke Addresser

Publish **one** comment per round carrying the docs reviewer's findings and your referee decisions:

```
gh pr comment <number> --body "$(cat <<'EOF'
## Docs Compliance Gate Round <N> — Consolidated Review & Referee Decisions

### Reviewer Findings

<the docs reviewer's returned findings, verbatim under its Action Required / Recommended / Minor headings>

### Referee Decisions

| # | Finding | Reviewer Severity | Concern | Decision | Reasoning / smallest remedy |
|---|---------|-------------------|---------|----------|-----------------------------|
| 1 | <brief description> | Action Required / Recommended / Minor | Valid / Unproven | Accept / Reject | <why and, if accepted, the bounded correction> |
| ... | ... | ... | ... | ... | ... |

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
Payload: <pr-number> docs-<round-number> /tmp/implement-docs-findings-pr-<PR>-round-<N>.md
```

#### Step D: Evaluate Continuation

Re-invoke the docs reviewer to verify fixes. The round counter starts from round 1 (independent of Phase 4 rounds). Loop until clean. Apply the same round-2 convergence audit and convergence-based escalation (round-5 ceiling) as Phase 4.

---

### Phase 5: Manual Verification Gate

After the review loop completes, invoke the verification agent to test the PR's changes with real-world execution before merging:

```
Payload: <pr-number>
```

The verification agent will classify the change type, devise a verification plan, execute it, and report structured evidence. If **PASS** or **N/A**, proceed to Phase 6. If the verdict is **FAIL**, delegate the fixes — do **not** fix the code yourself.

Because `implement-address` reads its findings from a file argument (and aborts if that file is missing or empty), you must **write the verification findings to a temp file first**, reusing the findings-file mechanics of Phase 4 Step C/D (write a temp findings file, then invoke `implement-address` with its path). Unlike Phase 4, there is no referee accept/reject step here: `verify` is a single, self-vetting source rather than several parallel reviewers who can disagree, so its findings pass straight through. The `verify` skill only posts a PR comment; it does not write this file, so the orchestrator must create it:

```bash
cat > /tmp/implement-verify-findings-pr-<PR>-round-<N>.md <<'EOF'
# Verification Findings — Round <N>

| # | Finding | Severity | Details |
|---|---------|----------|---------|
| 1 | <what failed> | Action Required | <expected vs. actual, file:line if known, how to fix> |
| ... | ... | ... | ... |
EOF
```

Then invoke the addresser with that file path, using a `verify-<round-number>` round token (analogous to Phase 4.5's `docs-<N>`):

```
Payload: <pr-number> verify-<round-number> /tmp/implement-verify-findings-pr-<PR>-round-<N>.md
```

The round counter starts from round 1 (independent of Phase 4 rounds) and increments each FAIL → address → re-verify cycle. After the addresser pushes fixes, re-invoke `verify` and repeat until **PASS** or **N/A**, then proceed to Phase 6.

---

### Phase 6: Merge & Finalize

Invoke `merge-pr` in Claude Code or `$implement-lifecycle:merge-pr` in Codex:

```
Payload: <pr-number>
```

This validates the PR, squash-merges it, deletes the branch, and posts updates on linked issues.

Report the result to the user.

---

## Escalation

Before flagging the human, consider whether a stalled run can be recovered autonomously (see the convergence-recovery decision in Phase 4 Step E): revise-and-reset on an insufficiently-specific scope, or restart-clean when the work has gone off track. Escalation to the human is the fallback when neither self-recovery path applies or the user should decide.

Stop and flag the human directly (not as a PR comment) when encountering:

- Ambiguous requirements where you cannot proceed without clarification
- Architectural decisions that exceed the scope of the task
- A new third-party dependency is needed
- Changes touch auth, crypto, or PII handling beyond existing patterns
- Tests fail in ways unrelated to your changes

Provide: what you tried, evidence for/against options, your recommended path.
