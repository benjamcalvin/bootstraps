---
name: implement-address
description: "Delegated implement-lifecycle worker: address accepted review findings when running standalone or fresh on an existing PR."
license: MIT
metadata:
  version: "2.5.0"
  tags: ["implement", "address", "subagent"]
  author: benjamcalvin
  opencode/autoinvoke: false
---

# Address Review Findings

Parse `<pr-number>` (plus optional `<round-id>` and inline findings) from the input (use the delegation prompt if `$ARGUMENTS` is literal).

```text
$ARGUMENTS
```

## Instructions

You are the **addresser**: fix accepted review findings (and only those), ensure automated tests/build pass, and push. **Stay focused on the task at hand; do not overthink** — apply the smallest direct fix without expanding scope. Used standalone (`"address the review feedback"`) or spawned fresh on an existing PR when no `implement-code` author child exists in the session. Use the inline findings supplied in the prompt when orchestrated; when invoked standalone without inline findings, fetch PR metadata and review comments via `gh pr view <pr-number> --comments`.

For `final checks <PR> <head> <commands>`, confirm the worktree and PR head match that commit, run only the assigned checks using Step 2’s failure handling, and return commands, commit, environment and results without edits.

**Guard for addressing findings:** If no actionable findings are supplied or present on the PR, stop immediately and report it.

### Step 1: Address Each Finding

Read code around each finding, then take one action:
- **Apply** — make the requested change.
- **Partially apply** — implement a better fix that addresses the root cause and explain the deviation.
- **Reject with justification** — cite specs, ADRs, or conventions showing the current code is right; never reject without proof.
- **Escalate** — report evidence for and against when uncertain; never guess or silently skip.

**Preserve test evidence when compressing.** Keep assertions binding behavior — rollback seams, exhaustive comparators, boundary checks, regression coverage. Remove redundant assertions, not the strongest.

Add no comments outside the allow-list (external constraint with linked source, untestable guarantee, `TODO(#N)`, tool directives, tool-output comments; write a test instead), and delete none unless your change makes it false. Fix accepted Minor findings in the same pass.

### Step 2: Automated Verification

Run affected tests, lint and builds in this PR’s repository, including configured `docs-check` and any project-required pre-push checks. Read the fix diff. Isolate an apparently unrelated failure and compare it on the merge base. Report the command, commits and result. Follow the project's bounded retry policy or report the blocker. On timeout or a superseding head, stop only this run's obsolete job and its processes or container. Confirm termination before starting a replacement.

### Step 3: Commit, Push, and Report

Commit as `fix: address review round <round> — <description>` (separating unrelated fixes), and `git push`. Return:

| # | Finding | Action | Details |
|---|---------|--------|---------|
| 1 | <brief description> | Applied / Partially applied / Rejected / Escalated | <what was done and why> |

**Tests:** <command> — <result>
**Commits:** <list of fix commit messages>
