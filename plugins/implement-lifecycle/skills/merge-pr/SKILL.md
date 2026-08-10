---
name: merge-pr
description: >-
  Merge a PR and update upstream GitHub issues with progress.
  Validates readiness, squash-merges, deletes branch, and posts issue updates.
  Triggers: /merge-pr, merge this PR
license: MIT
metadata:
  version: "1.0.0"
  tags: ["merge", "pr", "issues"]
  author: benjamcalvin
---

# Merge PR and Update Issues

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Run focused acceptance commands only. Do not run `./validate-all.sh`, an explicit shell invocation of that alias, or any full, complete, entire, repository-wide, or lifecycle-wide test suite. Final verification owns the authoritative suite.**

Merge the PR supplied with the invocation and update linked GitHub issues with what was delivered.

```text
$ARGUMENTS
```

If the current client leaves `$ARGUMENTS` literal, use the user's invoking prompt instead.

## PR Context

At runtime, parse the PR number and fetch its metadata, comments, and checks.

## Instructions

### Step 1: Validate Readiness

Check that the PR is safe to merge. For each check, determine pass/fail:

1. **State** — PR must be `OPEN`. If already merged or closed, report and stop.
2. **Merge conflicts** — `mergeable` must not be `CONFLICTING`. If conflicts exist, report and stop.
3. **CI status** — All status checks must pass. If any check is failing, report which ones and stop. **Exception — billing-only failure:** if a check failed purely because the account spending limit prevented any job from running, that is NOT a code gate. Classify a failure as billing-only ONLY when the run or job message carries an explicit billing/payment signal (e.g. "job was not started because recent account payments have failed", or a spending-limit error in the run output). Do NOT infer billing from timing — a job that fails in seconds before any step ran may be a genuine fast failure (config syntax, missing secret, immediate lint/compile error). When in doubt, treat it as a real failure. Record a confirmed billing exception in your report and proceed — do not block or report it as a red code failure.
4. **PR standards** — Invoke `pr-check` in Claude Code or `$implement-lifecycle:pr-check` in Codex against the PR. All scored checks must pass (WARN is acceptable, FAIL is not). Fix any failures if possible; otherwise report what needs to be fixed and stop. The **scope note is advisory** — surface it in your report, but never block a merge on it. A cohesive change is mergeable whatever its diff size, and a PR whose scope is already under review is past the point where splitting is cheap.
5. **Review decision** — Check `reviewDecision` and `baseRefName`:
   - If `CHANGES_REQUESTED`, stop and report.
   - If merging to `main` or `master`: require `APPROVED`. If `REVIEW_REQUIRED` or empty/null, escalate to the user and wait for explicit confirmation.
   - If merging to any other branch: human approval is not required. Proceed if CI passes and all other checks are satisfied.
6. **Exact-head verification evidence** — Read the latest successful verification comment/result. Require `verification-head`, `suite-result`, `suite-executions`, and `suite-exit-status`; `suite-result` must be `pass` with one successful execution or `not-required` with zero executions. Fetch the current `headRefOid` and require it to equal `verification-head`. Store that value as `VERIFIED_SHA`. Do not execute any suite during merge readiness checks.

**If validation fails**, stop and report exactly what needs to be fixed. Do not merge.

**If validation requires human judgment** (e.g., a check is flaky, unresolved conversations), stop and consult the user with the evidence.

### Step 2: Merge

Squash-merge the PR and delete the remote branch:

```
gh pr merge <pr-number> --squash --delete-branch --match-head-commit "$VERIFIED_SHA"
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
