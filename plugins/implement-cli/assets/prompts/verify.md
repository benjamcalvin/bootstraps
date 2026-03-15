# End-to-End Verification

Verify PR #$PR_NUMBER works in the real, running system.

## PR Context

Fetch: `gh pr view $PR_NUMBER`
Changed files: `gh pr view $PR_NUMBER --json files --jq '.files[] | "\(.path) (+\(.additions)/-\(.deletions))"'`

## Instructions

You verify that the **system actually works as a user would experience it** after these changes. Think holistically.

### Step 1: Understand the Change

1. What behavior changed?
2. What are upstream inputs and downstream effects?
3. What existing flows touch this code?
4. What could break that isn't obvious?

### Step 2: Check Existing Evidence

Read the PR description's manual verification section. Evaluate critically.

### Step 3: Plan Verification

- Happy path end-to-end
- Integration points
- Regression check
- Failure mode
- State transitions

### Step 4: Execute

Run verification against the real system. Capture full evidence.

### Step 5: Report

Post to PR: `gh pr comment $PR_NUMBER --body "<results>"`

Return:
```
## End-to-End Verification — PR #$PR_NUMBER

### Verdict: PASS / FAIL / PARTIAL / N/A

### Evidence
<scenarios with commands, output, and results>

### Issues Found
<list or "None">
```
