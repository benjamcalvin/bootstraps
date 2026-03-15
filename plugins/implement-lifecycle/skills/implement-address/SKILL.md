---
name: implement-address
description: Address filtered review findings for implement workflow (runs as subagent)
context: fork
agent: general-purpose
argument-hint: <pr-number> <round-number> <findings-file-path>
license: MIT
metadata:
  version: "2.0.1"
  tags: ["implement", "address", "subagent"]
  author: benjamcalvin
---

# Address Review Findings — Round $1

Address filtered review findings on PR #$0, round $1.

## PR Context

- PR metadata: !`gh pr view $0`
- Filtered findings: !`cat $2`

## Instructions

You are the **addresser** for the `/implement` workflow. You fix issues identified by the review, run tests, and push fixes. The filtered findings above contain only findings the referee accepted — address these and only these.

**Guard:** If the findings file is missing, unreadable, or contains no findings, stop immediately and report the issue to the orchestrator. Do not proceed with an empty or absent findings list.

Use the **Task tools** (`TaskCreate`, `TaskUpdate`) to track progress.

### Step 1: Understand Each Finding

Read the filtered findings in the Context section above. For each finding:
1. Understand what the reviewer identified and at what severity
2. Read the relevant code using the Read tool — understand the full context, not just the flagged line

### Step 2: Address Each Finding

For each finding, take one of these actions:

**Apply** — The finding is correct. Make the change.
- Edit the code
- Note what was changed

**Partially apply** — The core insight is right but the suggested fix isn't optimal.
- Implement a better fix that addresses the underlying concern
- Explain why you deviated from the exact suggestion

**Reject with justification** — The finding is incorrect or doesn't apply after deeper investigation.
- Explain clearly why the current code is correct
- Reference specs, ADRs, or project conventions to support your reasoning
- Never reject without a concrete justification

**Escalate** — You're unsure whether the finding is valid.
- Flag it in your summary with the evidence for and against
- Do not guess or silently skip

### Step 3: Run Full Verification

After addressing all findings:

1. **Run the full test suite and linters.** Every test must pass. Every lint must pass. If tests fail, fix the code — not the tests.
2. **Spot-check your changes** — Read through your own diff. Did you introduce any new issues while fixing the review feedback?

### Step 4: Commit and Push

- Commit with message format: `fix: address review round $1 — <description>`
- Keep fix commits separate when addressing unrelated findings
- Push to the PR branch:
  ```bash
  git push
  ```

### Step 5: Post Summary and Return

Post your summary to the PR:
```
gh pr comment $0 --body "<summary>"
```

Return a summary table:

| # | Finding | Action | Details |
|---|---------|--------|---------|
| 1 | <brief description> | Applied / Partially applied / Rejected / Escalated | <what was done and why> |

**Tests:** <command> — <result>
**Commits:** <list of fix commit messages>
