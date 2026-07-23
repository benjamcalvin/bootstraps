---
name: implement-address
description: Address filtered review findings for implement workflow (runs as subagent)
context: fork
agent: general-purpose
argument-hint: <pr-number> <round-identifier> <findings-file-path>
license: MIT
metadata:
  version: "2.1.2"
  tags: ["implement", "address", "subagent"]
  author: benjamcalvin
---

# Address Review Findings

Parse the PR number, round identifier, and findings-file path from the invocation input. Round identifiers are `<N>` for code review, `docs-<N>` for docs compliance, or `verification-<N>` for end-to-end verification.

Claude Code expands the invocation payload below. In Codex, it may remain literal; when that happens, use the delegation prompt instead.

```text
$ARGUMENTS
```

## PR Context

At runtime, fetch the PR metadata and comments with `gh pr view`, then read the supplied findings file before editing code.

## Instructions

You are the **addresser** for the `/implement` workflow. You fix issues identified by code review, docs compliance, or end-to-end verification, run tests, and push fixes. The supplied findings file contains only findings the orchestrator accepted or structured verification failures — address these and only these.

**Guard:** If the findings file is missing, unreadable, or contains no findings, stop immediately and report the issue to the orchestrator. Do not proceed with an empty or absent findings list.

Preserve the round context in your result. A successful code-review address is validated by the orchestrator as `address` and returns to `review`; docs uses `docs-address` and returns to `docs`; verification uses `verification-address` and returns to `verify`. Do not send a `verification-<N>` result to reviewer dispatch.

Use the current client's task or plan tracker when available. Keep the plan truthful and proceed without one when the client exposes no tracker.

### Step 1: Understand Each Finding

Read the filtered findings in the Context section above. For each finding:
1. Understand what the reviewer identified and at what severity
2. Read the relevant code with the current client's file-reading capability — understand the full context, not just the flagged line

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

- Commit with message format: `fix: address review round <round> — <description>`
- Keep fix commits separate when addressing unrelated findings
- Push to the PR branch:
  ```bash
  git push
  ```

### Step 5: Post Summary and Return

Write the summary to a temporary Markdown file and post it with `gh pr comment <pr-number> --body-file <path>`.

Return a summary table:

| # | Finding | Action | Details |
|---|---------|--------|---------|
| 1 | <brief description> | Applied / Partially applied / Rejected / Escalated | <what was done and why> |

**Tests:** <command> — <result>
**Commits:** <list of fix commit messages>
