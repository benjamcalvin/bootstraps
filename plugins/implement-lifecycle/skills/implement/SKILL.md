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

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Run focused tests, lint, builds, and acceptance commands only. Do not execute or consume the target repository's authoritative verification command or ordered command plan. Final verification owns that evidence.**

Orchestrate the full implementation lifecycle using the task supplied with the skill invocation.

The active harness expands the payload below. If it leaves the payload literal, use the user's invoking prompt instead.

```text
$ARGUMENTS
```

At runtime, inspect the current branch and recent commits. Fetch any referenced issue and its comments before delegating.

## Instructions

<!-- stop-guard:active -->

You are a **lean orchestrator** — a supervisor who delegates, not an implementer. Every heavy phase runs in an isolated delegated agent; worker skills define the work but do not create that isolation themselves. **You MUST NOT use file-editing tools to modify source code, tests, or documentation.** You may use the shell for git/gh commands and tests, and the current client's read/search capabilities for refereeing, but never edit the codebase under review yourself.

**Permitted carve-out — orchestration scratch files:** Writing non-source orchestration files for findings handoff is expected and allowed. Resolve a writable scratch location through the harness when it provides one; otherwise ask the operating system to create a temporary file or directory. Record each resolved path and pass it explicitly to the receiving worker. The prohibition targets modifying the codebase under review — source, tests, and docs — not writing orchestration scratch files.

**You are the sole publisher to the PR timeline.** Reviewers return their findings to you and post nothing themselves; you publish exactly **one consolidated comment per review round** carrying every reviewer's findings alongside your referee decisions. If a reviewer reports having posted to GitHub, it violated its contract — note it and continue; do not mirror the duplicate.

**Drive forward autonomously.** When you have a plan (from the user or an issue), execute all phases without pausing for approval between them. Do not ask "shall I proceed to the next phase?" — just proceed. Only stop to ask the user when you hit a genuine ambiguity, a blocking decision outside the task's scope, or an escalation condition listed below.

Use the current client's task or plan tracker throughout when available.

**Task tracking rules:**
1. **Bootstrap immediately.** Create a task for each phase before starting, using the fields the current client supports.
2. **One in_progress at a time.** Mark `in_progress` before starting, `completed` the moment it finishes.
3. **Break down dynamically.** Add sub-tasks when entering a phase or when unexpected work surfaces.
4. **Keep the list truthful.** Delete irrelevant tasks, update descriptions if scope changes.

### Harness-neutral delegation

The lifecycle maps each heavy phase to one canonical worker skill:

| Phase | Canonical skill | Model tier |
|-------|-----------------|------------|
| Implement | `implement-code` | `balanced`; `frontier` when pre-classified large or risky (Tier classification) |
| Address | `implement-address` | `balanced` |
| Review general | `review-general` | `balanced` |
| Review correctness | `review-correctness` | `balanced` |
| Review security | `review-security` | `balanced` |
| Review architecture | `review-architecture` | `balanced` |
| Review testing | `review-testing` | `balanced` |
| Review docs | `review-docs` | `balanced` |
| Verify | `verify` | `balanced` |

For every delegation, use the adapter for the active harness to create a fresh isolated child, explicitly select the mapped canonical skill, pass the complete payload and context bundle, and return the child's result to the orchestrator. Each delegation requests its role's tier; adapters map tiers to concrete models. Never silently inherit the orchestrator's model for a `balanced` role. The referee stays with the orchestrator and is not delegated. Wait for child completion results; do not poll, sleep, or schedule wake-ups to check on children.

**Claude Code adapter.** Spawn a generic isolated subagent whose prompt begins `Use the implement-lifecycle:<skill> plugin skill`, followed by the complete payload and fresh context bundle. Pass the Agent tool's `model` parameter explicitly: `"sonnet"` for `balanced`; omit it (inherit) for `frontier`.

