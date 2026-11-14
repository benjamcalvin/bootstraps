---
name: merge-pr
description: >-
  Merge a verified PR following repository policy and post issue updates;
  validates exact-head verification-record: v2 header on the PR comment.
  Triggers: /merge-pr, $implement-lifecycle:merge-pr, merge this PR
argument-hint: <pr-number>
license: MIT
metadata:
  version: "2.0.0"
  tags: ["merge", "pr", "issues"]
  author: benjamcalvin
---

# Merge PR and Update Issues

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Prefer fast package- or target-scoped checks during iteration; Phase 5 (`verify` or inline fast gate) owns authoritative exact-head suite signoff.**

```text
/merge-pr <pr-number>
$implement-lifecycle:merge-pr <pr-number>
```

Parse `<pr-number>` from `$ARGUMENTS` or prompt. Fetch PR metadata, comments, and checks.

## Instructions

### Step 1: Validate Readiness

Read user direction and target repository policy. Enforced repository constraints are binding. Explicit user direction may select only among choices those constraints permit; it cannot waive or contradict them. Apply this precedence consistently to required checks, approvals, billing exceptions, merge method, and branch retention. Bundled fallbacks apply only when both sources are silent.

All gates must pass:
1. **State & Conflicts** — PR is `OPEN`; `mergeable` is not `CONFLICTING`.
2. **CI status** — enforce required checks. Billing/account failures remain blocking unless policy or user direction permits an explicit exception.
3. **PR standards** — Evaluate the canonical `pr-check` checklist inline; do not spawn a child for it. Apply the 7 checks: branch naming (`<type>/<short-description>`), title (`<type>: <summary>`), lead (2–3 plain-language sentences ending with `*(agent-drafted lead)*`), shape (`Author ran:`, `**Review focus:**`, rest under `<details>` with blank line after `</summary>`), commits (no WIP/fixup), references (`Closes #N` only when fully complete, else `Part of #N`), and altitude layering. Block only on failures of those rules declared by repository policy. Bundled fallback checks apply only where policy is silent, are non-blocking, and are reported as WARN in the merge summary; WARNs never stop the merge.
4. **Approvals** — `CHANGES_REQUESTED` stops merge. Require declared approvals when policy mandates them. If the established policy does not require approval, do not invent a requirement from the base branch name.
5. **Exact-head verification evidence** — validate the flat `verification-record: v2` header from the latest verification PR comment (never execute the authoritative suite here):
   - **Exact version & head:** require `verification-record: v2` outside `<details>` with `verification-head` equal to current `headRefOid`. Store as `VERIFIED_SHA`.
   - **Live check:** require `live-check` to be `pass` or `skipped` (`fail` or `partial` stops merge).
   - **Executable changes:** require `suite-result: pass`, `suite-command` matching the target repository's authoritative command or ordered plan, `suite-exit-status: 0`, and either `suite-source: executed` (with `suite-ci-run: none` and `suite-ci-attempt: none`) OR `suite-source: ci` independently re-confirmed per `references/ci-source.md`.
   - **Documentation/comments only:** accept `suite-result: not-required` (with `suite-source: none`, `suite-ci-run: none`, `suite-ci-attempt: none`, `suite-command: none`, `suite-exit-status: n/a`, `live-check: skipped`) only after independently inspecting changed files and confirming every change is docs or comments only.
   - **Non-mergeable verdicts:** reject `PARTIAL`, `suite-result: fail` (including pre-existing merge-base failures), or `suite-result: missing-contract`.

**Human approval stop:** When policy requires human approvals or merge-queue checks not yet met and agent gates pass, report `## Ready for Human Merge — PR #<number>, awaiting human approval or merge queue.`

### Step 2: Merge

Use the established merge method and branch behavior: repository constraints bind; user direction selects among permitted ones. Use the corresponding supported GitHub CLI method flag (`--merge`, `--squash`, or `--rebase`). Add `--delete-branch` only when policy calls for deletion; omit it when the branch must be retained:

```bash
gh pr merge <pr-number> <merge-method-flag> <optional-delete-branch-flag> --match-head-commit "$VERIFIED_SHA"
```

### Step 3: Update Linked Issues

When PR title or body references `#N`, read `references/issue-updates.md` and comment on linked issues. Skip when none are referenced.

### Step 4: Report

Report `## Merge Complete` with PR number, title, base branch, issues, warnings, and summary.

## Escalation

Consult user for flaky CI, open threads, merge errors, or ambiguous policy.
