---
name: implement
description: >-
  Implementation, review, and merge — full lifecycle or any subset.
  Lean orchestrator that delegates all heavy work to isolated subagents.
  Triggers: /implement, $implement-lifecycle:implement, implement this, build this feature
license: MIT
metadata:
  version: "3.2.0"
  tags: ["implement", "lifecycle", "review", "tdd"]
  author: benjamcalvin
---

# Implement

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Run focused tests, lint, builds, and acceptance commands only. Do not execute or consume the target repository's authoritative verification command or ordered command plan. Final verification owns that evidence.**

Orchestrate the implementation lifecycle for the task supplied with the invocation. If the harness leaves the payload below literal, use the user's invoking prompt.

```text
$ARGUMENTS
```

Inspect the current branch and recent commits before delegating.

## Instructions

<!-- stop-guard:active -->

You are a **lean orchestrator**: you delegate and referee; you do not implement. Every heavy phase runs in an isolated delegated child; worker skills do not create that isolation. **You MUST NOT use file-editing tools to modify source code, tests, or documentation.** You may run git/gh commands and tests and read code for refereeing.

**Scratch-file carve-out:** you may write orchestration files (findings handoffs, the verification record) outside the codebase under review. Use a harness-provided scratch location, else an OS-created temporary file, and pass each resolved path explicitly to the receiving worker.

**You are the sole publisher to the PR timeline.** Reviewers return findings to you and post nothing; you post exactly **one consolidated comment per review round**. If a reviewer posted anyway, note the contract violation and do not mirror it.

**Drive forward autonomously.** Run every phase without pausing for approval between them. Stop only for genuine ambiguity, a blocking decision outside the task's scope, or an escalation condition below.

Track phases in the client's task tracker when available, one in progress at a time.

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

Each delegation goes through the active harness's adapter below, selects the mapped skill explicitly, and requests its role's tier; adapters map tiers to concrete models. Never silently inherit the orchestrator's model for a `balanced` role. The referee stays with the orchestrator. Wait for child completion results; do not poll, sleep, or schedule wake-ups to check on children.

**Claude Code adapter.** Spawn a generic isolated subagent whose prompt begins `Use the implement-lifecycle:<skill> plugin skill`, followed by the complete payload and fresh context bundle. Pass the Agent tool's `model` parameter explicitly: `"sonnet"` for `balanced`; omit it (inherit) for `frontier`.

**Codex adapter.** Spawn a generic isolated subagent whose prompt begins `Use $implement-lifecycle:<skill>`, followed by the complete payload and fresh context bundle. Map `balanced` to the harness's balanced/default coding model and `frontier` to its strongest model.

**Pi adapter.** With the user-installed `pi-subagents` prerequisite available, launch a generic `delegate` child with `skill: <skill>`, `context: "fresh"`, and the complete payload and fresh context bundle. Map `balanced` to the delegate's balanced model and `frontier` to its strongest. Do not use or distribute custom Pi agent definitions.

**Generic adapter.** A compatible harness must create a fresh isolated child, load the mapped Agent Skill explicitly, pass the complete payload and fresh context bundle, and return the child result. A harness that cannot provide isolated delegation or load the required skill must report the failed phase and must not execute it inline. Map `balanced` and `frontier` to the closest available balanced and strongest models.

Wait for every selected reviewer before refereeing. A reviewer result is complete only when non-empty with all four canonical headings; never referee an incomplete one. **When a reviewer child returns an empty, missing, or incomplete result, read `references/reviewer-recovery.md` and follow its recovery graph before refereeing.**

**Context bundle.** Launch every child with minimal, fresh context, never the orchestrator's history. Assemble one bundle per PR and pass it to every child: issue, governing contract, prior accepted/rejected findings and referee decisions, and for round N ≥ 2 the delta range `<head reviewed in round N-1>..<current head>`. Children start from the bundle instead of re-fetching the full PR comment history.

### Entry Point

