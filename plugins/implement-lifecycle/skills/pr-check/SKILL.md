---
name: pr-check
description: >-
  Validate a PR against PR standards before requesting review.
  Checks branch naming, title, description, commits, references, and scope.
  Triggers: /pr-check, check this PR, validate PR
license: MIT
metadata:
  version: "2.0.0"
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

**5. Commit Messages**
Each commit message should follow `<type>: <summary>` format. No "WIP", "fixup", or "wip" commits.

**6. References**
If the change relates to a GitHub issue, it should reference it with an appropriate keyword:
- `Closes #N` / `Fixes #N` — only when this single PR fully completes the issue
- `Part of #N` — when the PR is one of several addressing the issue

WARN if no references found (not all PRs need them, but flag for awareness). WARN if `Closes #N` is used but the PR appears to be a sub-task of a larger issue (e.g., the issue has multiple acceptance criteria and the PR only addresses some).

**7. Altitude Layering**
The description must descend through altitude layers rather than mixing them:
- The TL;DR contains **no** file paths, function names, or line numbers — behavior in plain language only
- Design reasoning (when present) is in component terms; code identifiers appear only in implementation-level sections (Implementation Notes, Test evidence, Review focus)
- No sentence carries a claim, its mechanism, and a citation at once; citations sit at the end of their bullet, not mid-clause
- No review chronology woven into the description ("round 1 added...", "after feedback we...")

WARN on isolated violations; FAIL if the TL;DR is saturated with code identifiers or the layers are absent entirely.

### Scope Note (advisory — not scored)

Assess whether the PR is **one logical change a reviewer can hold in their head in one sitting**, or a small batch of same-kind housekeeping changes. This is a judgment about cohesion, not size: a single ADR, a new module's scaffold, and a mechanical rename are each one logical change however many lines they span, while a small PR that fixes a bug *and* refactors an unrelated module is two.

Report a one-line observation. Say the PR is cohesive, or name the seam it should be split along. Do not assign PASS/WARN/FAIL, do not count lines against a threshold, and do not treat this note as a merge blocker — it exists to inform the author and reviewers, not to gate.

**Size-to-cap advisory (early split signal).** If the PR is over-scoped — far larger than the change it claims to be, or spanning multiple unrelated changes a reviewer cannot hold in one sitting — flag it and recommend splitting the out-of-scope work into child issues BEFORE implementation proceeds. This is a qualitative scope judgment, not a line-count threshold (see the scope note above). A PR that balloons past reviewable size mid-lifecycle forces scope-splitting refine passes and extra review rounds — far cheaper to split up front. This is advisory, not a blocker.

### Output Format

```
## PR Standards Check

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 1 | Branch naming | PASS/WARN/FAIL | ... |
| 2 | PR title | PASS/WARN/FAIL | ... |
| 3 | TL;DR | PASS/WARN/FAIL | ... |
| 4 | Test evidence | PASS/WARN/FAIL | ... |
| 5 | Commit messages | PASS/WARN/FAIL | ... |
| 6 | References | PASS/WARN/FAIL | ... |
| 7 | Altitude layering | PASS/WARN/FAIL | ... |

**Result: X/7 passing, Y warnings, Z failures**

**Scope (advisory):** <one line — cohesive, or the seam it should be split along>
```

If there are failures, add a brief "Suggested Fixes" section listing what to change.
