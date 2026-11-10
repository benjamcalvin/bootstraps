---
name: implement-code
description: Plan, implement code, tests, and create PR for implement workflow (runs as subagent)
license: MIT
metadata:
  version: "1.2.0"
  tags: ["implement", "code", "pr", "subagent"]
  author: benjamcalvin
---

# Implement

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Run focused tests, lint, builds, and acceptance commands only. Do not execute or consume the target repository's authoritative verification command or ordered command plan. Final verification owns that evidence.**

Implement the task supplied by the orchestrator. The first token is the linked issue number, or `0` if none. If the client leaves `$ARGUMENTS` literal, use the delegation prompt.

```text
$ARGUMENTS
```

## Instructions

You are the **implementer**: explore, plan, write code and tests, and open the PR. Inspect the branch, recent commits, status, and referenced issue or spec first. Read `AGENTS.md`, `CLAUDE.md`, and relevant standards docs for invariants. Explicit user direction and the target repository's instructions override this skill's bundled fallbacks for branch names, commit format, PR structure, checks, and delivery. Use the client's task tracker when available.

### Step 0: Plan (unless skipped)

Skip to Step 1 when the task says "skip planning" or "just implement", or carries a detailed plan with acceptance criteria. Otherwise, without returning the plan: read referenced specs, ADRs, and issues; explore only the modules the task touches; write testable acceptance criteria; list test cases (happy path, edge, error, regression); and choose the minimum viable approach, noting risks.

### Step 1: Branch

On a shared base branch (the default or a shared integration branch), create a feature branch; on a feature or stacked branch for this work, stay on it. Bundled fallback name: `<type>/<short-description>` (type `feat`, `fix`, `refactor`, `docs`, `test`, or `chore`), lowercase, hyphenated, no issue numbers.

### Step 2: Tests First

Write tests for the planned cases **before** production code; they fail until the implementation is done. Follow nearby test conventions and helpers; use obviously synthetic data, never real personal data.

### Step 3: Production Code

Write the minimum code that makes the tests pass. Match existing style; every changed line traces to the task. Do not "improve" adjacent code or formatting or add unrequested features. Add no comments except a constraint imposed from outside the codebase (link its source), a guarantee that cannot be tested, `TODO(#N)`, tool directives, and comments a tool turns into output. If code must stay a certain way, write a test named after that guarantee. Leave existing comments alone unless your change makes them false.

### Step 4: Focused Verification

Run focused tests, linters, and a build for the packages you changed. Every test you touched and every lint must pass; if tests fail, fix the code, not the tests. Scan the comment lines you added (`git diff -U0 | rg '^\+\s*(//|#|/\*|\*|--)'`) and delete each one that is outside the allow-list, cites your tracker (`#N`, milestones), narrates a step, or records history ("previously", "no longer").

### Step 5: Manual Verification

When the change has runnable artifacts, exercise them in a real environment: CLIs and scripts with representative inputs plus one error case; each new or changed endpoint (status, body, errors); a service with changed configuration; a migration applied, rolled back, and reapplied. Libraries, refactors, and docs need none. Each piece of evidence has the exact **command**, its full unedited **output**, and an **explanation**.

### Step 6: Self-Review

Read every changed file and fix unused imports or variables, style mismatches, missing error handling, changes that do not trace to the task, and security concerns (injection, PII exposure, missing auth).

### Step 7: Commit

Follow the target repository's commit policy; when silent, use `<type>: <summary>` in imperative mood with no period, plus a body stating the reason when the diff does not make it evident. Stage specific files, separate logically distinct changes, and never commit "WIP" or "fixup".

### Step 8: Sync, Push, and Create PR

Rebase on the branch this work belongs on: the default branch (`gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`) for standalone work, or the parent feature branch for stacked work; never assume `main`. Resolve conflicts, rerun only affected focused checks, and push with `git push -u origin HEAD`.

Use the target repository's PR template and formatting policy when present; the structure below is a fallback. When the issue number is not `0`, put `Closes #N` (only when this PR **fully completes** the issue) or `Part of #N` (one of several; the default when unsure) after the TL;DR unless policy places it elsewhere.

Before writing the body, read `references/pr-description.md` (altitude rules for each section).

```bash
gh pr create --title "<type>: <imperative summary>" --body "$(cat <<'EOF'
## TL;DR
<2-4 plain-language sentences: the resulting change and why it matters, for a reader who has never seen the code>

<Closes #N or Part of #N — omit when the issue number is 0>

## Design
<Key design choices and reasons in component terms, including intentional spec deviations. Omit only when the TL;DR leaves no design question open.>

## Implementation Notes
<File-level shape of the diff and, when large, the order to read it>

## Test evidence
### Automated tests
<command and result summary>
### Manual verification
<command, full output, and explanation per check, or "N/A — no runnable artifacts changed">

## Review focus
<decisions reviewers should weigh in on, with file references>
EOF
)"
```

### Step 9: Return Result

Return exactly:

```
PR_NUMBER: <number>
PR_TITLE: <title>
SUMMARY: <1-2 sentence summary of what was implemented>
```