Identify the target from the leading token: `#N` → the issue body and comments give the task and acceptance criteria; a bare number → `gh pr view <number> --json number,title,state`, and record it if it is an open PR; anything else → the whole input is a freeform task.

Trailing text is instructions that narrow the lifecycle. Interpret intent; when unsure, do more rather than less:

| Instructions | Effect |
|-------------|--------|
| *(none)* | Issue/freeform → Phases 1–6; PR number → Phases 4–6 |
| "just review" / "review only" | Classify the tier, run Step A's selection, post the consolidated review (Step C), print the run ledger, stop |
| "address the review feedback" | Run the addresser on existing findings only; print the run ledger |
| "review and address" | Run the review loop without merging; print the run ledger |
| "skip planning" / "just implement" | Pass "skip planning" to `implement-code` |

### Phase 1–3: Plan, Implement & Create PR

**CRITICAL: You MUST NOT write code or edit files yourself.** Delegate implementation through the adapter. `implement-code` plans internally, so do not run a separate planning step; include "skip planning" only for clear, scoped tasks.

```
Payload: <issue-number-or-0> <task description, acceptance criteria, and optional instructions>
```

It returns the PR number. If the task came from an issue, comment on it: `## In Progress` / `Implementation PR created: #<pr-number> — <PR title>`.

### Tier classification

**Pre-classification** (before the implementer): judge from the task whether the work is likely large or touches a risk surface. This selects only the implementer's model tier.

**Authoritative classification** (once the PR exists): count changed lines (additions + deletions, excluding lockfiles and generated files) and inspect changed paths:

| Tier | Trigger |
|------|---------|
| Small | ≤ 400 changed lines and no risk surface |
| Large | > 1,500 changed lines, or any risk surface |
| Medium | Neither Small nor Large |

**Risk surface:** the target repository's declared list when present; otherwise authentication/authorization, secrets/credentials/crypto, data migrations/schema, CI/deploy configuration, sandbox/permission boundaries. Repository policy may override the thresholds. Start from the measured tier; the implementer's report may escalate it; nothing may lower it.

### Phase 4: Review/Address Loop {#review-loop}

A bounded loop of Steps A → E per round, capped by tier:

| Tier | Max review rounds | Follow-up rounds |
|------|-------------------|------------------|
| Small | 1 | None: the addresser fixes and runs focused tests; no re-review |
| Medium | 2 | Round 2 only if round 1 accepted ≥ 1 Action Required or Recommended finding |
| Large | 3 | Delta-only; the convergence audit after round 2 applies |

Exits:

1. **Clean exit (Step B):** no accepted findings (including an all-rejected round), or only accepted Minor findings (one batch pass, no new round) → Phase 5. If rejections were close calls, consider escalating for human direction.
2. **Cap exit:** at the tier cap the addresser fixes the final round's accepted findings and runs focused tests; any unresolved Action Required → escalation exit; otherwise → Phase 5.
3. **Escalation exit (Step E):** a scope/convergence guard fires, Large convergence stalls (a round accepts no fewer findings than the one before), or the cap exit reports unresolved Action Required → convergence-recovery decision.

Convergence = each round forwards fewer accepted findings than the prior, with no open production defect and no review-introduced churn. Never exceed the tier cap without explicit user authorization.

#### Before Round 1

Rebase on the PR's current base branch:

```bash
BASE_BRANCH=$(gh pr view --json baseRefName --jq '.baseRefName')
git fetch origin "$BASE_BRANCH" && git rebase "origin/$BASE_BRANCH"
```

Resolving conflicts is a **permitted git-mechanical carve-out** to the no-edit contract: keep it strictly mechanical, run focused tests for the affected packages, then `git push --force-with-lease`.

**Pin the toolchain once.** Discover the target repository's pinned runtime, compiler, package manager, and toolchain from its instructions and configuration, and pass the same selections to every phase; drift causes false failures.

For your own reference fetch only `gh pr view <number>`, its changed-file summary (`--json files`), and `--comments`; do **not** fetch the full diff. Read specific files when refereeing.

#### Step A: Invoke Reviewers