**Codex adapter.** Spawn a generic isolated subagent whose prompt begins `Use $implement-lifecycle:<skill>`, followed by the complete payload and fresh context bundle. Map `balanced` to the harness's balanced/default coding model and `frontier` to its strongest model.

**Pi adapter.** With the user-installed `pi-subagents` prerequisite available, launch a generic `delegate` child with `skill: <skill>`, `context: "fresh"`, and the complete payload and fresh context bundle. Never rely on the delegate default for context freshness. Map `balanced` to the delegate's balanced model and `frontier` to its strongest. Do not use or distribute custom Pi agent definitions.

**Generic adapter.** A compatible harness must create a fresh isolated child, load the mapped Agent Skill explicitly, pass the complete payload and fresh context bundle, and return the child result. A harness that cannot provide isolated delegation or load the required skill must report the failed phase and must not execute it inline. Map `balanced` and `frontier` to the closest available balanced and strongest models.

When specialists are selected, every adapter launches the selected reviewers in parallel and waits for all their results before refereeing.

Selected Pi reviewers remain parallel, read-only children. Each delegation explicitly names its canonical `skill`, sets `context: "fresh"`, and captures the child's final result. A reviewer result is complete only when it is non-empty and contains all four canonical headings: `### Action Required`, `### Recommended`, `### Minor`, and `### Summary`. Do not referee an empty, missing, or structurally incomplete result.

The reviewer-result recovery contract is this exact state graph:

<!-- lifecycle-reviewer-recovery:v1
delegated + nonempty-canonical-result -> complete
delegated + empty-or-incomplete-result -> incomplete
incomplete + transcript-recovery-complete -> complete
incomplete + transcript-recovery-incomplete -> fresh-retry
incomplete + transcript-recovery-unavailable -> fresh-retry
fresh-retry + nonempty-canonical-result -> complete
fresh-retry + empty-or-incomplete-result -> stop
complete + referee -> refereeing
-->

On an incomplete result, first recover the final captured result from the harness transcript when available. If recovery is unavailable or still incomplete, retry once in a new child with the same canonical skill and `context: "fresh"`. If that retry is incomplete, stop the phase and report the failed delegation. Only the `complete` state may enter refereeing.

**Isolate delegated context.** Launch each delegated agent (implementer, addresser, reviewer, verifier) with MINIMAL, FRESH context, not the orchestrator's accumulated history. Assemble one **context bundle** per PR and pass it to every child: issue, governing contract, prior accepted/rejected findings and referee decisions, and for round N ≥ 2 the delta range `<head reviewed in round N-1>..<current head>`. Children start from the bundle instead of re-fetching the full PR comment history. Reset or bound long-lived sessions per PR.

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
| "just review" / "review only" | Classify the tier, run Step A's mechanical selection, post the consolidated review (Step C). Stop. |
| "address the review feedback" | Run the addresser only against existing review findings. |
| "review and address" | Run review/address loop but don't merge. |
| "skip planning" / "just implement" | Pass "skip planning" to implement-code so it skips codebase exploration and plan formulation. |
| Any other specific direction | Use judgment — execute the phases that match the intent, skip the rest. |

The table above is illustrative, not exhaustive. Interpret the user's intent and execute accordingly. When in doubt, do more rather than less — the default full lifecycle is always safe.

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

### Tier classification

**Pre-classification (before the implementer).** Judge from the issue/task whether the work is likely large or touches a risk surface; that selects only the implementer's model tier.

**Authoritative classification (once the PR exists).** Start from the measured result only; the implementer's report may raise it. Count changed lines (additions + deletions, excluding lockfiles and generated files) and inspect changed paths:

| Tier | Trigger |
|------|---------|
| Small | ≤ 400 changed lines and no risk surface |
| Large | > 1,500 changed lines, or any risk surface |
| Medium | Neither Small nor Large |

Any risk surface makes the PR Large regardless of size.

