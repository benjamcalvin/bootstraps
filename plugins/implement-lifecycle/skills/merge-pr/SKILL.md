---
name: merge-pr
description: >-
  Merge a verified PR following repository policy and post issue updates;
  validates exact-head verification record from comment or optional record path.
  Triggers: /merge-pr, $implement-lifecycle:merge-pr, merge this PR
argument-hint: <pr-number> [verification-record-path]
license: MIT
metadata:
  version: "1.1.0"
  tags: ["merge", "pr", "issues"]
  author: benjamcalvin
---

# Merge PR and Update Issues

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Prefer fast package- or target-scoped checks during iteration (using the repository's default check only when fast and no narrower check exists); `verify` owns authoritative exact-head suite signoff.**

```text
/merge-pr <pr-number> [verification-record-path]
$implement-lifecycle:merge-pr <pr-number> [verification-record-path]
```

Parse `<pr-number> [verification-record-path]` from `$ARGUMENTS` or prompt. Fetch PR metadata, comments, and checks.

## Instructions

### Step 1: Validate Readiness

Read user direction and target repository policy. Enforced repository constraints are binding. Explicit user direction may select only among choices those constraints permit; it cannot waive or contradict them. Apply this precedence consistently to required checks, approvals, billing exceptions, merge method, and branch retention. Bundled fallbacks apply only when both sources are silent.

All gates must pass:
1. **State & Conflicts** — PR is `OPEN`; `mergeable` is not `CONFLICTING`.
2. **CI status** — enforce required checks. Billing/account failures remain blocking unless policy or user direction permits an explicit exception.
3. **PR standards** — Evaluate the canonical `pr-check` checklist inline; do not spawn a child for it. Apply the 7 standard checks: branch naming (`<type>/<short-description>`), title (`<type>: <summary>`), lead (2–3 plain-language sentences ending with `*(agent-drafted lead)*`), shape (`Author ran:`, `**Review focus:**`, rest under `<details>` with blank line after `</summary>`), commits (no WIP/fixup), references (`Closes #N` only for complete resolution, else `Part of #N`), and altitude layering. Block only on failures of those rules declared by repository policy. Bundled fallback checks apply only where policy is silent, are non-blocking, and are reported as WARN in the merge summary; WARNs never stop the merge.
4. **Approvals** — `CHANGES_REQUESTED` stops merge. If repository policy requires approvals, require the declared number and kind. If the established policy does not require approval, do not invent a requirement from the base branch name.
5. **Exact-head verification evidence** — validate exact-head verification evidence; never execute the authoritative suite here.
   - **With `[verification-record-path]`:** Read that JSON file. If the path is absent, unreadable, or does not contain a complete `verification-record:v1` plus its referenced `suite-evidence`, stop rather than reconstructing evidence from an inaccessible parent transcript. Match `verification-record:v1` fields with the latest verification PR comment semantically. For every result, require its `#/suite-evidence/command-<N>` pointer to resolve inside the handed-off object to an entry with the exact command and nonempty output.
   - **Without `[verification-record-path]`:** Validate exact-head `verification-record: v1` directly from PR's latest verification comment on GitHub.
   - **Exact head and plan:** Current `headRefOid` must equal `verification-head`. Match authoritative plan independently established from target repository sources. Accept `pass` only when `suite-command` exactly matches that plan, overall exit status is 0, and per-command results match every plan command with `pass`/0.
   - **CI source.** When `suite-source` is `ci`, read `references/ci-source.md` and satisfy every condition there.
   - **Baseline.** Never treat `suite-baseline` results as PR-head evidence: they ran on the merge-base, and a `fail` record whose failures are all pre-existing is not mergeable.
   - **Not required.** Accept `not-required` only after independently inspecting the changed files and confirming that every change is documentation or comments only, with JSON `null` command and exit status, zero executions, empty results, and empty `suite-evidence`.
   - Store matching head as `VERIFIED_SHA`.

**Human approval stop:** When repository policy requires human approvals or merge-queue checks not yet met and all agent gates pass, report `## Ready for Human Merge` cleanly:
- `## Ready for Human Merge` — PR #<number>, awaiting required human approval or merge queue.

### Step 2: Merge

Use the established merge method and branch behavior: repository constraints bind; user direction selects among permitted ones. Use the corresponding supported GitHub CLI method flag (`--merge`, `--squash`, or `--rebase`). Add `--delete-branch` only when policy calls for deletion; omit it when the branch must be retained.

```bash
gh pr merge <pr-number> <merge-method-flag> <optional-delete-branch-flag> --match-head-commit "$VERIFIED_SHA"
```

### Step 3: Update Linked Issues

When the PR title or body references `#N`, read `references/issue-updates.md` and comment on linked issues. Skip when no issues are referenced.

### Step 4: Report

Report `## Merge Complete` with PR number, title, base branch, updated issues, warnings, and delivered changes summary.

## Escalation

Consult user for flaky CI, unresolved conversations, unexpected merge errors, or ambiguous policy.
