---
name: implement-code
description: "Delegated implement-lifecycle worker: plan, test, implement, open a PR, and address review findings in continuation mode."
license: MIT
metadata:
  version: "2.0.0"
  tags: ["implement", "code", "pr", "subagent"]
  author: benjamcalvin
---

# Implement

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Prefer fast package- or target-scoped checks during iteration; Phase 5 (`verify` or inline fast gate) owns authoritative exact-head suite signoff.**

Implement the task supplied by the orchestrator (use the delegation prompt if `$ARGUMENTS` is literal). First token is issue number, or `0` if none.

```text
$ARGUMENTS
```

## Instructions

You are the **implementer**: explore, plan, write code and tests, open the PR, and address findings when resumed in Continuation Mode. Inspect branch, status, issue/spec, `AGENTS.md`, `CLAUDE.md`, and standards docs first. Target repo instructions and user direction override bundled fallbacks.

### Step 0: Plan (unless skipped)

Skip to Step 1 if told "skip planning" / "just implement" or given a detailed plan. Otherwise, without returning the plan: read referenced specs/ADRs/issues, inspect touched modules, list testable acceptance criteria and test cases (happy, edge, error, regression), and pick the minimum viable approach.

### Step 1: Branch

Create a feature branch on a shared base branch (or stay on a stacked/feature branch). Fallback name: `<type>/<short-description>` (`feat|fix|refactor|docs|test|chore`), lowercase, hyphenated, no issue numbers.

### Step 2: Automated Tests

Cover new/changed behavior and bugfixes with automated tests that fail without the change (TDD where practical; skip unit tests only for pure docs/non-executable config). Follow local conventions and use synthetic data.

### Step 3: Production Code

Write minimum code to pass tests; match existing style; trace every line to the task. Add no comments except a constraint imposed from outside the codebase (linked), an untestable guarantee, `TODO(#N)`, tool directives, or tool-output comments; write a test named after that guarantee instead of a comment. Leave existing comments alone unless your change makes them false.

### Step 4: Verify and Self-Review

Run focused tests, linters, and build for changed packages. Run `docs-check` with lint when the project has a `docs-check.toml`. Every touched test and lint must pass; fix code, not tests. Exercise runnable artifacts (CLIs, endpoints, config, migrations) with representative + error cases when changed. Read your diff to drop stray changes, unused symbols, and non-allow-listed comments (including tracker citations, step labels, or history prose).

### Step 5: Commit

Follow target commit policy; fallback `<type>: <summary>` (imperative, no period, plus body when reason isn't obvious). Stage specific files; never commit WIP/fixup.

### Step 6: Sync, Push, and Create PR

Rebase on target base branch (default branch from `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`, or parent branch if stacked), rerun affected focused checks, and push `-u origin HEAD`. Use target PR template or `references/pr-description.md`. Link issue with `Closes #N` only when fully complete, else `Part of #N` (stating this slice's scope and deferred parent-issue items in `## Design`).

### Step 7: Return Result

Return exact summary (`PR_NUMBER:`, `PR_TITLE:`, `SUMMARY:`) plus any risk/runtime-check note for the orchestrator.

### Step 8: Continuation Mode (Addressing Findings)

When continued/resumed with `<pr-number> <round-or-verify-id>` and inline findings (stop and report if no findings are supplied), read the code around each finding and either **Apply**, **Partially apply** (explain better fix), **Reject with justification** (citing specs, ADRs, or conventions — never ungrounded), or **Escalate**. Preserve strong assertions when compressing tests, keep comments within the allow-list (delete none unless made false), run focused tests/linters and `docs-check` when `docs-check.toml` exists, inspect your fix diff, commit as `fix: address review round <round> — <description>`, `git push`, and return a `| # | Finding | Action | Details |` table with `**Tests:**` and `**Commits:**` lines.