**Risk surface:** the target repository's declared list when present; otherwise authentication/authorization, secrets/credentials/crypto, data migrations/schema, CI/deploy configuration, sandbox/permission boundaries. Repository policy may override the thresholds. The implementer's report may escalate the tier; nothing may lower it. Record tier and reason in the round-1 consolidated comment.

### Phase 4: Review/Address Loop {#review-loop}

**This is a bounded loop.** It repeats Steps A → B → C → D → E per round, capped by tier:

| Tier | Max review rounds | Follow-up rounds |
|------|-------------------|------------------|
| Small | 1 | None: the addresser fixes and runs focused tests; no re-review |
| Medium | 2 | Round 2 only if round 1 accepted ≥ 1 Action Required or Recommended finding; Minor-only exits |
| Large | 3 | Delta-only; the convergence audit after round 2 still applies |

Exit when:

1. **Clean exit (Step B):** no accepted findings (including a round whose findings were all rejected), or only accepted Minor findings (one batch pass; no new round) → Phase 5. If rejections were close calls, consider escalating for human direction.
2. **Cap exit:** at the tier cap the addresser fixes the final round's accepted findings and runs focused tests; if it reports any Action Required unresolved → escalation exit; otherwise → Phase 5.
3. **Escalation exit (Step E):** a scope/convergence guard fires, or Large convergence stalls (evaluated after round 2: round 2 accepted no fewer findings than round 1; after round 3, no fewer than round 2), or the cap exit reports unresolved Action Required → run the **convergence-recovery decision** in Step E.

Convergence = each round forwards fewer accepted findings than the prior, with no open production defect and no review-introduced churn. Never exceed the tier cap without explicit user authorization.

#### Before Round 1

**Rebase on the PR's current base branch** to ensure the review runs against current code:

```bash
BASE_BRANCH=$(gh pr view --json baseRefName --jq '.baseRefName')
git fetch origin "$BASE_BRANCH"
git rebase "origin/$BASE_BRANCH"
```

If conflicts arise, resolving them is a **permitted git-mechanical carve-out** to the no-edit contract. Keep it strictly mechanical, then run focused tests for the affected packages and force-push the rebased branch:

```bash
git push --force-with-lease
```

The orchestrator does not execute verification's authoritative suite. It hands the exact current PR head and any durable evidence for that same head to `verify`; all earlier phases remain focused-only.

**Pin the toolchain once.** Discover the target repository's pinned runtime, compiler, package manager, and toolchain from its governing instructions and project configuration, then use those exact selections consistently across every phase. Do not let implementer, addresser, and verify resolve different toolchain versions; version drift creates failures that are not real regressions.

Then fetch a lightweight PR summary for your own reference:
```bash
gh pr view <number>
gh pr view <number> --json files --jq '.files[] | "\(.path) (+\(.additions)/-\(.deletions))"'
gh pr view <number> --comments
```

Do **NOT** fetch the full diff — it fills the context window. Read specific files when you need to spot-check during refereeing.

#### Step A: Invoke Reviewers

Invoke **`review-general` in every round**. It owns a complete baseline review: correctness, requirements, conventions, local patterns, scope, maintainability, integration fit, and basic test adequacy.

Specialists are selected mechanically by tier and path trigger, not by discretion:

- **Any tier:** `review-docs` when docs, specs, READMEs, or user-facing interfaces (CLI flags, public APIs, config keys) change, when the change alters architecture, conventions, or behavior described in AGENTS.md, ADRs, or other project docs, or when the tier is Large.
- **Small/Medium:** `review-general` only, plus `review-docs` per the trigger above.
- **Large:** `review-general` plus `review-docs` and each specialist whose trigger fires:
  - `review-security` — auth, secrets, crypto, sandbox, or permission paths change
  - `review-correctness` — migrations, concurrency primitives, or CI/deploy configuration change
  - `review-architecture` — a new top-level module/package or public interface is added
  - `review-testing` — production code changes without corresponding test changes
