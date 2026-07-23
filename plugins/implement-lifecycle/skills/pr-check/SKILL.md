---
name: pr-check
description: >-
  Validate a PR against PR standards before requesting review.
  Checks branch naming, title, description, sizing, commits, and references.
  Triggers: /pr-check, check this PR, validate PR
license: MIT
metadata:
  version: "1.1.0"
  tags: ["pr", "check", "standards", "validation"]
  author: benjamcalvin
---

# PR Standards Check

Pre-flight validation for PRs.

```text
$ARGUMENTS
```

If the current client leaves `$ARGUMENTS` literal, use the user's invoking prompt. If no PR number is supplied, inspect the PR associated with the current branch when available.

## Context

At runtime, inspect the current branch and fetch available PR metadata and comments. Determine the actual base branch before inspecting commits and diff size.

## Instructions

Validate the current PR against each standard below. If no PR exists, check only what can be validated locally and note that no PR exists yet.

For each check, output one of:
- **PASS** — Meets the standard
- **WARN** — Minor deviation, note what's off
- **FAIL** — Does not meet the standard, explain what needs to change

### Checks

**1. Branch Naming**
Branch must match `<type>/<short-description>` where type is one of: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`. Must be lowercase, hyphen-separated.

**2. PR Title**
Must match `<type>: <imperative summary>`. Type prefix should match branch type. Under 72 characters. No period at the end. Imperative mood ("Add", "Fix"), not past tense ("Added", "Fixed").

**3. PR Description — TL;DR**
Must open with 2-4 plain-language sentences explaining what the change does and why (a `## TL;DR` or `## Summary` section, before any mechanism). FAIL if the description opens with implementation bullets instead of prose a non-reader of the code could follow.

**4. PR Description — Test Evidence**
Must include how the change was verified: test output, manual steps, or "covered by existing tests."

**5. PR Sizing**
Check additions + deletions (excluding generated code, test fixtures, lock files if identifiable):
- Under 400 lines → PASS
- 400-600 lines → WARN ("consider splitting")
- Over 600 lines → FAIL ("should be split")

**6. Commit Messages**
Each commit message should follow `<type>: <summary>` format. No "WIP", "fixup", or "wip" commits.

**7. References**
If the change relates to a GitHub issue, it should reference it with an appropriate keyword:
- `Closes #N` / `Fixes #N` — only when this single PR fully completes the issue
- `Part of #N` — when the PR is one of several addressing the issue

WARN if no references found (not all PRs need them, but flag for awareness). WARN if `Closes #N` is used but the PR appears to be a sub-task of a larger issue (e.g., the issue has multiple acceptance criteria and the PR only addresses some).

**8. Altitude Layering**
The description must descend through altitude layers rather than mixing them:
- The TL;DR contains **no** file paths, function names, or line numbers — behavior in plain language only
- Design reasoning (when present) is in component terms; code identifiers appear only in implementation-level sections (Implementation Notes, Test evidence, Review focus)
- No sentence carries a claim, its mechanism, and a citation at once; citations sit at the end of their bullet, not mid-clause
- No review chronology woven into the description ("round 1 added...", "after feedback we...")

WARN on isolated violations; FAIL if the TL;DR is saturated with code identifiers or the layers are absent entirely.

### Output Format

```
## PR Standards Check

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 1 | Branch naming | PASS/WARN/FAIL | ... |
| 2 | PR title | PASS/WARN/FAIL | ... |
| 3 | TL;DR | PASS/WARN/FAIL | ... |
| 4 | Test evidence | PASS/WARN/FAIL | ... |
| 5 | Sizing | PASS/WARN/FAIL | ... |
| 6 | Commit messages | PASS/WARN/FAIL | ... |
| 7 | References | PASS/WARN/FAIL | ... |
| 8 | Altitude layering | PASS/WARN/FAIL | ... |

**Result: X/8 passing, Y warnings, Z failures**
```

If there are failures, add a brief "Suggested Fixes" section listing what to change.
