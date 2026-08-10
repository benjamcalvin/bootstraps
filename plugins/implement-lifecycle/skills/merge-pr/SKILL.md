---
name: merge-pr
description: >-
  Merge a PR and update upstream GitHub issues with progress.
  Validates readiness, follows repository merge policy, and posts issue updates.
  Triggers: /merge-pr, merge this PR
license: MIT
metadata:
  version: "1.0.0"
  tags: ["merge", "pr", "issues"]
  author: benjamcalvin
---

# Merge PR and Update Issues

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Run focused tests, lint, builds, and acceptance commands only. Do not execute or consume the target repository's authoritative verification command or ordered command plan. Final verification owns that evidence.**

Merge the PR supplied with the invocation and update linked GitHub issues with what was delivered.

```text
$ARGUMENTS
```

If the current client leaves `$ARGUMENTS` literal, use the user's invoking prompt instead.

## PR Context

At runtime, parse the PR number and fetch its metadata, comments, and checks.

## Instructions

### Step 1: Validate Readiness

Before evaluating readiness, read explicit user direction and the target repository's governing instructions, branch-protection/ruleset configuration when accessible, and documented contribution policy. Those sources take precedence over every bundled fallback below. Resolve and record the required checks, approval rule, merge method, and branch-retention rule. Do not infer policy from this plugin's source repository.

Check that the PR is safe to merge. For each check, determine pass/fail:

1. **State** — PR must be `OPEN`. If already merged or closed, report and stop.
2. **Merge conflicts** — `mergeable` must not be `CONFLICTING`. If conflicts exist, report and stop.
3. **CI status** — Enforce the checks required by target-repository policy and explicit user direction. If either requires all reported checks, enforce all of them. Report every blocking failure and stop. A billing or account-status failure remains blocking unless repository policy or explicit user direction specifically permits that exception; an exception is never global. Even when permitted, classify the failure as billing-only only when the run or job carries an explicit billing/payment signal. Never infer billing from timing, and record every applied exception.
4. **PR standards** — Invoke the canonical `pr-check` skill through the shared adapter for the active harness: Claude Code, Codex, Pi, or generic. The adapter must explicitly load `pr-check`, pass the PR and fresh repository-policy context, and return its result; if isolated skill dispatch is unavailable, report the failed readiness step instead of running an improvised inline substitute. Apply the target repository's blocking standards. Bundled checks are fallbacks only when repository policy is silent. The bundled scope note remains advisory unless target policy makes scope a gate.
5. **Review decision** — Check `reviewDecision` and the approval rule established from repository policy and explicit user direction:
   - If `CHANGES_REQUESTED`, stop and report.
   - If the established policy requires approvals, require the declared number and kind of approvals; otherwise stop and report the missing approval.
   - If the established policy does not require approval, do not invent a requirement from the base branch name. Proceed autonomously when the other gates pass.
6. **Exact-head verification evidence** — Read the latest successful verification comment/result. Require all five fields: `verification-head`, `suite-result`, `suite-command`, `suite-executions`, and `suite-exit-status`. Independently establish the target repository's authoritative command or ordered command plan from the same target sources used by verification. Fetch the current `headRefOid` and require it to equal `verification-head`. Accept `pass` only when `suite-command` exactly matches that established command or ordered JSON command array, with the same command boundaries and order, exactly one plan execution, original overall exit status 0, and per-command results for every command in a plan. Reject different commands, reordered plans, missing command results, wrappers, arguments, prefixes, suffixes, or evidence when no target contract can be established. Accept `not-required` only after independently inspecting the changed files and confirming that every change is documentation or comments only, with command `none`, zero executions, and status `n/a`. Reject every other combination. Store the matching head as `VERIFIED_SHA`. Do not execute or consume the authoritative command or plan during merge readiness checks; validation reads verification's recorded result only.

**If validation fails**, stop and report exactly what needs to be fixed. Do not merge.

**If validation requires human judgment** (e.g., a check is flaky, unresolved conversations), stop and consult the user with the evidence.

### Step 2: Merge

Select the merge method and branch behavior established before readiness. Use the corresponding supported GitHub CLI method flag (`--merge`, `--squash`, or `--rebase`). Add `--delete-branch` only when repository policy or explicit user direction calls for deletion; omit it when the branch must be retained. When policy is silent, use an enabled repository merge method and retain the branch.

```
gh pr merge <pr-number> <merge-method-flag> <optional-delete-branch-flag> --match-head-commit "$VERIFIED_SHA"
```

The `--match-head-commit` precondition makes the evidence check and merge atomic: if the PR head changes after readiness validation, the merge fails rather than merging an unverified commit. If the merge fails, report the error and stop.

### Step 3: Update Linked Issues

1. **Extract issue references** from the PR title and description. Look for:
   - **Closing references:** `Closes #N`, `Fixes #N`, `Resolves #N` (case-insensitive) — the PR fully addresses the issue
   - **Partial references:** `Relates to #N`, `Part of #N` — the PR partially addresses or relates to the issue

2. **For each referenced issue**, fetch with `gh issue view <N> --json state,title` and post an update:

   **For closing references** (issue should be auto-closed by GitHub):
   ```
   gh issue comment <N> --body "$(cat <<'EOF'
   ## Delivered

   **PR:** #<pr-number> — <PR title>

   ### Changes delivered
   - <bullet summary extracted from PR description and diff>

   This PR fully addresses this issue.
   EOF
   )"
   ```

   **For partial references:**
   ```
   gh issue comment <N> --body "$(cat <<'EOF'
   ## Progress Update

   **PR:** #<pr-number> — <PR title>

   ### Changes delivered
   - <bullet summary extracted from PR description>

   ### Remaining work
   <What this issue still needs. If unclear, state "See issue description for remaining scope.">
   EOF
   )"
   ```

3. **If no issues are referenced**, skip this step.

### Step 4: Report

Output a summary:

```
## Merge Complete

**PR:** #<number> — <title>
**Merged to:** <base branch>
**Issues updated:** <list of issue numbers, or "none">

### Changes
- <bullet summary>
```

## Escalation

Stop and consult the user when:

- PR has failing CI checks that may be flaky (unclear if real failure)
- PR has unresolved review conversations
- Merge fails for an unexpected reason
- An issue referenced by the PR is already closed and the update seems redundant
- Any situation requiring human judgment about whether to proceed