- **Follow-up rounds (N ≥ 2):** `review-general` only, plus a specialist or `review-docs` only when its own accepted finding is unresolved; re-include `review-docs` also when the fix delta changes documented behavior.

Invoke the selected reviewers in parallel through the client adapter:

```
Payload: Review PR #<pr-number>, round <round-number>[, delta <prev-reviewed-head>..<current-head>]
```

Each reviewer fetches PR context and returns its findings to you; reviewers do **not** post to GitHub. Keep each returned text for Step C. In round N ≥ 2 the payload carries the delta range and prior referee decisions (context bundle). Follow-up reviewers judge only that range: did the fixes resolve the accepted findings, and did they introduce regressions? They must not reopen rejected findings or review code outside the delta.

**Reviewers should execute the PR's own focused acceptance commands when feasible** — focused tests, linters, or commands the PR claims to satisfy — rather than only reasoning about them. They must follow their `focused-only` capability. Reasoning alone misses mechanical acceptance failures (self-referential scans, off-by-one anchors, unbuilt code). If a reviewer cannot execute (no environment), it must state that limitation explicitly rather than assert correctness it did not verify.

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
- **Minor findings:** They never open a round. Accepted Minors go to the addresser with other accepted findings, or alone in one batch pass when they are the only accepted findings (no new round).
- **Out of delta (round N ≥ 2):** Reject findings about code outside the round's delta as "out of delta" and record them as follow-up items for the final report; they never open a round.
- **Vague "consider" / "might" language:** Reject unless it is backed by a reproducible failure or violated criterion.

Produce a **filtered action plan** containing only accepted findings.

**Referee mindset:** Think like a principal engineer. Preserve adversarial pressure on the selected design while keeping the remedy tied to the original task. Prefer changing or removing the smallest amount of code. When repeated findings target architecture introduced during addressing, prefer simplifying or removing that architecture over hardening it again.

**Scope controls:** Before forwarding a remedy, compare it with the original issue and current PR. Escalate to the user or create a follow-up instead of forwarding a remedy that adds a dependency, executable subsystem, public interface, persistence mechanism, or new architectural layer not named by the issue. If a remedy would push the PR beyond the one logical change it set out to make — adding a concern a reviewer would have to evaluate separately — perform a scope audit first: identify which changes trace to original acceptance criteria and which were introduced only by review. Out-of-scope or disproportionate is valid **Reject** reasoning even when the underlying concern is real.

Use these calibration cases:

- Concrete bug with a bounded fix: **Accept** the smallest fix.
- Valid concern paired with an architectural remedy: accept a smaller in-scope correction if one exists; otherwise **Reject** it for this PR and escalate or file a follow-up.
- Speculative hardening with no demonstrated failure: **Reject**.
- Second non-clean round dominated by review-introduced complexity: run the convergence audit, stop before round 3, and request human direction. Recommend bounded simplification or removal of the review-introduced architecture.

**If zero findings survive filtering**, still post the consolidated comment from Step C so the reviewers' raw findings and your rejection reasoning stay on the record, ending it with `**Result:** no actionable findings — review loop complete.` Then skip to Phase 5. If only Minor findings were accepted, post the comment, have the addresser batch them in one pass, and skip to Phase 5 without a new round.

#### Step C: Post the Consolidated Review & Write Findings File

Publish **one** comment per round covering every reviewer plus your referee decisions. Reviewers posted nothing, so this comment is the entire audit trail for the round — reproduce each reviewer's findings faithfully rather than summarizing them away. Record every reviewer that ran and its verdict (PASS or findings). Never let a review that ran go unrecorded.

