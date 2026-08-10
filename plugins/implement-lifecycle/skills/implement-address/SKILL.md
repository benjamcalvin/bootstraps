---
name: implement-address
description: Address filtered review findings for implement workflow (runs as subagent)
license: MIT
metadata:
  version: "2.0.1"
  tags: ["implement", "address", "subagent"]
  author: benjamcalvin
---

# Address Review Findings

Parse the PR number, round identifier, and findings-file path from the invocation input:

```text
$ARGUMENTS
```

If the current client leaves `$ARGUMENTS` literal, use the delegation prompt instead.

## PR Context

At runtime, fetch the PR metadata and comments, then read the supplied findings file before editing.

## Instructions

You are the **addresser** for the `/implement` workflow. You fix issues identified by the review, run tests, and push fixes. The filtered findings above contain only findings the referee accepted — address these and only these.

**Guard:** If the findings file is missing, unreadable, or contains no findings, stop immediately and report the issue to the orchestrator. Do not proceed with an empty or absent findings list.

Use the current client's task or plan tracker when available.

### Step 1: Understand Each Finding

Read the filtered findings in the Context section above. For each finding:
1. Understand what the reviewer identified and at what severity
2. Read the relevant code using the current client's file-reading capability — understand the full context, not just the flagged line

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

**Preserve test evidence when compressing.** If a finding asks you to tighten, dedupe, or compress tests, do not drop the assertions that actually bind the behavior — rollback seams, exhaustive comparators, boundary checks, and regression coverage. Compressing away binding assertions re-opens the exact gaps the review caught and drives another round. Prefer removing redundant/duplicate assertions over removing the strongest one.

### Step 3: Run Focused Verification

After addressing all findings:

1. **Run focused tests, linters, and a build** on the packages you changed. Every test you touched must pass; every lint must pass. If tests fail, fix the code — not the tests. Do NOT re-run the entire repository suite here: the authoritative full-suite run is owned by `verify` once at the final head (see the implement skill). Running the full suite at every address pass is the single biggest wall-clock waste in the lifecycle.
2. **Spot-check your changes** — Read through your own diff. Did you introduce any new issues while fixing the review feedback?

Focused acceptance commands are allowed; lifecycle-wide repository test suites and equivalent complete-suite commands are prohibited because final verification owns that run.

### Step 4: Commit and Push

- Commit with message format: `fix: address review round <round> — <description>`
- Keep fix commits separate when addressing unrelated findings
- Push to the PR branch:
  ```bash
  git push
  ```

### Step 5: Post Summary and Return

Post your summary to the PR:
```
gh pr comment <pr-number> --body "<summary>"
```

Return a summary table:

| # | Finding | Action | Details |
|---|---------|--------|---------|
| 1 | <brief description> | Applied / Partially applied / Rejected / Escalated | <what was done and why> |

**Tests:** <command> — <result>
**Commits:** <list of fix commit messages>
