---
name: implement-code
description: Delegated implement-lifecycle worker: plan, test, implement, and open a PR.
license: MIT
metadata:
  version: "1.5.0"
  tags: ["implement", "code", "pr", "subagent"]
  author: benjamcalvin
---

# Implement

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Prefer fast package- or target-scoped checks during iteration (using the repository's default check only when fast and no narrower check exists); `verify` owns authoritative exact-head suite signoff.**

Implement the task supplied by the orchestrator. The first token is the linked issue number, or `0` if none. If the client leaves `$ARGUMENTS` literal, use the delegation prompt.

```text
$ARGUMENTS
```

## Instructions

You are the **implementer**: explore, plan, write code and tests, and open the PR. Inspect the branch, status, and referenced issue or spec first. Read `AGENTS.md`, `CLAUDE.md`, and relevant standards docs for invariants. Explicit user direction and the target repository's instructions override this skill's bundled fallbacks for branch names, commit format, PR structure, checks, and delivery.

### Step 0: Plan (unless skipped)

Skip to Step 1 when the task says "skip planning" or "just implement", or carries a detailed plan with acceptance criteria. Otherwise, without returning the plan: read referenced specs, ADRs, and issues; explore only the modules the task touches; write testable acceptance criteria; list test cases (happy path, edge, error, regression); and choose the minimum viable approach, noting risks.

### Step 1: Branch

On a shared base branch (the default or a shared integration branch), create a feature branch; on a feature or stacked branch for this work, stay on it. Bundled fallback name: `<type>/<short-description>` (type `feat`, `fix`, `refactor`, `docs`, `test`, or `chore`), lowercase, hyphenated, no issue numbers.

### Step 2: Automated Tests

Cover new/changed behavior and bugfixes with automated tests that would fail without the change (writing tests first when practical, such as bug reproductions and clear contracts; skipping unit tests only for pure documentation or non-executable config changes). Follow nearby test conventions and helpers; use obviously synthetic data, never real personal data.

### Step 3: Production Code

Write the minimum code that makes the tests pass. Match existing style; every changed line traces to the task. Do not "improve" adjacent code or formatting or add unrequested features. Add no comments except a constraint imposed from outside the codebase (link its source), a guarantee that cannot be tested, `TODO(#N)`, tool directives, and comments a tool turns into output. If code must stay a certain way, write a test named after that guarantee instead of a comment. Leave existing comments alone unless your change makes them false.

### Step 4: Verify and Self-Review

Run focused tests, linters, and a build for the packages you changed. Run `docs-check` with lint when the project has a `docs-check.toml`. Every touched test and every lint must pass; fix the code, not the tests. When the change has runnable artifacts, exercise them in a real environment (CLIs and scripts with representative inputs plus one error case; endpoints; configuration changes; migrations).

Read your own diff to remove stray changes, unused symbols, style mismatches, missing error handling, and security concerns. Scan added comments and delete each one that is outside the allow-list, cites your tracker (`#N`), narrates a step, or records history ("previously", "no longer").

### Step 5: Commit

Follow the target repository's commit policy; when silent, use `<type>: <summary>` in imperative mood with no period, plus a body stating the reason when the diff does not make it evident. Stage specific files, separate logically distinct changes, and never commit "WIP" or "fixup".

### Step 6: Sync, Push, and Create PR

Rebase on the branch this work belongs on: the default branch (`gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`) for standalone work, or the parent feature branch for stacked work; never assume `main`. Resolve conflicts, rerun only affected focused checks, and push with `git push -u origin HEAD`.

Use the target repository's PR template and formatting policy when present; otherwise read `references/pr-description.md` and use its fallback shape. Link the issue (when not `0`) with `Closes #N` only when this PR **fully completes** it, else `Part of #N`.

### Step 7: Return Result

Return exactly:

```
PR_NUMBER: <number>
PR_TITLE: <title>
SUMMARY: <1-2 sentence summary of what was implemented>
```