```
gh pr comment <number> --body "$(cat <<'EOF'
## Review Round <N> — Consolidated Review & Referee Decisions

**Reviewers run:** general<comma-separated specialists and `review-docs`, if any>

**Tier:** <Small/Medium/Large + reason; round 1 only>

**Specialist rationale:** <the trigger for each specialist and for `review-docs`, or "none — tier/triggers did not call for one">

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
cat > <resolved-findings-path> <<'EOF'
# Filtered Findings — Round <N>

| # | Finding | Severity | Details |
|---|---------|----------|---------|
| 1 | <description> | <severity> | <file:line + what to fix> |
| ... | ... | ... | ... |
EOF
```

#### Step D: Invoke Addresser

```
Payload: <pr-number> <round-number> <resolved-findings-path>
```

The addresser will fix issues, run tests, commit, push, and return a summary.

#### Step E: Next Round

The addresser has pushed fixes. Apply the tier cap and convergence checks, then continue or exit.

**Do not run a redundant clean-confirmation round.** After a genuinely clean round (zero reviewer findings) with only trivial follow-up changes, proceed to Phase 5 without re-invoking reviewers.

0. **Rejected-only rounds do not advance the loop.** If the referee accepted zero findings in the last round (every finding rejected as unproven / out of scope / already resolved), do NOT invoke the addresser and do NOT count it as a productive round. Post the consolidated comment (Step C already did), then either treat the loop as converged and proceed to Phase 5, or, if the rejections were close calls, escalate for human direction. Never send an empty findings file to the addresser.

1. **Convergence audit after round 2 (Large):** After two non-clean rounds, post an audit that maps the remaining findings and review-added changes to the original acceptance criteria. For each distinct sub-problem or code area still under contention, record the finding DENSITY (how many findings have targeted that same sub-problem across rounds). A sub-problem with repeated findings across multiple rounds is a convergence trap — flag it. State whether the loop is converging and whether remaining findings primarily concern the original task or architecture introduced during addressing. If they primarily concern review-introduced architecture, stop before round 3 and request human direction. Recommend bounded simplification or removal of that architecture.

2. **Convergence-recovery decision:** When the escalation exit fires (tier cap reached unresolved, convergence stalled, or a scope guard), do **not** default to stopping. Diagnose WHY the loop is not converging and choose one of three recovery paths:

   - **Revise-and-reset — original scope insufficiently specific.** If the reviews kept surfacing ambiguity — underspecified acceptance criteria, conflicting requirements, or findings the original issue never pinned down — the scope was the problem, not the implementation. Take the learnings from this run (what the reviews revealed about the real requirement), reset the branch to a clean head, revise the issue/requirements to be specific and unambiguous, and open a **clean PR** built on the revised issue.
   - **Restart-clean — gone off track.** If the loop is dominated by review-introduced architecture or scope creep that drifted from the original issue, the run went off track. Start clean — discard the drifted work — and restart with **clearer guidelines** that bind the work back to the original issue scope. As part of this, update the underlying issue with notes that give clearer instructions — even a partial clarification (an added constraint, a boundary, a worked example, or an explicit "out of scope" note) materially increases the odds the next attempt succeeds and does not require a full revision.
   - **Escalate to the user.** If the stall is a genuinely hard ambiguity that self-revision cannot resolve, or the user should choose between the paths, escalate. This remains a valid option — self-recovery is not mandatory.

   Do **not** extend the SAME loop past the tier cap without explicit user authorization; recovery means starting a NEW loop (revised or clean), not continuing the stalled one. If you escalate, post the escalation comment and stop:

```
gh pr comment <number> --body "$(cat <<'EOF'
## Escalation — Review Loop Stopped

Review loop stopped (tier cap or stalled convergence) after <N> round(s).

### Unresolved items
<list each unresolved item with context on what was attempted>

Requesting human review.
EOF
)"
```

Then stop and inform the user directly.

3. **Continue** only if the tier cap allows another round; otherwise take the cap exit: record the delta range (`<reviewed head>..<new head>`), increment the round counter, and return to Step A. Continue autonomously unless the convergence audit requires human direction or another scope guard fires.

### Phase 5: Manual Verification Gate

