---
name: merge-pr
description: >-
  Lifecycle-internal merge step requiring a PR number and the temporary handoff
  artifact produced by verification; validates readiness, follows repository
  merge policy, and posts issue updates.
argument-hint: <pr-number> <handoff-artifact-path>
license: MIT
metadata:
  version: "1.0.0"
  tags: ["merge", "pr", "issues"]
  author: benjamcalvin
---

# Merge PR and Update Issues

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Run focused tests, lint, builds, and acceptance commands only. Do not execute or consume the target repository's authoritative verification command or ordered command plan. Final verification owns that evidence.**

```text
/merge-pr <pr-number> <handoff-artifact-path>
$implement-lifecycle:merge-pr <pr-number> <handoff-artifact-path>
```

Parse `<pr-number> <handoff-artifact-path>` from `$ARGUMENTS` when the client exposes it, otherwise from the invoking prompt. Read that JSON object and fetch the PR metadata, comments, and checks. If the path is absent, unreadable, or does not contain a complete `verification-record:v1` plus its referenced `suite-evidence`, stop rather than reconstructing evidence from an inaccessible parent transcript.

## Instructions

### Step 1: Validate Readiness

First read explicit user direction, the target repository's governing instructions, branch-protection/ruleset configuration when accessible, and documented contribution policy. Enforced repository constraints are binding. Explicit user direction may select only among choices those constraints permit; it cannot waive or contradict them. If they cannot be reconciled, stop and report the conflict. Apply this precedence consistently to required checks, approvals, billing exceptions, merge method, and branch retention. Bundled fallbacks apply only when both sources are silent. Never infer policy from this plugin's source repository.

Every check must pass:

1. **State** — the PR is `OPEN`; otherwise report and stop.
2. **Merge conflicts** — `mergeable` is not `CONFLICTING`; otherwise report and stop.
3. **CI status** — enforce the checks binding repository policy requires; user direction may add checks but not waive required ones. Report every blocking failure and stop. A billing or account-status failure stays blocking unless repository policy permits that exception, or policy is silent and explicit user direction permits it; an exception is never global, applies only when the run or job carries an explicit billing/payment signal (never inferred from timing), and is recorded.
4. **PR standards** — Evaluate the canonical `pr-check` checklist inline: read that skill's checks and apply them yourself; do not spawn a child for it. "Repository-declared" means declared in the policy read above (instructions, contribution docs, PR template, branch protection). Block only on failures of those rules. Bundled fallback checks apply only where repository policy is silent, are non-blocking, and are reported as WARN in the merge summary; WARNs never stop the merge. The scope note stays advisory unless target policy makes scope a gate.
5. **Review decision** — `CHANGES_REQUESTED` stops the merge. If repository policy requires approvals, require the declared number and kind; user direction may add approvals but not reduce the repository minimum. If the established policy does not require approval, do not invent a requirement from the base branch name. Proceed autonomously when the other gates pass.
6. **Exact-head verification evidence** — validate the handed-off record; never execute the authoritative command or plan here.
   - **Handoff matches comment.** Its `verification-record:v1` fields must match the latest verification PR comment semantically, not as raw text: comment `suite-command: none` ↔ JSON `null` and `suite-exit-status: n/a` ↔ JSON `null`; compare other scalars by typed value and structured fields as JSON, preserving array order. Require `verification-record: v1`, `verification-head`, `suite-result`, `suite-command`, `suite-executions`, `suite-exit-status`, and `suite-command-results`. An absent `suite-source` means `executed`; an absent, `none`, or JSON `null` `suite-ci-run`, `suite-ci-attempt`, or `suite-baseline` is none; any other value, including `false`, is present.
   - **Exact head and contract.** Independently establish the target repository's authoritative command or ordered plan from the same sources verification uses. The current `headRefOid` must equal `verification-head`.
   - **Accept `pass`** only when `suite-command` exactly matches that command or ordered JSON array (same boundaries and order), with `suite-source: executed` with exactly one plan execution or `suite-source: ci` with zero executions (below), no `suite-baseline`, overall exit status 0, and ordered per-command results matching every plan command with `pass`/zero. For every result, require its `#/suite-evidence/command-<N>` pointer to resolve inside the handed-off object's `suite-evidence` to an entry with the exact command and a nonempty output string. Reject outside, dangling, or mismatched pointers; different, reordered, missing, or wrapped commands, or added arguments, prefixes, or suffixes; stale or mismatched handoff/comment records; `missing-contract`; and any evidence when no target contract can be established.
   - **CI source.** For `suite-source: ci`, reject a record whose `suite-ci-attempt` is none or not an integer ≥ 1; otherwise parse the repository and run id from `suite-ci-run` and fetch that attempt with `gh run view -R <owner>/<repo> <run-id> --attempt <suite-ci-attempt> --json headSha,conclusion,jobs,url`. Require the repository to be the target repository, its `headSha` to equal `verification-head`, that attempt's `conclusion` to be `success`, and, in every job or matrix leg with a step running a plan command, each established command to map in order to a `success` step, none `skipped`; reject a conditional or `continue-on-error` plan step in the workflow definition the run executed (for `pull_request`, the merge ref). Reject a run for any other SHA, repository, or attempt.
   - **Baseline.** Never treat `suite-baseline` results as PR-head evidence: they ran on the merge-base, and a `fail` record whose failures are all pre-existing is not mergeable.
   - **Not required.** Accept `not-required` only after independently inspecting the changed files and confirming that every change is documentation or comments only, with JSON `null` command and exit status, zero executions, empty results, and empty `suite-evidence`.
   - Reject every other combination. Store the matching head as `VERIFIED_SHA`.

If validation fails, report exactly what must be fixed and do not merge; for judgment calls, see Escalation.

### Step 2: Merge

Use the merge method and branch behavior established before readiness: repository-required or -prohibited methods and retention are binding; user direction selects among permitted ones; an unresolved conflict stops the merge. Use the corresponding supported GitHub CLI method flag (`--merge`, `--squash`, or `--rebase`). Add `--delete-branch` only when the resolved policy calls for deletion; omit it when the branch must be retained. When both sources are silent, use an enabled repository method and retain the branch.

```
gh pr merge <pr-number> <merge-method-flag> <optional-delete-branch-flag> --match-head-commit "$VERIFIED_SHA"
```

`--match-head-commit` makes the evidence check and merge atomic: if the head changed after validation, the merge fails rather than merging unverified code. On failure, report the error and stop.

### Step 3: Update Linked Issues

From the PR title and description, find closing references (`Closes`/`Fixes`/`Resolves #N`, case-insensitive) and partial references (`Relates to`/`Part of #N`). For each, `gh issue view <N> --json state,title` and comment:

- **Closing:** `## Delivered`, `**PR:** #<pr-number> — <PR title>`, a `### Changes delivered` bullet summary, and "This PR fully addresses this issue."
- **Partial:** `## Progress Update`, the same PR line and `### Changes delivered`, then `### Remaining work` (or "See issue description for remaining scope.").

Skip this step when no issues are referenced.

### Step 4: Report

```
## Merge Complete

**PR:** #<number> — <title>
**Merged to:** <base branch>
**Issues updated:** <numbers, or "none">
**Warnings:** <fallback-standard WARNs and applied exceptions, or "none">

### Changes
- <bullet summary>
```

## Escalation

Stop and consult the user, with the evidence, for possibly flaky CI failures, unresolved review conversations, an unexpected merge failure, an already-closed referenced issue whose update seems redundant, or any other judgment call about proceeding.
