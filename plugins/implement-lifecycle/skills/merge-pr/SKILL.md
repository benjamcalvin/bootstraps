---
name: merge-pr
description: "Merge a verified PR following the target project's rules and post linked issue updates. Triggers: /merge-pr, $implement-lifecycle:merge-pr, merge this PR"
argument-hint: <pr-number>
license: MIT
metadata:
  version: "4.0.0"
  tags: ["merge", "pr", "issues"]
  author: benjamcalvin
---

# Merge PR and Update Issues

```text
/merge-pr <pr-number>
$implement-lifecycle:merge-pr <pr-number>
```

Execute inline in Phase 6 (**never spawn a subagent**; do not spawn a child for it) or standalone against `<pr-number>`. **Stay focused on the task at hand; do not overthink — follow the target project's rules without inventing extra ceremony.**

## Step 1: Check Project Rules & Readiness

Read the target project's documented rules (`AGENTS.md`, `CLAUDE.md`, contributing/PR guides, and repository branch/merge settings) plus any explicit user direction. Target project rules are binding; user direction chooses only among options those rules permit.

Confirm:
1. PR is `OPEN` and has no merge conflicts (`mergeable` is not `CONFLICTING`).
2. Required CI checks pass and there are no `CHANGES_REQUESTED` reviews or unresolved blocking gates required by the project.
3. When real-world verification ran on the PR, the latest verification comment reports `PASS` (or `N/A`) with `Verified-Head` matching current `headRefOid` (`FAIL` or `PARTIAL` stops merge).
4. **Human approval / merge queue:** if project rules require human approval or merge-queue checks not yet satisfied, stop and report `## Ready for Human Merge — PR #<number>, awaiting human approval or merge queue.`

## Step 2: Merge

Merge using the project's rule-selected method (`--squash`, `--merge`, or `--rebase`) and branch-cleanup convention (`--delete-branch` when appropriate), guarding the head commit:

```bash
gh pr merge <pr-number> <merge-method-flag> <optional-delete-branch-flag> --match-head-commit "$HEAD_SHA"
```

## Step 3: Update Linked Issues & Report

When PR title or body references `#N`, read `references/issue-updates.md` and comment on linked issues. Report `## Merge Complete` with PR number, title, base branch, linked issues, and summary. Consult the user on flaky CI, open blockers, or ambiguous policy.