After the review loop completes, invoke the verification agent with the tier; a re-verification also names the scenarios that failed:

```
Payload: <pr-number> tier=<Small|Medium|Large> [failed-scenarios=<names>]
```

The verifier scales scenarios to the tier, records exact-head suite evidence (executed or matching CI), and compares suite failures against the merge-base. If **PASS** or **N/A**, proceed to Phase 6. If the verdict is **FAIL**, delegate the fixes — do **not** fix the code yourself. If it is **PARTIAL** (no authoritative verification contract, or only pre-existing failures), stop and report the missing contract or the listed pre-existing failures; do not address, merge, or invent a substitute.

Capture the verifier's returned handoff-artifact JSON object: the complete durable `verification-record:v1` (exact command or ordered JSON plan, execution count, overall status, and ordered per-command result/status/evidence-pointer entries) plus its `suite-evidence` object. Confirm every `#/suite-evidence/command-<N>` pointer resolves inside that object to the matching exact command and complete unedited output. Write the whole object byte-for-byte to a harness-provided temporary file, or a uniquely created file under the operating system's temporary directory when the harness provides none, and pass the resolved path explicitly to `merge-pr`. The verifier publishes only the matching concise canonical record in its PR comment; `suite-evidence` remains in the temporary handoff and is never posted as persistent output. If the returned object is absent, malformed, or has a dangling or mismatched pointer, stop rather than reconstructing it from the parent transcript.

Because `implement-address` reads its findings from a file argument (and aborts if that file is missing or empty), you must **write the verification findings to a temp file first**, reusing the findings-file mechanics of Phase 4 Step C/D (write a temp findings file, then invoke `implement-address` with its path). Unlike Phase 4, there is no referee accept/reject step here: `verify` is a single, self-vetting source rather than several parallel reviewers who can disagree, so its findings pass straight through. The `verify` skill only posts a PR comment; it does not write this file, so the orchestrator must create it:

```bash
cat > <resolved-verify-findings-path> <<'EOF'
# Verification Findings — Round <N>

| # | Finding | Severity | Details |
|---|---------|----------|---------|
| 1 | <what failed> | Action Required | <expected vs. actual, file:line if known, how to fix> |
| ... | ... | ... | ... |
EOF
```

Then invoke the addresser with that file path, using a `verify-<round-number>` round token:

```
Payload: <pr-number> verify-<round-number> <resolved-verify-findings-path>
```

The round counter starts from round 1 (independent of Phase 4 rounds) and increments each FAIL → address → re-verify cycle. After the addresser pushes fixes, re-invoke `verify` with the failed scenarios. Allow at most 2 FAIL → address → re-verify cycles; on a third FAIL, do not address again: post an escalation comment listing the unresolved failures, then stop and inform the user.

### Phase 6: Merge & Finalize

Invoke `merge-pr` through the same harness-neutral adapter contract used for every other lifecycle phase. Select the Claude Code, Codex, Pi, or generic adapter for the active harness, load the canonical `merge-pr` skill explicitly, pass fresh PR context, and capture its returned result:

```
Payload: <pr-number> <resolved-verification-record-path>
```

This validates the PR, applies the target repository's merge and branch-retention policy, and posts updates on linked issues.

Report the result to the user.

## Escalation

Before flagging the human, consider whether a stalled run can be recovered autonomously (see the convergence-recovery decision in Phase 4 Step E): revise-and-reset on an insufficiently-specific scope, or restart-clean when the work has gone off track. Escalation to the human is the fallback when neither self-recovery path applies or the user should decide.

Stop and flag the human directly (not as a PR comment) when encountering:

- Ambiguous requirements where you cannot proceed without clarification
- Architectural decisions that exceed the scope of the task
- A new third-party dependency is needed
- Changes touch auth, crypto, or PII handling beyond existing patterns
- Tests fail in ways unrelated to your changes

Provide: what you tried, evidence for/against options, your recommended path.