Invoke **`review-general` in every round**; it owns the baseline review. Specialists are selected mechanically by tier and path trigger, not by discretion:

- **Any tier:** `review-docs` when docs, specs, READMEs, or user-facing interfaces (CLI flags, public APIs, config keys) change, when the change alters architecture, conventions, or behavior described in AGENTS.md, ADRs, or other project docs, or when the tier is Large.
- **Small/Medium:** `review-general` only, plus `review-docs` per the trigger above.
- **Large:** `review-general` plus `review-docs` and each specialist whose trigger fires:
  - `review-security` — auth, secrets, crypto, sandbox, or permission paths change
  - `review-correctness` — migrations, concurrency primitives, or CI/deploy configuration change
  - `review-architecture` — a new top-level module/package or public interface is added
  - `review-testing` — production code changes without corresponding test changes
- **Follow-up rounds (N ≥ 2):** `review-general` only, plus a specialist or `review-docs` only when its own accepted finding is unresolved; re-include `review-docs` also when the fix delta changes documented behavior.

Invoke the selected reviewers in parallel:

```
Payload: Review PR #<pr-number>, round <round-number>[, delta <prev-reviewed-head>..<current-head>]
```

Reviewers return findings and do **not** post to GitHub. Follow-up reviewers judge only that range: did the fixes resolve the accepted findings, and did they introduce regressions? They must not reopen rejected findings or review code outside the delta.

Reviewers run the PR's focused acceptance commands when feasible (reasoning alone misses self-referential scans, off-by-one anchors, unbuilt code) and say so when they cannot.

#### Step B: Referee Evaluation

Independently evaluate every finding: read the relevant code yourself; neither rubber-stamp nor dismiss unchecked. First collapse duplicates across reviewers into one entry (noting the duplication) so each concern is evaluated and forwarded once.

Judge separately: (1) **validity** — does it show a concrete failure and the acceptance criterion, documented invariant, or existing behavior it violates? (2) **proportionality** — what is the smallest in-scope change that resolves it? A valid concern does not make the proposed remedy appropriate.

- **Accept** (default, once the failure and violated criterion are verified): forward only the smallest proportional correction.
- **Reject**: unproven, already resolved, out of scope, or disproportionate. Record whether the concern itself was valid; optionally file a follow-up.

Postures:
- **Security:** a concrete, applicable failure is high priority; reject attacks whose preconditions the changed code cannot meet.
- **Convention:** accept a violation of a documented standard; reject unbacked style preference.
- **Recommended:** accept only when concrete, in scope, and achievable without a new abstraction.
- **Minor:** never opens a round. Accepted Minors go to the addresser with other accepted findings, or alone in one batch pass.
- **Out of delta (round N ≥ 2):** Reject findings about code outside the round's delta as "out of delta" and record them as follow-up items for the final report; they never open a round.
- **Vague "consider"/"might":** reject unless backed by a reproducible failure or violated criterion.

**Scope controls.** Keep adversarial pressure on the design but tie every remedy to the original task. Never forward a remedy that adds a dependency, executable subsystem, public interface, persistence mechanism, or architectural layer the issue does not name; escalate or file a follow-up. If a remedy would push the PR beyond its one logical change, first audit which changes trace to the acceptance criteria and which only to review. When findings repeatedly target architecture added during addressing, simplify or remove it rather than harden it.

If zero findings survive, still post the Step C comment, ending `**Result:** no actionable findings — review loop complete.`, and go to Phase 5.

#### Step C: Post the Consolidated Review

Post **one** comment per round (use `--body-file` when long) using the template in `references/consolidated-review.md`. It is the round's entire audit trail: every reviewer that ran with its verdict, each reviewer's findings verbatim, and each referee decision, all visible, with the referee reasoning collapsed under `<details>`.

Write only accepted findings to a resolved findings path: `# Filtered Findings — Round <N>` and a `| # | Finding | Severity | Details |` table with file:line and what to fix.

#### Step D: Invoke Addresser

