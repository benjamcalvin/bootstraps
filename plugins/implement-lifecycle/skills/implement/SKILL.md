---
name: implement
description: >-
  Implementation, review, and merge — full lifecycle or any subset.
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

You are a **lean orchestrator**: delegate and referee; do not implement. **Never edit source code, tests, or docs.** Run git/gh and focused checks for refereeing and read code to verify findings. **You are the sole PR publisher** (except `verify`'s comment): post **one consolidated comment per review round**. Drive autonomously; pause only for genuine ambiguity or escalation.

### Harness-neutral delegation

| Phase | Canonical skill | Model tier |
|-------|-----------------|------------|
| Implement | `implement-code` | `balanced`; `frontier` if pre-classified `Large` (> 1,500 changed lines) |
| Address | `implement-address` | `balanced` |
| Review general | `review-general` | `balanced` |
| Review correctness | `review-correctness` | `balanced` |
| Review security | `review-security` | `balanced` |
| Review docs | `review-docs` | `balanced` |
| Verify | `verify` | `balanced` |

Map tiers via the active adapter. **Never silently inherit the orchestrator model for a `balanced` role; pass the adapter's explicit `balanced` model on every `review-*`, `implement-address`, and `verify` call.** Wait for children; do not poll, sleep, or schedule wake-ups.

- **New roles:** Spawn a fresh isolated child (never inheriting orchestrator history) for `implement-code`, each Round-1 `review-*`, and `verify`.
- **Continuations:** When supported, reuse that same subagent rather than spawning a new one: continue the `implement-code` author child via its Continuation Mode for addressing/verify fixes (spawn `implement-address` fresh only when entering on an existing PR without an author child), continue `review-*` for Round 2 deltas, and continue `verify` for scoped re-verification. Spawn fresh only when none exists or the harness is one-shot.

Read only your harness adapter once at start (`references/adapter-claude.md`, `references/adapter-codex.md`, `references/adapter-agy.md`, `references/adapter-pi.md`, or `references/adapter-generic.md`). Wait for all selected reviewers; if any result lacks all four canonical headings, read `references/reviewer-recovery.md` before refereeing.

**PR & prompt as source of truth (no sidecar scratch files).** Do not write state, bundle, or scratch findings files. Keep active child handles, size tier, round, and phase start times in conversation context (recovering from PR comments, `gh pr view --json files`, and `git log` or spawning fresh children if compacted). For `Part of #N` slice PRs, scope review, refereeing, and verification to **this PR's slice** as stated in the PR description and prompt — never penalize or fail a slice PR for deferred parent-issue items.

### Entry Point

Leading token: `#N` → issue criteria; bare number → `gh pr view <n> --json number,title,state`; else freeform. Modifiers: *(none)* → full lifecycle (Phases 1–6, or 4–6 on PR); `"just review"` / `"review only"` → classify + Step A/C + ledger; `"address the review feedback"` → addresser + ledger; `"review and address"` → Phase 4 + ledger; `"skip planning"` / `"just implement"` → pass to `implement-code`.

### Phase 1–3: Implement & Create PR

**Never edit code or docs.** Delegate `implement-code`: `Payload: <issue-number-or-0> <task, criteria, instructions>`. Keep the PR number and author child handle for continuations. If from an issue, comment: `## In Progress` / `Implementation PR created: #<pr-number> — <PR title>`.

### Size Tier & Risk Lenses

Pre-classify `frontier` only if likely > 1,500 net lines. Once PR exists, count additions + deletions in added/modified/renamed files (excluding whole-file deletions, lockfiles, generated files) and inspect all changed paths (including deletions):

| Tier | Trigger |
|------|---------|
| Small | ≤ 400 changed lines |
| Medium | 401–1,500 changed lines |
| Large | > 1,500 changed lines |

**Size tier is determined strictly by net changed lines; risk paths select specialist lenses without escalating the size tier.**

### Phase 4: Review/Address Loop {#review-loop}

Bounded Steps A → E capped at 2 rounds:

| Tier | Max review rounds | Follow-up rounds |
|------|-------------------|------------------|
| Small | 1 | None: the addresser fixes accepted findings and runs focused tests; no re-review |
| Medium | 2 | Delta-only; Round 2 runs only if Round 1 accepted ≥ 1 Action Required finding |
| Large | 2 | Delta-only; Round 2 runs only if Round 1 accepted ≥ 1 Action Required finding |

Exits: (1) **Clean or non-blocking (Step B):** zero findings, OR `Small`, OR Round 1 accepted only `Recommended`/`Minor` findings (`only accepted Minor` / non-blocking fixes, zero `Action Required`) → addresser fixes + focused tests → Phase 5; (2) **Cap exit:** after Round 2, the addresser fixes the final round's accepted findings and runs focused tests → unresolved `Action Required` escalates, else Phase 5; (3) **Escalation:** `references/convergence-recovery.md`. Never exceed the cap without user authorization.

#### Before Round 1

Rebase on base branch only when entering at Phase 4 or conflicting (`gh pr view` base, `git fetch`, `git rebase`). Mechanical conflict resolution is permitted: fix, run focused tests, `git push --force-with-lease`. Fetch only `gh pr view`, `--json files`, and `--comments`; read specific files when refereeing.

#### Step A: Invoke Reviewers

Invoke **`review-general` in Round 1 on every tier** (holistic baseline: bugs, boundaries, conventions, test assertions). Attach up to **2 specialist lenses** by path/change trigger (**max 3 reviewers total**):
- `review-security`: auth, secrets, crypto, permissions, sandbox, or network/service exposure.
- `review-correctness`: schema/data migrations, concurrency/locking, or multi-step state/retry protocols.
- `review-docs`: docs, specs, READMEs, or public interfaces (CLI/API/config) change, or behavior described in `AGENTS.md`, ADRs, or covered specs changes.

If all 3 trigger, keep `review-security` + `review-correctness` (or keep `review-docs` over the weaker code trigger if `docs-check.toml` or `Covers:` specs changed) and note the third for `review-general`.

**Follow-up Round 2:** when Round 1 accepted `Action Required` solely from `review-docs` and the delta touches docs only, continue `review-docs` only; otherwise continue `review-general` plus specialists with accepted `Action Required` findings (and `review-docs` if the delta changes documented behavior).

Run in parallel (`Payload: Review PR #<pr-number>, round <N>[, delta <prev>..<head>][ — <task or slice scope note>]`). Reviewers are read-only and never post to GitHub or run suites. Follow-up reviewers judge only that range.

#### Step B: Referee Evaluation

Verify every finding against code, collapsing duplicates first (message reviewer if ambiguous). Accept verified violations of criteria/invariants (respecting `Part of #N` slice scope) with the smallest fix. Reject unproven items and reject findings outside the delta as "out of delta" (record as follow-ups; never open a round). **Scope controls:** reject unrequested dependencies, subsystems, public interfaces, or layers; simplify over-engineered code instead of hardening it. Zero survivors → Step C clean comment → Phase 5.

#### Step C: Post Consolidated Review

Post **one** comment via `references/consolidated-review.md`.

#### Step D: Invoke Addresser

Continue the author child (`implement-code` Continuation Mode), or spawn fresh `implement-address` if none exists, passing only accepted findings inline (`Payload: <pr-number> <round-number>` followed by `| # | Finding | Severity | Details |` with `file:line` and smallest fix).

#### Step E: Next Round

Never run a clean-confirmation round. Rejected-only or non-blocking Round 1 exits to Phase 5 after Step D. If cap exit leaves unresolved `Action Required`, read `references/convergence-recovery.md`. Otherwise advance to Round 2 with delta `<reviewed head>..<new head>` and return to Step A.

### Phase 5: Verification Gate

**Inline Fast Gate (no `verify` child):** Run Phase 5 inline per `verify/SKILL.md`, posting the flat `verification-record: v2` comment and recording `verify: inline (fast-gate)` for the Run Ledger, when **no live check is needed**:
1. Docs/comments only (`Verdict: N/A`, `suite-result: not-required`, `live-check: skipped`), OR
2. `Small` tier with **no runtime behavior, UI, CLI, API, migration, or deploy change**, where exact-head CI satisfies `verify`'s CI-evidence rules (`suite-source: ci`) or the authoritative command passes once inline on `verification-head` (`suite-source: executed`). On inline suite failure, spawn `verify` for merge-base baselining.

**Delegated `verify` (`balanced`):** Spawn `verify` when runtime behavior changed (`Small` runtime changes; all executable `Medium`/`Large`) or baselining is needed: `Payload: <pr-number> tier=<Small|Medium|Large> [failed-scenarios=<names>]` (keep the classified `tier=`; never re-classify).

**PASS** / **N/A** → confirm latest comment has valid `verification-record: v2` matching `headRefOid`, fix any `Claim Mismatches` via `gh pr edit --body-file`, then Phase 6. **FAIL** → capped at 2 cycles via `references/verify-fail-loop.md`. **PARTIAL** (missing contract, human-only check, pre-existing failures) → stop and print run ledger; never address or merge.

### Phase 6: Merge & Finalize

Evaluate and execute the canonical `merge-pr` skill inline against `<pr-number>`; do not spawn a child for it. Print the run ledger and report the result.

## Run ledger

Track phase times, spawns/continuations, and fix commits across the run. On every terminal path, read `references/run-ledger.md` and print the collapsed run ledger.

## Escalation

After `references/convergence-recovery.md`, escalate to human for ambiguous requirements, out-of-scope architecture, new dependencies, non-pattern auth/crypto/PII, human-only checks, or unrelated test failures, with options and the run ledger.
