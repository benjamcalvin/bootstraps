---
name: implement
description: >-
  Implementation, review, verification, and merge — full lifecycle or any subset.
  Lean orchestrator delegating heavy work to subagents.
  Triggers: /implement, $implement-lifecycle:implement, implement this, build this feature
license: MIT
metadata:
  version: "4.4.0"
  tags: ["implement", "lifecycle", "review", "tdd"]
  author: benjamcalvin
---

# Implement

Orchestrate the implementation lifecycle (use the prompt if `$ARGUMENTS` is literal):

```text
$ARGUMENTS
```

Record the invocation time in UTC from the session event or clock. Inspect the branch and recent commits.

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

Map tiers via the active adapter. **Never silently inherit the orchestrator model for a `balanced` role; pass the adapter's explicit `balanced` model on every `review-general`, `review-docs`, `implement-address`, and `verify` call.** Supervise running children per `references/supervision.md`: sparse check-ins adapted to observed progress, never tight polling.

- **New roles:** Spawn a fresh isolated child (never inheriting orchestrator history) for `implement-code`, each Round-1 `review-general`, `review-docs`, and `verify`.
- **Continuations:** When supported, reuse that same subagent rather than spawning a new one: continue the `implement-code` author child via its Continuation Mode for addressing/Phase-5 fixes (spawn `implement-address` fresh only when entering on an existing PR without an author child), continue `review-general` for Round 2 deltas, and continue `review-docs` / `verify` for Phase-5 re-checks. Spawn fresh only when none exists or the harness is one-shot.

Read only your harness adapter once at start (`references/adapter-claude.md`, `references/adapter-codex.md`, `references/adapter-opencode.md`, `references/adapter-agy.md`, `references/adapter-pi.md`, or `references/adapter-generic.md`). Wait for reviewers; if any result lacks all four canonical headings, read `references/reviewer-recovery.md` before refereeing.

**PR & prompt as source of truth (no sidecar scratch files).** Do not write state, bundle, or scratch findings files. Keep child handles, risk, round and observed milestone times in context. Recover from events and PR history after compaction. For `Part of #N` slice PRs, scope review, refereeing, and verification to **this PR's slice** as stated in the PR description and prompt — never penalize or fail a slice PR for deferred parent-issue items.

### Entry Point

Leading token: `#N` → issue criteria; bare number → `gh pr view <n> --json number,title,state`; else freeform. Modifiers: *(none)* → full lifecycle (Phases 1–6, or 4–6 on PR); `"just review"` / `"review only"` → classify + Step A/C + ledger; `"address the review feedback"` → addresser + ledger; `"review and address"` → Phase 4 + ledger; `"skip planning"` / `"just implement"` → pass to `implement-code`.

### Phase 1–3: Implement & Create PR

**Never edit code or docs.** Delegate `implement-code`: `Payload: <issue-number-or-0> <task, criteria, instructions>`. In every writer prompt, including corrections, name the repo, affected checks and when its full gate is due. For multi-PR work, identify the first usable result. Name a real integration interaction for the first runnable slice. Keep the PR number and author handle. If from an issue, comment: `## In Progress` / `Implementation PR created: #<pr-number> — <PR title>`.

### Risk & Complexity

Assess **risk and complexity** pragmatically from what changed and what could break — **never by line-count thresholds, and do not overthink classification** (when in doubt between two levels, pick the lighter one unless concrete security, data, or concurrency risk is present):

| Level | Profile | Review & verify shape |
|-------|---------|-----------------------|
| `Low` | Straightforward, localized changes (bugfixes, small features, config, tests, docs, localized refactors) | 1 `review-general` reviewer, max 1 round; quick real-world smoke check via `verify` if runnable/observable surface changed (skip `verify` if none) |
| `Moderate` | Multi-module logic, CLI/API/UI behavior changes, or non-trivial state handling | 1 `review-general` reviewer (or 2 splitting distinct subsystems); max 2 rounds (Round 2 only if Round 1 accepted ≥ 1 `Action Required` finding); real-world `verify` |
| `High` | Auth/crypto/permissions/trust boundaries, schema/data migrations, concurrency/locking/distributed state, or very large cross-cutting surface area | 2–3 parallel `review-general` reviewers splitting surface area or focus; max 2 rounds (Round 2 only if Round 1 accepted ≥ 1 `Action Required` finding); real-world `verify` |

### Phase 4: Code Review / Address Loop {#review-loop}

#### Before Round 1

Rebase on base branch only when entering at Phase 4 or conflicting (`gh pr view` base, `git fetch`, `git rebase`). Mechanical conflict resolution is permitted: fix, run focused tests, `git push --force-with-lease`.

#### Step A: Invoke Reviewers

