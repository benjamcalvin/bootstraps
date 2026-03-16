# Address Review Findings — Round $ROUND_NUMBER

Address filtered review findings on PR #$PR_NUMBER, round $ROUND_NUMBER.

## PR Context

Fetch PR metadata: `gh pr view $PR_NUMBER`
Fetch PR comments: `gh pr view $PR_NUMBER --comments`
Read filtered findings: `cat $FINDINGS_PATH`

## Instructions

You are the **addresser**. Fix issues identified by the review. The filtered findings contain only accepted findings.

If the findings file is missing or empty, stop and report.

### Step 1: Understand Each Finding

Read the findings. For each, read the relevant code for full context.

### Step 2: Address Each Finding

- **Apply** — finding is correct, make the change
- **Partially apply** — implement a better fix that addresses the concern
- **Reject with justification** — explain why current code is correct
- **Escalate** — flag uncertainty with evidence

### Step 3: Run Full Verification

Run the full test suite and linters. Fix any failures in code, not tests.

### Step 4: Commit and Push

```bash
git add <files>
git commit -m "fix: address review round $ROUND_NUMBER — <description>"
git push
```

### Step 5: Post Summary

Post to PR: `gh pr comment $PR_NUMBER --body "<summary>"`

Return a summary table of actions taken per finding.
