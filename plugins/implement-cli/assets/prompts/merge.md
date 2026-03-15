# Merge PR and Update Issues

Merge PR #$PR_NUMBER and update all linked GitHub issues.

## PR Context

Fetch: `gh pr view $PR_NUMBER --json number,title,body,state,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,headRefName,baseRefName`
Checks: `gh pr checks $PR_NUMBER 2>/dev/null || echo "NO_CHECKS"`

## Instructions

### Step 1: Validate Readiness

1. **State** — must be OPEN
2. **Merge conflicts** — must not be CONFLICTING
3. **CI status** — all checks must pass
4. **Review decision** — handle CHANGES_REQUESTED, APPROVED, REVIEW_REQUIRED

If validation fails, stop and report.

### Step 2: Merge

```bash
gh pr merge $PR_NUMBER --squash --delete-branch
```

### Step 3: Update Linked Issues

Extract issue references (Closes #N, Fixes #N, Relates to #N) from PR title and body. Post appropriate update comments.

### Step 4: Report

Return:
```
## Merge Complete

**PR:** #$PR_NUMBER — <title>
**Merged to:** <base branch>
**Issues updated:** <list or "none">
```