By default, spawn **1 `review-general` child** (`Payload: Review PR #<pr-number>, round <N>[, delta <prev>..<head>][ — <focus or surface slice>]`). Only when the surface area is very large or `High` risk/complexity, spawn **2–3 parallel `review-general` children**, assigning each a distinct subsystem slice or risk focus in its prompt (**max 3 reviewers total**). Reviewers are read-only and never post to GitHub or run suites. For Low changes confined to docs, skill wording or tests, assign docs accuracy and links to the same reviewer. Honor any required independent docs review. Continue only reviewers with accepted `Action Required` findings for Round 2 on `<prev>..<head>`. Follow-up reviewers judge only that range.

#### Step B: Referee Evaluation

Verify every finding against code, collapsing duplicates first (message reviewer if ambiguous). Accept verified violations of criteria/invariants (stay focused on the task at hand, respect `Part of #N` slice scope) with the smallest fix. Reject unproven, nitpick, "out of delta" (note as follow-ups; never open a round), or scope-creep items (unrequested dependencies, subsystems, public interfaces, or layers; simplify over-engineered code instead of hardening it). Zero survivors → Step C clean comment → Phase 5.

#### Step C: Post Consolidated Review

Post **one** comment via `references/consolidated-review.md`.

#### Step D: Invoke Addresser

Continue the author child (`implement-code` Continuation Mode), or spawn fresh `implement-address` if none exists, passing only accepted findings inline (`Payload: <pr-number> <round-number>` followed by `| # | Finding | Severity | Details |` with `file:line` and smallest fix).

#### Step E: Next Round

Never run a clean-confirmation round. `Low` runs and Round 1 runs with rejected-only or non-blocking findings (`only accepted Minor` / `Recommended`, zero `Action Required`) exit directly to Phase 5 after Step D. If cap exit leaves unresolved `Action Required`, read `references/convergence-recovery.md`. Otherwise advance to Round 2 with delta `<reviewed head>..<new head>` and return to Step A.

### Phase 5: Parallel Verification & Docs Review

Send failing automated checks to their owning writer for diagnosis. Keep required failures blocking. Run **Verification** and **Docs Review** **in parallel** on the post-review head when both apply:

- **Docs Review (`review-docs`, `balanced` child):** Skip if the general reviewer covered the docs, fixes stayed in scope and no separate reviewer is required. Otherwise spawn when docs, specs, READMEs, public interfaces (CLI/API/config), or documented behavior changed (`Payload: Review docs for PR #<pr-number>[, delta <prev>..<head>]`). Skip when purely internal code changed with no doc impact.
- **Real-World Verification (`verify`, `balanced` child, in parallel with `review-docs`):** `verify` exercises and inspects the actual built work (data outputs/shapes, CLI execution, browser UI navigation & screenshots, live endpoints/services) — **never spawn `verify` just to re-run unit tests**:
  - **Spawn `verify`** when the PR touches any runnable, visual, data-producing, or user-observable surface: `Payload: <pr-number> risk=<Low|Moderate|High> [failed-scenarios=<names>]` (keep the classified `risk=`; never re-classify).
  - **Skip `verify`** (record `verify: skipped (no live surface)` for the Run Ledger, and compare PR description claims against `gh pr diff <pr-number>` inline) when the PR has no changed live behavior. Exercise changed skill instructions when they affect what a user or agent can do.

**Resolve Phase 5:** Wait for both (when both run). Referee `review-docs` findings against code/docs (accept only concrete doc drift, broken links, missing interface docs, or `docs-check` errors).
- **PASS / N/A / skipped & clean docs:** fix any `Claim Mismatches` via `gh pr edit --body-file`, then Phase 6.
- **FAIL and/or accepted `Action Required` doc findings:** Batch both into **one** inline fix pass via `references/verify-fail-loop.md` (capped at 2 cycles), then recheck failures and refresh any stale verification verdict.
- **PARTIAL** (unavailable live environment/credentials, human-only check, or pre-existing merge-base failures): stop and print run ledger; never merge.

### Phase 6: Merge & Finalize

Reuse permitted results for the candidate head, command and environment. Assign each missing required check once to its project-designated owner. For local checks, continue the writer with `final checks <PR> <head> <commands>` (fresh `implement-address` if none exists). Complete agent-runnable gates before a human handoff. A failing gate blocks merge. If a fix changes the head, revisit affected review and verification before merging.

Evaluate and execute the canonical `merge-pr` skill inline against `<pr-number>`; do not spawn a child for it. Print the run ledger and report the result.

## Run ledger

Capture UTC event times as PR opens, review and verification finish, the PR becomes ready, and merge or stop occurs. Track observed external waits, spawns/continuations and fix commits. On every terminal path, read `references/run-ledger.md` and print the collapsed run ledger.

## Escalation

After `references/convergence-recovery.md`, escalate to human for ambiguous requirements, out-of-scope architecture, new dependencies, non-pattern auth/crypto/PII, human-only checks, or unrelated test failures, with options and the run ledger.
