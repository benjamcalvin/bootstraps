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

At runtime, parse the PR number and the explicitly passed temporary handoff-artifact path, read that JSON object, and fetch the PR metadata, comments, and checks. If the path is absent, unreadable, or does not contain a complete `verification-record:v1` plus its referenced `suite-evidence`, stop rather than reconstructing evidence from an inaccessible parent transcript.

## Instructions

### Step 1: Validate Readiness

Before evaluating readiness, read explicit user direction and the target repository's governing instructions, branch-protection/ruleset configuration when accessible, and documented contribution policy. Enforced repository constraints are binding. Explicit user direction may select only among choices those constraints permit; it cannot waive or contradict them. If repository policy and user direction cannot be reconciled, stop the merge and report the conflict. Apply this precedence consistently to required checks, approvals, billing exceptions, merge method, and branch retention. Bundled fallbacks apply only when both sources are silent. Do not infer policy from this plugin's source repository.

Check that the PR is safe to merge. For each check, determine pass/fail:

1. **State** — PR must be `OPEN`. If already merged or closed, report and stop.
2. **Merge conflicts** — `mergeable` must not be `CONFLICTING`. If conflicts exist, report and stop.
3. **CI status** — Enforce the checks required by binding target-repository policy; user direction may request additional checks but may not waive required ones. Report every blocking failure and stop. A billing or account-status failure remains blocking unless repository policy permits that exception, or policy is silent and explicit user direction permits it; an exception is never global. Even when permitted, classify the failure as billing-only only when the run or job carries an explicit billing/payment signal. Never infer billing from timing, and record every applied exception.
4. **PR standards** — Invoke the canonical `pr-check` skill with a fresh isolated context using the active harness adapter:
   - **Claude Code:** use the Task/subagent facility, explicitly load the canonical `pr-check` skill, and provide the PR plus freshly read repository-policy context.
   - **Codex:** spawn a fresh subagent, instruct it to load the canonical `pr-check` skill, and provide the PR plus freshly read repository-policy context.
   - **Pi:** use `pi-subagents` with `context: "fresh"`, explicitly select the canonical `pr-check` skill, and provide the PR plus freshly read repository-policy context.
   - **Generic:** use the client's isolated delegation mechanism with a fresh context and explicit canonical `pr-check` skill selection; do not emulate a subagent inline.

   Capture and evaluate the returned `pr-check` result. If isolated dispatch, fresh context, explicit skill loading, or result capture is unavailable, fail closed and report the readiness step instead of running an improvised substitute. Apply the target repository's blocking standards. Bundled checks are fallbacks only when repository policy is silent. The bundled scope note remains advisory unless target policy makes scope a gate.
5. **Review decision** — Check `reviewDecision` and the approval rule established from repository policy and explicit user direction:
   - If `CHANGES_REQUESTED`, stop and report.
   - If repository policy requires approvals, require the declared number and kind; user direction may require additional approvals but may not reduce or waive the repository minimum. Otherwise stop and report the missing approval.
   - If the established policy does not require approval, do not invent a requirement from the base branch name. Proceed autonomously when the other gates pass.
6. **Exact-head verification evidence** — Read the explicitly handed-off temporary JSON object and require its canonical `verification-record:v1` fields to match the complete record in the latest verification PR comment. Require `verification-record: v1`, `verification-head`, `suite-result`, `suite-command`, `suite-executions`, `suite-exit-status`, and `suite-command-results`. Independently establish the target repository's authoritative command or ordered command plan from the same target sources used by verification. Fetch the current `headRefOid` and require it to equal `verification-head`. Accept `pass` only when `suite-command` exactly matches that established command or ordered JSON command array, with the same command boundaries and order, exactly one plan execution, original overall exit status 0, and ordered per-command results whose exact commands match every command in the plan and whose results/statuses are `pass`/zero. For every result, require its `#/suite-evidence/command-<N>` pointer to resolve inside the handed-off object's `suite-evidence`; require the resolved entry's exact command to match and its output to be a nonempty string. Reject pointers outside the handed-off object, dangling or mismatched entries, different commands, reordered plans, missing command results, wrappers, arguments, prefixes, suffixes, stale or mismatched handoff/comment records, `missing-contract`, or evidence when no target contract can be established. Accept `not-required` only after independently inspecting the changed files and confirming that every change is documentation or comments only, with command `none`, zero executions, status `n/a`, an empty results list, and empty `suite-evidence`. Reject every other combination. Store the matching head as `VERIFIED_SHA`. Do not execute the authoritative command or plan during merge readiness checks; validation reads verification's handed-off record and output only.

**If validation fails**, stop and report exactly what needs to be fixed. Do not merge.

**If validation requires human judgment** (e.g., a check is flaky, unresolved conversations), stop and consult the user with the evidence.

### Step 2: Merge

Select the merge method and branch behavior established before readiness. Repository-required or repository-prohibited methods and retention behavior remain binding; user direction selects among permitted methods and may choose branch behavior only when repository policy permits it. An unresolved conflict stops the merge. Use the corresponding supported GitHub CLI method flag (`--merge`, `--squash`, or `--rebase`). Add `--delete-branch` only when the resolved policy calls for deletion; omit it when the branch must be retained. When policy and user direction are both silent, use an enabled repository merge method and retain the branch.

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
