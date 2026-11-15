---
name: implement-address
description: "Delegated implement-lifecycle worker: address accepted review findings when running standalone or fresh on an existing PR."
license: MIT
metadata:
  version: "2.4.0"
  tags: ["implement", "address", "subagent"]
  author: benjamcalvin
---

# Address Review Findings

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Prefer fast package- or target-scoped checks during iteration; Phase 5 (`verify` or inline fast gate) owns authoritative exact-head suite signoff.**

Parse `<pr-number>` (plus optional `<round-id>` and inline findings) from the input (use the delegation prompt if `$ARGUMENTS` is literal).

```text
$ARGUMENTS
```

## Instructions

You are the **addresser**: fix accepted review findings (and only those), then run focused tests and push. **Stay focused on the task at hand; do not overthink** — apply the smallest direct fix without expanding scope. Used standalone (`"address the review feedback"`) or spawned fresh on an existing PR when no `implement-code` author child exists in the session. Use the inline findings supplied in the prompt when orchestrated; when invoked standalone without inline findings, fetch PR metadata and review comments via `gh pr view <pr-number> --comments`.

**Guard:** If no actionable findings are supplied or present on the PR, stop immediately and report it.

### Step 1: Address Each Finding

Read code around each finding, then take one action:
- **Apply** — make the requested change.
- **Partially apply** — implement a better fix that addresses the root cause and explain the deviation.
- **Reject with justification** — cite specs, ADRs, or conventions showing the current code is right; never reject without proof.
- **Escalate** — report evidence for and against when uncertain; never guess or silently skip.

**Preserve test evidence when compressing.** Keep assertions binding behavior — rollback seams, exhaustive comparators, boundary checks, regression coverage. Remove redundant assertions, not the strongest.

Add no comments outside the allow-list (external constraint with linked source, untestable guarantee, `TODO(#N)`, tool directives, tool-output comments; write a test instead), and delete none unless your change makes it false. Fix accepted Minor findings in the same pass.

### Step 2: Focused Verification

Run focused tests, linters, `docs-check` (if `docs-check.toml` exists), and a build on changed packages. Fix code, not tests, if any fail. Read your fix diff to catch regressions.

### Step 3: Commit, Push, and Report

Commit as `fix: address review round <round> — <description>` (separating unrelated fixes), and `git push`. Return:

| # | Finding | Action | Details |
|---|---------|--------|---------|
| 1 | <brief description> | Applied / Partially applied / Rejected / Escalated | <what was done and why> |

**Tests:** <command> — <result>
**Commits:** <list of fix commit messages>