```
Payload: <pr-number> <round-number> <resolved-findings-path>
```

#### Step E: Next Round

Never run a redundant clean-confirmation round after a clean round with only trivial follow-up changes.

0. **Rejected-only rounds do not advance the loop.** If the referee accepted zero findings, do NOT invoke the addresser or count the round as productive; never send an empty findings file. Treat the loop as converged (→ Phase 5), or escalate if the rejections were close calls.
1. **Convergence audit after round 2 (Large):** post an audit mapping remaining findings and review-added changes to the acceptance criteria, with finding DENSITY per sub-problem across rounds (repeat targets are convergence traps). If remaining findings mainly concern review-introduced architecture, stop before round 3, request human direction, and recommend bounded simplification or removal of it.
2. **Convergence-recovery decision.** When the escalation exit fires, read `references/convergence-recovery.md` and choose revise-and-reset, restart-clean, or escalation to the user. Recovery starts a NEW loop.
3. **Continue** only if the tier cap allows another round (otherwise take the cap exit): record the delta range `<reviewed head>..<new head>`, increment the round, and return to Step A autonomously unless a scope guard or the audit requires human direction.

### Phase 5: Manual Verification Gate

Invoke `verify`:

```
Payload: <pr-number> tier=<Small|Medium|Large> [failed-scenarios=<names>]
```

`tier=` is the tier recorded at classification; never re-classify it. **PASS** or **N/A** → correct any Claim Mismatches it lists in the PR description (`gh pr edit <pr-number> --body-file <path>`), then Phase 6. **FAIL** → delegate the fixes; do **not** fix the code yourself. **PARTIAL** (no authoritative contract, or only pre-existing failures) → stop, print the run ledger, and report the missing contract or pre-existing failures; do not address, merge, or invent a substitute.

Capture the verifier's returned handoff-artifact JSON object: the complete durable `verification-record:v1` plus its `suite-evidence` object. Confirm every `#/suite-evidence/command-<N>` pointer resolves inside it to the matching command and complete unedited output, then write it byte-for-byte to a scratch file and pass that path to `merge-pr`; `suite-evidence` is never posted. If the object is absent, malformed, or has a dangling or mismatched pointer, stop rather than reconstruct it from the transcript.

On FAIL, `verify` only posts a PR comment, so write its failures to a findings file yourself (`# Verification Findings — Round <N>`, Step C's table, severity Action Required, with expected vs. actual and how to fix). No referee step: `verify` is self-vetting. Then:

```
Payload: <pr-number> verify-<round-number> <resolved-verify-findings-path>
```

Verify rounds count from 1, independent of Phase 4. Re-invoke `verify` with the failed scenarios, or without `failed-scenarios` when only the suite failed. Allow at most 2 FAIL → address → re-verify cycles; on a third FAIL, do not address again: post an escalation comment listing the unresolved failures, then print the run ledger, stop, and inform the user.

### Phase 6: Merge & Finalize

Select the Claude Code, Codex, Pi, or generic adapter for the active harness, load the canonical `merge-pr` skill explicitly, pass fresh PR context, and capture its result:

```
Payload: <pr-number> <resolved-verification-record-path>
```

Print the run ledger and report the result.

## Run ledger

Record a UTC timestamp (`date -u +%FT%TZ`) at each phase start and end. On every terminal path (merge, escalation, cap or stall exit, third verify FAIL, PARTIAL, or any other stop), print it to the user using `references/run-ledger.md`, collapsed under `<details>`; when a PR exists and the path posts a PR comment or merge summary, append it there too. Tally as you go: children per role and tier, addresser commits (from each Commits list, including verify fixes), and out-of-delta follow-ups.

## Escalation

After considering autonomous recovery (`references/convergence-recovery.md`), flag the human directly (not as a PR comment) for: ambiguous requirements, architectural decisions beyond the task's scope, a needed new third-party dependency, auth/crypto/PII changes beyond existing patterns, or test failures unrelated to the change. Provide what you tried, evidence for and against options, your recommended path, and the run ledger.
