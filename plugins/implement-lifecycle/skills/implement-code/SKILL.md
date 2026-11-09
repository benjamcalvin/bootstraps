---
name: implement-code
description: Plan, implement code, tests, and create PR for implement workflow (runs as subagent)
license: MIT
metadata:
  version: "1.1.0"
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

You are the **implementer**: explore, plan, write code and tests, and open the PR. Inspect the branch, recent commits, status, and any referenced issue or spec first. Read `AGENTS.md`, `CLAUDE.md`, and relevant standards docs (e.g. `docs/`) for invariants. Explicit user direction and the target repository's governing instructions override this skill's bundled fallbacks for branch names, commit format, PR structure, checks, and delivery. Use the client's task tracker when available.

### Step 0: Plan (unless skipped)

Skip to Step 1 when the task says "skip planning" or "just implement", or already carries a detailed plan with acceptance criteria. Otherwise, without returning the plan: read referenced specs, ADRs, and issues; explore only the modules the task touches (patterns, test structure, dependencies); write testable acceptance criteria; list test cases (happy path, edge, error, and regression cases); and choose the minimum viable approach, noting risks.

### Step 1: Branch

On a shared base branch (the default or a shared integration branch), create a feature branch; on a feature or stacked branch for this work, stay on it. Bundled fallback name: `<type>/<short-description>`, type `feat`, `fix`, `refactor`, `docs`, `test`, or `chore`; lowercase, hyphen-separated, no issue numbers.

### Step 2: Tests First

Write tests for the planned cases **before** production code; they fail until the implementation is done. Follow nearby test conventions and helpers, and use obviously synthetic data, never real personal data.

### Step 3: Production Code

Write the minimum code that makes the tests pass. Match existing style and patterns; every changed line traces to the task. Do not "improve" adjacent code, formatting, or comments, or add unrequested features.

### Step 4: Focused Verification

Run focused tests, linters, and a build for the packages you changed. Every test you touched and every lint must pass; if tests fail, fix the code, not the tests.

### Step 5: Manual Verification

When the change has runnable artifacts, exercise them against a real environment: run CLI commands and scripts with representative inputs plus one error case; start the server and hit each new or changed endpoint (status, body, errors); start a service with changed configuration and observe it; apply, roll back, and reapply a migration. Library code, refactors, and docs need no manual verification. Each piece of evidence has the exact **command**, its complete unedited **output**, and an **explanation** of what it demonstrates.

### Step 6: Self-Review

Read every changed file and fix unused imports or variables, style mismatches, missing error handling, changes that do not trace to the task, and security concerns (injection, PII exposure, missing auth checks).

### Step 7: Commit

Follow the target repository's commit policy; when silent, use `<type>: <summary>` in imperative mood with no period. Stage specific files, separate logically distinct changes, and never commit "WIP", "fixup", or "wip".

### Step 8: Sync, Push, and Create PR

Rebase on the branch this work belongs on: the default branch (`gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`) for standalone work, or the parent feature branch for stacked work; never assume `main`. Resolve conflicts and rerun only the affected focused checks. Push with `git push -u origin HEAD`.

Use the target repository's PR template and formatting policy when present; the structure below is a fallback. When the issue number is not `0`, put `Closes #N` (only when this PR **fully completes** the issue) or `Part of #N` (one of several; the default when unsure) after the TL;DR unless policy places it elsewhere.

The description descends through altitude layers, one per section: the TL;DR is behavior only (plain language, **no file paths, function names, or line numbers**), Design is component terms only, and code identifiers appear from Implementation Notes down. One idea per sentence; cite an issue or spec at the end of a bullet, never mid-clause; keep review chronology ("round 1 added X") out. Skim test: the first sentence of each section, read in order, summarizes the PR at descending altitude.

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
