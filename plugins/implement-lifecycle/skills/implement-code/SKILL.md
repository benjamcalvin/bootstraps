---
name: implement-code
description: Plan, implement code, tests, and create PR for implement workflow (runs as subagent)
context: fork
agent: general-purpose
argument-hint: <issue-number-or-0> <task description, plan, and instructions>
license: MIT
metadata:
  version: "1.1.0"
  tags: ["implement", "code", "pr", "subagent"]
  author: benjamcalvin
---

# Implement

Implement the following task. The first token is the linked issue number (or `0` if none):

$ARGUMENTS

## Context

- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`

## Project Standards

Read project-level instructions if they exist. At minimum, check for `AGENTS.md` and `CLAUDE.md` for critical invariants. Check for standards docs in `docs/` or `docs/specs/standards/` when your task touches relevant areas.

## Instructions

You are the **implementer** for the `/implement` workflow. You explore the codebase, plan, write code, write tests, and create the PR.

Use the **Task tools** (`TaskCreate`, `TaskUpdate`) to track your progress.

### Step 0: Plan (unless skipped)

If the task description includes "skip planning" or "just implement", or if the orchestrator has already provided a detailed plan with acceptance criteria, skip to Step 1.

Otherwise, plan the implementation before writing code:

1. **Understand the task.** Read the task description carefully. If specs, ADRs, or issues are referenced, read them. Identify what needs to change and any ambiguities.
2. **Explore the codebase.** Use Glob, Grep, and Read to understand which modules and files are relevant, existing patterns, test structure, and dependencies between affected modules. Focus on the areas the task touches — don't explore exhaustively.
3. **Define acceptance criteria.** Write verifiable criteria — each one testable (provably true or false after implementation). Be specific.
4. **Identify test cases.** List the tests that must pass: happy path, edge cases, error cases, and regression tests if modifying existing behavior.
5. **Plan the implementation.** Identify files to create or modify, the minimum viable approach, dependencies between changes, and any risks.

Do not return the plan to the orchestrator. Proceed directly to Step 1 with the plan in mind.

### Step 1: Create a Branch

If you're on the shared base branch for this work (for example the repository default branch or a shared integration branch), create a feature branch:

```bash
git checkout -b <type>/<short-description>
```

Branch naming: `<type>/<short-description>` where type is `feat`, `fix`, `refactor`, `docs`, `test`, or `chore`. Lowercase, hyphen-separated. No issue numbers in the branch name.

If already on a feature branch or stacked branch for this work, stay on it.

### Step 2: Write Tests First

Write tests for the identified test cases **before** writing production code. Tests should fail until implementation is complete. Follow existing test patterns in the codebase:
- Check nearby test files for conventions (table-driven tests, test helpers, naming)
- Use test utilities/helpers where available
- Use obviously synthetic data — never real personal data

### Step 3: Write Production Code

Write the minimum code to make all tests pass:
- Follow existing patterns in the codebase (match style, naming, structure)
- Surgical changes only — every changed line should trace to the task
- Don't "improve" adjacent code, formatting, or comments
- Don't add features beyond what was asked

### Step 4: Run the Full Test Suite

Run the project's test suite and linters. All tests must pass. All lints must pass. If tests fail, fix the code (not the tests).

### Step 5: Manual Verification

If your changes include **runnable artifacts** — CLI commands, scripts, API endpoints, or configuration that produces observable behavior — verify them against a real environment before proceeding.

| Change type | What to verify |
|-------------|---------------|
| **CLI commands / scripts** | Run with representative inputs. Verify expected output. Test at least one error case. |
| **API endpoints** | Start the server. Hit each new/changed endpoint. Verify response status, body, and errors. |
| **Configuration changes** | Start the affected service. Verify it loads correctly and behavior is observable. |
| **Database migrations** | Apply the migration. Verify schema changes. Roll back and reapply. |
| **Library code / refactoring / docs** | No manual verification required — automated tests are sufficient. Skip to Step 6. |

#### Evidence Format

Every piece of verification evidence must include three parts:

1. **Command** — the exact command that was run
2. **Output** — the complete, unedited output
3. **Explanation** — what the output demonstrates and why it constitutes a pass

### Step 6: Self-Review

Read every changed file. Check for:
- Unused imports or variables introduced by your changes
- Style mismatches with surrounding code
- Missing error handling
- Changes that don't trace directly to the task
- Security concerns (injection, PII exposure, missing auth checks)

Fix anything you find before proceeding.

### Step 7: Commit

Commit with `<type>: <summary>` format. Imperative mood, no period.
- Separate logically distinct changes into separate commits
- No "WIP", "fixup", or "wip" commits

```bash
git add <specific files>
git commit -m "<type>: <summary>"
```

### Step 8: Sync with the Correct Base Branch, Push, and Create PR

Before pushing, identify the branch this work should be based on. Use the repository's default branch for standalone work, or the parent feature branch for stacked work. Do not assume it is always `main`.

```bash
BASE_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
# Example for stacked work: BASE_BRANCH="feat/parent-feature"
git fetch origin "$BASE_BRANCH"
git rebase "origin/$BASE_BRANCH"
```

If conflicts arise, resolve them and re-run the test suite before continuing.

Push the branch (first push uses `-u` to set upstream):

```bash
git push -u origin HEAD
```

Create the PR. If the issue number is not `0`, include an issue reference after the TL;DR section:
- Use `Closes #N` only when this single PR **fully completes** the issue
- Use `Part of #N` when this PR is **one of several** addressing the issue (default to this when unsure)

The description descends through altitude layers, and each section holds one:
the TL;DR is behavior only (plain language, **no file paths, function names,
or line numbers**), Design is component terms only, and code identifiers
appear from Implementation Notes down. One idea per sentence; cite an issue or
spec at the end of a bullet, never mid-clause; keep review chronology ("round
1 added X") out of the description. Skim test before submitting: the first
sentence of each section, read in order, must summarize the PR at descending
altitude.

```bash
gh pr create --title "<type>: <imperative summary>" --body "$(cat <<'EOF'
## TL;DR
<Behavior layer. 2-4 plain-language sentences: the resulting change and why
it matters. A reader who has never seen the code must understand it.>

<Closes #N or Part of #N, on its own line — omit when the issue number is 0>

## Design
<Design layer. The important design choices and their reasons, in component
terms; identify intentional deviations from a spec here. Omit only when the
TL;DR leaves no design question open.>

## Implementation Notes
<Implementation layer — the only sections from here down where file, function,
and line references belong. The file-level shape of the diff and, when the
diff is large, the order in which to read it.>

## Test evidence

### Automated tests
<test command and result summary>

### Manual verification
<for each verification, include: exact command, full output, and explanation>
<if not applicable: "N/A — no runnable artifacts changed">

## Review focus
<the specific decisions reviewers should weigh in on, with file references>
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
