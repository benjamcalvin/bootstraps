---
name: verify
description: >-
  Devise and execute manual verification for a PR's changes (runs as subagent).
  Determines what to verify based on change type, runs real commands, and reports
  structured evidence.
context: fork
agent: general-purpose
argument-hint: <pr-number>
license: MIT
metadata:
  version: "1.0.0"
  tags: ["verify", "manual", "testing", "subagent"]
  author: benjamcalvin
---

# Manual Verification

Verify PR #$ARGUMENTS with real-world execution.

## PR Context

- PR metadata: !`gh pr view $ARGUMENTS`
- Changed files: !`gh pr view $ARGUMENTS --json files --jq '.files[] | "\(.path) (+\(.additions)/-\(.deletions))"'`

## Instructions

You are the **verification agent** for the implementation lifecycle. Code review and automated tests catch logic and style issues — your job is to catch integration and runtime bugs by actually running the feature. You are the last line of defense before merge.

Use the **Task tools** (`TaskCreate`, `TaskUpdate`) to track progress.

### Step 1: Classify the Change

Read the PR description and changed files above. Determine the change type:

| Change type | Verification required? |
|-------------|----------------------|
| **CLI commands / scripts** | Yes — run with representative inputs |
| **API endpoints** | Yes — start server, hit endpoints |
| **Configuration changes** | Yes — start service, observe behavior |
| **Database migrations** | Yes — apply, verify schema, rollback |
| **Build system changes** | Yes — run the build, verify artifacts |
| **Library code / refactoring** | Maybe — only if it produces observable side effects |
| **Documentation only** | No — report "N/A" and return |

If the change doesn't produce any runnable artifacts, report that no manual verification is needed and return immediately.

### Step 2: Check for Existing Evidence

Read the PR description's "Manual verification" section and any PR comments. Look for verification evidence that includes all three parts:

1. **Command** — exact command that was run
2. **Output** — complete, unedited output
3. **Explanation** — what the output demonstrates

If adequate evidence already exists, verify it's plausible (not fabricated), report that verification evidence is present, and return.

### Step 3: Devise a Verification Plan

Based on the change type and the specific changes made, design a concrete verification plan:

1. **Identify what to verify** — What behavior should be observable after these changes? What would a user/operator actually do?
2. **Plan the happy path** — What commands demonstrate the feature working correctly?
3. **Plan at least one error case** — What happens with invalid input, missing dependencies, or unexpected state?
4. **Identify prerequisites** — What services need to be running? What setup is needed?

### Step 4: Execute Verification

Run your verification plan. For each step:

1. **Set up prerequisites** — Start any required services, create test data, configure the environment.
2. **Run the verification command** — Execute exactly what a user/operator would do.
3. **Capture the full output** — Do not edit, truncate, or summarize. Include exit codes.
4. **Verify the result** — Does the output match expectations? Are side effects correct (files created, database updated, etc.)?
5. **Run the error case** — Verify the system handles bad input gracefully.

If a verification step fails:
- Note exactly what failed and what was expected
- Check if it's a real bug or an environment issue
- Do NOT fix the bug yourself — report it

### Step 5: Report Findings

Post your verification results to the PR:

```
gh pr comment $ARGUMENTS --body "<results>"
```

Return findings in this structure:

```
## Manual Verification — PR #<number>

### Verdict: PASS / FAIL / PARTIAL / N/A

### Evidence

#### <Test description>
**Command:**
```
<exact command>
```
**Output:**
```
<complete output>
```
**Result:** PASS / FAIL — <explanation of what this demonstrates>

#### <Error case description>
**Command:**
```
<exact command with bad input>
```
**Output:**
```
<complete output>
```
**Result:** PASS / FAIL — <explanation>

### Issues Found
<list any bugs discovered, or "None">

### Notes
<any caveats, environment-specific observations, or suggestions>
```

If verification is not applicable (docs-only, pure refactor with no observable change), return:

```
## Manual Verification — PR #<number>

### Verdict: N/A

No runnable artifacts changed. Automated tests are sufficient for this change.
```
