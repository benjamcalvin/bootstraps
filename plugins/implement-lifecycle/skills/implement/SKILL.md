---
name: implement
description: >-
  Implementation, review, and merge — full lifecycle or any subset.
  Lean orchestrator that delegates all heavy work to isolated subagents.
  Triggers: /implement, $implement-lifecycle:implement, implement this, build this feature
license: MIT
metadata:
  version: "3.4.0"
  tags: ["implement", "lifecycle", "review", "tdd"]
  author: benjamcalvin
---

# Implement

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Prefer fast package- or target-scoped checks during iteration (using the repository's default check only when fast and no narrower check exists); `verify` owns authoritative exact-head suite signoff.**

Orchestrate the implementation lifecycle for the task supplied with the invocation. If the harness leaves the payload below literal, use the user's invoking prompt.

```text
$ARGUMENTS
```

Inspect the current branch and recent commits before delegating.

## Instructions

You are a **lean orchestrator**: delegate and referee; do not implement. Every heavy phase runs in an isolated delegated child; worker skills do not create that isolation. **You MUST NOT use file-editing tools to modify source code, tests, or documentation.** Run git/gh commands and tests and read code for refereeing. Write orchestration files outside the codebase under review (scratch directory or system temporary file), passing resolved paths explicitly. **You are the sole publisher to the PR timeline.** Reviewers return findings to you and post nothing; post exactly **one consolidated comment per review round**. Drive forward autonomously without pausing for approval between phases; stop only for genuine ambiguity, a blocking decision outside task scope, or escalation.

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

Each delegation goes through the active harness adapter, selects the mapped skill explicitly in a fresh isolated child, and requests its tier; adapters map tiers to concrete models. Never silently inherit the orchestrator's model for a `balanced` role. Wait for child completion results; do not poll, sleep, or schedule wake-ups to check on children.

Identify the active harness from its delegation tools and read only that harness's adapter reference once at run start:
- Claude Code → `references/adapter-claude.md`
- Codex → `references/adapter-codex.md`
- Antigravity (`agy`) → `references/adapter-agy.md`
- Pi → `references/adapter-pi.md`
- Other compatible harnesses → `references/adapter-generic.md`

Wait for every selected reviewer before refereeing. A reviewer result is complete only when non-empty with all four canonical headings; never referee an incomplete one. When a reviewer child returns an empty, missing, or incomplete result, read `references/reviewer-recovery.md` and follow its recovery graph before refereeing.

**Context bundle.** Launch every child with minimal, fresh context, never orchestrator history. Write one scratch context-bundle file per PR outside the codebase (issue, governing contract, PR body, changed-file summary, prior accepted/rejected findings and referee decisions; for round N ≥ 2 the delta range `<head reviewed in round N-1>..<current head>`), refresh it each round, and pass its resolved path (`bundle=<resolved-context-bundle-path>`) to every post-PR child. Children read the context bundle instead of re-fetching `gh pr view`.

### Entry Point

Identify the target from the leading token: `#N` → issue body and comments give task and criteria; bare number → open PR via `gh pr view <number> --json number,title,state`; anything else → freeform task. Trailing text narrows the lifecycle:

| Instructions | Effect |
|-------------|--------|
| *(none)* | Issue/freeform → Phases 1–6; PR number → Phases 4–6 |
| "just review" / "review only" | Classify the tier, run Step A's selection, post the consolidated review (Step C), print the run ledger, stop |
| "address the review feedback" | Run the addresser on existing findings only; print the run ledger |
| "review and address" | Run the review loop without merging; print the run ledger |
| "skip planning" / "just implement" | Pass "skip planning" to `implement-code` |

### Phase 1–3: Plan, Implement & Create PR

**CRITICAL: You MUST NOT write code or edit files yourself.** Delegate implementation through the adapter. `implement-code` plans internally; include "skip planning" only for clear, scoped tasks:

```text
Payload: <issue-number-or-0> <task description, acceptance criteria, and optional instructions>
```

It returns the PR number. If from an issue, comment: `## In Progress` / `Implementation PR created: #<pr-number> — <PR title>`.

### Tier classification

**Pre-classification:** judge whether work is likely large or risky to select implementer tier.
**Authoritative classification** (once the PR exists): count changed lines (additions + deletions in added, modified, or renamed files, excluding whole-file deletions, lockfiles, and generated files) and inspect all changed paths (including deleted files):

| Tier | Trigger |
|------|---------|
| Small | ≤ 400 changed lines and no risk surface |
| Large | > 1,500 changed lines, or any risk surface |
| Medium | Neither Small nor Large |

**Risk surface:** repository declared list when present; otherwise auth, secrets/crypto, data migrations/schema, CI/deploy configuration, sandbox/permission boundaries. Start from measured tier; implementer report may escalate it; nothing may lower it.

### Phase 4: Review/Address Loop {#review-loop}

A bounded loop of Steps A → E per round, capped by tier:

| Tier | Max review rounds | Follow-up rounds |
|------|-------------------|------------------|
| Small | 1 | None: the addresser fixes and runs focused tests; no re-review |
| Medium | 2 | Round 2 only if round 1 accepted ≥ 1 Action Required or Recommended finding |
| Large | 3 | Delta-only; the convergence audit after round 2 applies |

Exits: (1) **Clean exit (Step B):** no accepted findings, or only accepted Minor findings (one batch pass, no new round) → Phase 5; (2) **Cap exit:** at the tier cap the addresser fixes the final round's accepted findings and runs focused tests; any unresolved Action Required → escalation exit; otherwise → Phase 5; (3) **Escalation exit (Step E):** scope guard fires, Large convergence stalls, or cap exit reports unresolved Action Required → convergence-recovery decision.
Convergence = each round forwards fewer accepted findings than prior, with no open defect and no churn. Never exceed the tier cap without explicit user authorization.

#### Before Round 1

Rebase on base branch only when entering at Phase 4 on an existing PR or when branch is behind/conflicting:

```bash
BASE_BRANCH=$(gh pr view --json baseRefName --jq '.baseRefName')
git fetch origin "$BASE_BRANCH" && git rebase "origin/$BASE_BRANCH"
```

Resolving conflicts is a **permitted git-mechanical carve-out** to the no-edit contract: keep it strictly mechanical, run focused tests for affected packages, then `git push --force-with-lease`. Discover the target repository's pinned runtime and toolchain from instructions and configuration. Fetch only `gh pr view <number>`, changed-file summary (`--json files`), and `--comments`; do **not** fetch the full diff. Read specific files when refereeing.

#### Step A: Invoke Reviewers

Invoke **`review-general` in every round**; it owns the baseline review. Specialists are selected mechanically by tier and path trigger, not by discretion:

- **Any tier:** `review-docs` when docs, specs, READMEs, or user-facing interfaces (CLI flags, public APIs, config keys) change, when the change alters architecture, conventions, or behavior described in AGENTS.md, ADRs, or other project docs, or when the tier is Large.
- **Small/Medium:** `review-general` only, plus `review-docs` per the trigger above.
- **Large:** for Large tier, read `references/large-tier.md` to select triggered specialists (and after round 2 on Large, apply its convergence audit).
- **Follow-up rounds (N ≥ 2):** when the prior round accepted only `review-docs` findings and the fix delta touches only documentation files, run `review-docs` only; otherwise run `review-general`, plus any specialist or `review-docs` whose own accepted finding is unresolved (and `review-docs` when the fix delta changes documented behavior).

Invoke selected reviewers in parallel:

```text
Payload: Review PR #<pr-number>, round <round-number>[, delta <prev-reviewed-head>..<current-head>] bundle=<resolved-context-bundle-path>
```

Reviewers return findings and do **not** post to GitHub. Follow-up reviewers judge only that range: did the fixes resolve the accepted findings, and did they introduce regressions? They must not reopen rejected findings or review code outside the delta. Reviewers run the PR's focused acceptance commands when feasible.

#### Step B: Referee Evaluation

Independently evaluate every finding by reading relevant code yourself. First collapse duplicates across reviewers so each concern is evaluated and forwarded once.

Judge separately: (1) **validity** — concrete failure violating an acceptance criterion, documented invariant, or existing behavior; (2) **proportionality** — smallest in-scope change resolving it.
- **Accept** (default, once verified): forward only the smallest proportional correction.
- **Reject**: unproven, out of scope, unbacked style preference, vague "consider"/"might", or disproportionate. Reject findings about code outside the round's delta as "out of delta" and record them as follow-up items for the final report; they never open a round.
- **Minor:** never opens a round. Accepted Minors go to the addresser with other accepted findings, or alone in one batch pass.

**Scope controls.** Tie every remedy to the original task. Never forward a remedy that adds an unrequested dependency, executable subsystem, public interface, persistence mechanism, or architectural layer; escalate or record a follow-up. When findings repeatedly target architecture added during addressing, simplify or remove it rather than harden it.

If zero findings survive, post the Step C comment (`**Result:** no actionable findings — review loop complete.`) and go to Phase 5.

#### Step C: Post the Consolidated Review

Post **one** comment per round by reading `references/consolidated-review.md` and following its template. Write only accepted findings to a resolved findings path: `# Filtered Findings — Round <N>` and a `| # | Finding | Severity | Details |` table with file:line and what to fix.

#### Step D: Invoke Addresser

```text
Payload: <pr-number> <round-number> <resolved-findings-path> bundle=<resolved-context-bundle-path>
```

#### Step E: Next Round

Never run a redundant clean-confirmation round after a clean round with only trivial follow-up changes.
0. **Rejected-only rounds do not advance the loop.** If zero findings accepted, treat loop as converged (→ Phase 5), or escalate if rejections were close.
1. **Convergence audit after round 2 (Large):** for Large tier, apply the convergence audit in `references/large-tier.md`.
2. **Convergence-recovery decision.** When escalation exit fires, read `references/convergence-recovery.md`.
3. **Continue** only if tier cap allows: record delta range `<reviewed head>..<new head>`, increment round, and return to Step A autonomously.

### Phase 5: Manual Verification Gate

Invoke `verify`:

```text
Payload: <pr-number> tier=<Small|Medium|Large> record=<resolved-verification-record-path> [failed-scenarios=<names>] bundle=<resolved-context-bundle-path>
```

`tier=` is the tier recorded at classification; never re-classify it.

**PASS** or **N/A** → confirm the verification record file at `<resolved-verification-record-path>` exists and its `#/suite-evidence/command-<N>` pointers resolve, correct any Claim Mismatches it lists in the PR description (`gh pr edit <pr-number> --body-file <path>`), then Phase 6.

**FAIL** → on FAIL (capped at 2 fix cycles), read `references/verify-fail-loop.md` and delegate fixes without editing code yourself.

**PARTIAL** (no authoritative contract, or only pre-existing failures) → stop, print the run ledger, and report the missing contract or pre-existing failures; do not address, merge, or invent a substitute.

### Phase 6: Merge & Finalize

Evaluate and execute the canonical `merge-pr` skill inline against `<pr-number> <resolved-verification-record-path>`; do not spawn a child for it. Print the run ledger and report the result.

## Run ledger

Track phase start and end times. On every terminal path, read `references/run-ledger.md` and print the collapsed run ledger.

## Escalation

After considering autonomous recovery (`references/convergence-recovery.md`), flag the human directly for: ambiguous requirements, architectural decisions beyond task scope, new third-party dependencies, auth/crypto/PII changes beyond existing patterns, or test failures unrelated to the change. Provide options, recommendations, and the run ledger.
