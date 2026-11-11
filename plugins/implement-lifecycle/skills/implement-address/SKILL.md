---
name: implement-address
description: Delegated implement-lifecycle worker: address accepted review findings and push fixes.
license: MIT
metadata:
  version: "2.2.0"
  tags: ["implement", "address", "subagent"]
  author: benjamcalvin
---

# Address Review Findings

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Prefer fast package- or target-scoped checks during iteration (using the repository's default check only when fast and no narrower check exists); `verify` owns authoritative exact-head suite signoff.**

Parse the PR number, round identifier, and findings-file path from the invocation input. If the client leaves `$ARGUMENTS` literal, use the delegation prompt.

```text
$ARGUMENTS
```

## Instructions

You are the **addresser**: fix the findings the referee accepted, and only those, then run tests and push. Read the findings file and supplied context-bundle file when provided; fetch PR metadata and comments only when invoked without a bundle.

**Guard:** If the findings file is missing, unreadable, or contains no findings, stop immediately and report it to the orchestrator.

Use the client's task tracker when available.

### Step 1: Address Each Finding

Read the code around each finding, then take one action:

- **Apply** — the finding is correct; make the change.
- **Partially apply** — the insight is right but the suggested fix is not; implement a better fix and explain the deviation.
- **Reject with justification** — deeper investigation shows the current code is correct; cite specs, ADRs, or conventions. Never reject without a concrete justification.
- **Escalate** — you cannot tell whether it is valid; report the evidence for and against. Never guess or silently skip.

**Preserve test evidence when compressing.** If a finding asks you to tighten, dedupe, or compress tests, keep the assertions that bind the behavior — rollback seams, exhaustive comparators, boundary checks, regression coverage. Remove redundant assertions, not the strongest one.

Add no comments outside the allow-list (an external constraint with its source linked, an untestable guarantee, `TODO(#N)`, tool directives, tool-output comments; test the guarantee instead), and delete none unless your change makes it false. Fix accepted Minor findings in the same pass; they never prompt another round.

### Step 2: Focused Verification

Run focused tests, linters, and a build on the packages you changed. Every test you touched and every lint must pass; if tests fail, fix the code, not the tests. Then read your own diff for issues the fixes introduced. When no follow-up review will occur (Small tier or final round), report the focused tests you ran.

### Step 3: Commit, Push, and Report

Commit as `fix: address review round <round> — <description>`, keeping unrelated fixes in separate commits, and `git push`. Return:

| # | Finding | Action | Details |
|---|---------|--------|---------|
| 1 | <brief description> | Applied / Partially applied / Rejected / Escalated | <what was done and why> |

**Tests:** <command> — <result>
**Commits:** <list of fix commit messages>
