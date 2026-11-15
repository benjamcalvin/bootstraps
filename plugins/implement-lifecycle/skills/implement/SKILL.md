---
name: implement
description: >-
  Implementation, review, verification, and merge — full lifecycle or any subset.
  Lean orchestrator delegating heavy work to subagents.
  Triggers: /implement, $implement-lifecycle:implement, implement this, build this feature
license: MIT
metadata:
  version: "4.0.0"
  tags: ["implement", "lifecycle", "review", "tdd"]
  author: benjamcalvin
---

# Implement

<!-- lifecycle-suite-capability: orchestrator -->

**Suite capability: `orchestrator`. Use fast package- or target-scoped checks when refereeing in Phases 1–4; execute the authoritative suite at most once per head in Phase 5 when running the inline fast gate, otherwise delegate Phase 5 to `verify`.**

Orchestrate the implementation lifecycle (use the prompt if `$ARGUMENTS` is literal):

```text
$ARGUMENTS
```

Inspect the branch and recent commits before delegating.

## Instructions

You are a **lean orchestrator**: delegate and referee; do not implement. **Never edit source code, tests, or docs.** Run git/gh and focused checks for refereeing and read code to verify findings. **Stay focused on the task at hand; do not overthink.** Default to the simplest path that satisfies the requirement and project conventions; never invent speculative requirements, hypothetical edge cases, or ceremonial process. **You are the sole PR publisher** (except `verify`'s comment): post **one consolidated comment per code-review round**. Drive autonomously; pause only for genuine ambiguity or escalation.

### Harness-neutral delegation

| Phase | Canonical skill | Model tier |
|-------|-----------------|------------|
| Implement | `implement-code` | `balanced`; `frontier` if pre-assessed `High` risk/complexity |
| Address | `implement-address` | `balanced` |
| Review | `review-general` | `balanced` |
| Review docs | `review-docs` | `balanced` |
| Verify | `verify` | `balanced` |

Map tiers via the active adapter. **Never silently inherit the orchestrator model for a `balanced` role; pass the adapter's explicit `balanced` model on every `review-general`, `review-docs`, `implement-address`, and `verify` call.** Wait for children; do not poll, sleep, or schedule wake-ups.

- **New roles:** Spawn a fresh isolated child (never inheriting orchestrator history) for `implement-code`, each Round-1 `review-general`, `review-docs`, and `verify`.
- **Continuations:** When supported, reuse that same subagent rather than spawning a new one: continue the `implement-code` author child via its Continuation Mode for addressing/Phase-5 fixes (spawn `implement-address` fresh only when entering on an existing PR without an author child), continue `review-general` for Round 2 deltas, and continue `review-docs` / `verify` for Phase-5 re-checks. Spawn fresh only when none exists or the harness is one-shot.

Read only your harness adapter once at start (`references/adapter-claude.md`, `references/adapter-codex.md`, `references/adapter-agy.md`, `references/adapter-pi.md`, or `references/adapter-generic.md`). Wait for reviewers; if any result lacks all four canonical headings, read `references/reviewer-recovery.md` before refereeing.

**PR & prompt as source of truth (no sidecar scratch files).** Do not write state, bundle, or scratch findings files. Keep active child handles, risk/complexity level, round, and phase start times in conversation context (recovering from PR comments, `gh pr view --json files`, and `git log` or spawning fresh children if compacted). For `Part of #N` slice PRs, scope review, refereeing, and verification to **this PR's slice** as stated in the PR description and prompt — never penalize or fail a slice PR for deferred parent-issue items.

### Entry Point

Leading token: `#N` → issue criteria; bare number → `gh pr view <n> --json number,title,state`; else freeform. Modifiers: *(none)* → full lifecycle (Phases 1–6, or 4–6 on PR); `"just review"` / `"review only"` → classify + Step A/C + ledger; `"address the review feedback"` → addresser + ledger; `"review and address"` → Phase 4 + ledger; `"skip planning"` / `"just implement"` → pass to `implement-code`.

### Phase 1–3: Implement & Create PR

**Never edit code or docs.** Delegate `implement-code`: `Payload: <issue-number-or-0> <task, criteria, instructions>`. Keep the PR number and author child handle for continuations. If from an issue, comment: `## In Progress` / `Implementation PR created: #<pr-number> — <PR title>`.

### Risk & Complexity

Assess **risk and complexity** pragmatically from what changed and what could break — **never by line-count thresholds, and do not overthink classification** (when in doubt between two levels, pick the lighter one unless concrete security, data, or concurrency risk is present):

| Level | Profile | Review & verify shape |
|-------|---------|-----------------------|
| `Low` | Straightforward, localized changes (bugfixes, small features, config, tests, docs, localized refactors) | 1 `review-general` reviewer, max 1 round; inline fast gate if non-runtime (or smoke check via `verify` if runtime changed) |
| `Moderate` | Multi-module logic, CLI/API/UI behavior changes, or non-trivial state handling | 1 `review-general` reviewer (or 2 splitting distinct subsystems); max 2 rounds (Round 2 only if Round 1 accepted ≥ 1 `Action Required` finding); delegated `verify` |
| `High` | Auth/crypto/permissions/trust boundaries, schema/data migrations, concurrency/locking/distributed state, or very large cross-cutting surface area | 2–3 parallel `review-general` reviewers splitting surface area or focus; max 2 rounds (Round 2 only if Round 1 accepted ≥ 1 `Action Required` finding); delegated `verify` |

### Phase 4: Code Review / Address Loop {#review-loop}

Bounded Steps A → E capped at 2 rounds (`Low`: max 1 round, no re-review after addressing; `Moderate`/`High`: max 2 rounds, delta-only Round 2 runs only if Round 1 accepted ≥ 1 `Action Required` finding).

#### Before Round 1

Rebase on base branch only when entering at Phase 4 or conflicting (`gh pr view` base, `git fetch`, `git rebase`). Mechanical conflict resolution is permitted: fix, run focused tests, `git push --force-with-lease`.

#### Step A: Invoke Reviewers

By default, spawn **1 `review-general` child** (`Payload: Review PR #<pr-number>, round <N>[, delta <prev>..<head>][ — <focus or surface slice>]`). Only when the surface area is very large or `High` risk/complexity, spawn **2–3 parallel `review-general` children**, assigning each a distinct subsystem slice or risk focus in its prompt (**max 3 reviewers total**). Reviewers are read-only and never post to GitHub or run suites. Follow-up Round 2 continues only the reviewer(s) whose `Action Required` findings were accepted, judging only `<prev>..<head>` (Follow-up reviewers judge only that range).

#### Step B: Referee Evaluation

Verify every finding against code, collapsing duplicates first (message reviewer if ambiguous). Accept verified violations of criteria/invariants (stay focused on the task at hand, respect `Part of #N` slice scope) with the smallest fix. Reject unproven, nitpick, "out of delta" (note as follow-ups; never open a round), or scope-creep items (unrequested dependencies, subsystems, public interfaces, or layers; simplify over-engineered code instead of hardening it). Zero survivors → Step C clean comment → Phase 5.

#### Step C: Post Consolidated Review

Post **one** comment via `references/consolidated-review.md`.

#### Step D: Invoke Addresser

Continue the author child (`implement-code` Continuation Mode), or spawn fresh `implement-address` if none exists, passing only accepted findings inline (`Payload: <pr-number> <round-number>` followed by `| # | Finding | Severity | Details |` with `file:line` and smallest fix).

#### Step E: Next Round

Never run a clean-confirmation round. `Low` runs and Round 1 runs with rejected-only or non-blocking findings (`only accepted Minor` / `Recommended`, zero `Action Required`) exit directly to Phase 5 after Step D. If cap exit leaves unresolved `Action Required`, read `references/convergence-recovery.md`. Otherwise advance to Round 2 with delta `<reviewed head>..<new head>` and return to Step A.

### Phase 5: Parallel Verification & Docs Review

Run **Verification** and **Docs Review** **in parallel** on the post-Phase-4 PR head:

- **Docs Review (`review-docs`, `balanced` child):** Spawn whenever docs, specs, READMEs, public interfaces (CLI/API/config), or behavior described in `AGENTS.md`, ADRs, or covered specs changed (`Payload: Review docs for PR #<pr-number>[, delta <prev>..<head>]`). Skip when purely internal code changed with no doc impact.
- **Verification:**
  - **Inline Fast Gate (no `verify` child):** Run inline (recording `verify: inline (fast-gate)` for the Run Ledger) when **no live runtime check is needed**: (1) docs/comments only (`Verdict: N/A`), or (2) `Low` risk with no runtime/UI/CLI/API/migration/deploy change where exact-head required CI already passed or the project's test command passes once inline on `headRefOid` (post concise verification comment with `### Verdict: PASS` and `Verified-Head: <full-head-sha>`). On inline suite failure, spawn `verify` for merge-base baselining.
  - **Delegated `verify` (`balanced` child, in parallel with `review-docs`):** Spawn when runtime behavior changed or risk/complexity is `Moderate`/`High`: `Payload: <pr-number> risk=<Low|Moderate|High> [failed-scenarios=<names>]` (keep the classified `risk=`; never re-classify).

**Resolve Phase 5:** Wait for both (when both run). Referee `review-docs` findings against code/docs (accept only concrete doc drift, broken links, missing interface docs, or `docs-check` errors).
- **PASS / N/A & clean docs:** fix any `Claim Mismatches` via `gh pr edit --body-file`, then Phase 6.
- **FAIL and/or accepted `Action Required` doc findings:** Batch both into **one** inline fix pass via `references/verify-fail-loop.md` (capped at 2 cycles), then re-run only the failed check(s).
- **PARTIAL** (missing test contract, human-only check, or pre-existing merge-base failures): stop and print run ledger; never merge.

### Phase 6: Merge & Finalize

Evaluate and execute the canonical `merge-pr` skill inline against `<pr-number>`; do not spawn a child for it. Print the run ledger and report the result.

## Run ledger

Track phase times, spawns/continuations, and fix commits across the run. On every terminal path, read `references/run-ledger.md` and print the collapsed run ledger.

## Escalation

After `references/convergence-recovery.md`, escalate to human for ambiguous requirements, out-of-scope architecture, new dependencies, non-pattern auth/crypto/PII, human-only checks, or unrelated test failures, with options and the run ledger.
