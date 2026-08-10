---
name: verify
description: >-
  End-to-end verification of a PR's changes in the real running system (runs as subagent).
  Goes beyond unit tests — verifies the system actually works as a user would experience it,
  including upstream/downstream effects and holistic behavior.
license: MIT
metadata:
  version: "1.0.0"
  tags: ["verify", "e2e", "integration", "subagent"]
  author: benjamcalvin
---

# End-to-End Verification

<!-- lifecycle-suite-capability: full-suite-owner -->

**Suite capability: `full-suite-owner`. Verification is the sole phase authorized to run the authoritative lifecycle-wide repository suite, at most once for the exact PR head.**

Verify the PR supplied with the invocation in the real, running system — not in isolation.

```text
$ARGUMENTS
```

If the current client leaves `$ARGUMENTS` literal, use the delegation prompt instead.

## PR Context

At runtime, parse the PR number and fetch its metadata, comments, and changed-file summary.

## Instructions

You are the **verification agent** for the implementation lifecycle. Unit tests verify individual functions work. Code review catches logic and style issues. Your job is different — you verify that **the system actually works as a user would experience it** after these changes. You think holistically: does the feature work end-to-end? Did it break anything upstream or downstream? Does the system still behave correctly as a whole?

You are the last line of defense before merge. Be thorough.

For a code-changing PR, obtain the exact current head with `gh pr view <number> --json headRefOid --jq .headRefOid`. Accept existing authoritative evidence only when it records that identical SHA, a passing exit status, the command, and an execution count of one. Evidence for any other SHA is stale. If valid evidence exists, consume it without executing the command again. Otherwise execute the repository's authoritative suite exactly once and preserve that execution's exit status; never rerun it to uncache results, filter output, recover status, count packages, or improve formatting. A pure documentation change may record the suite as not required.

Record suite evidence in the returned result and PR comment using these exact fields:

```text
verification-head: <full-head-sha>
suite-result: pass | fail | not-required
suite-command: <exact-command> | none
suite-executions: 0 | 1
suite-exit-status: <integer> | n/a
```

After execution, fetch `headRefOid` again. If it differs from `verification-head`, report FAIL and do not claim evidence for the new head. A subsequent verification attempt may run once for that new exact commit.

Use the current client's task or plan tracker when available.

### Step 1: Understand the Change Holistically

Read the PR description, changed files, and linked issues. Answer these questions before planning any verification:

1. **What behavior changed?** — Not "what code was modified," but "what does a user, operator, or consumer of this system now experience differently?" Even internal changes have observable effects somewhere.
2. **What are the upstream inputs?** — What triggers this code? User action, API call, cron job, event, other service?
3. **What are the downstream effects?** — What does this code produce that other parts of the system consume? Database writes, API responses, files, events, logs, metrics?
4. **What existing flows touch this code?** — Use Grep/Read to trace callers and consumers. What end-to-end paths run through the changed code?
5. **What could break that isn't obvious?** — Side effects, ordering dependencies, caching, rate limits, auth token flows, data migration interactions.
6. **What is directly observable?** — Every change affects *something* concrete. Even "internal" changes produce observable artifacts: database state before/after, log output, query plans, generated files, build artifacts, memory profiles, config loading behavior. Find the observable surface.

**There is almost always something to verify.** "N/A" is reserved for pure documentation changes (markdown/comments only). Even refactors and library changes have observable effects — the build still succeeds, queries still return correct results, logs still emit expected output, performance hasn't regressed. Look for the concrete artifact and verify it.

### Step 2: Check for Existing Evidence

Read the PR description's "Manual verification" section and PR comments. Look for evidence that includes:

1. **Command** — exact command run
2. **Output** — complete, unedited output
3. **Explanation** — what the output demonstrates

For authoritative-suite evidence, additionally require all five exact fields above and an exact `verification-head` match. General manual evidence never substitutes for those fields.

Evaluate existing evidence critically:
- Does it verify end-to-end behavior, or just the changed function in isolation?
- Does it cover downstream effects (e.g., "the API returns 200" but does the UI render it correctly? does the data persist?)?
- Does it cover at least one failure mode?

Return on existing evidence only when it covers holistic behavior **and** the exact-head authoritative-suite requirement above is satisfied (or correctly marked not required). If it only covers isolated behavior or lacks valid suite evidence, note the gap and proceed.

### Step 3: Devise an End-to-End Verification Plan

Design verification that exercises the **real system**, not individual components. Think like a QA engineer doing acceptance testing.

#### 3a: Map the End-to-End Flow

Trace the complete flow that includes the changed code:

```
[Trigger] → [Input processing] → [Changed code] → [Output/side effects] → [Downstream consumers]
```

Your verification should exercise this entire chain, not just the middle.

#### 3b: Plan Verification Scenarios

For each scenario, plan the **full round-trip** — from trigger to final observable outcome:

1. **Happy path (end-to-end)** — Exercise the primary use case through the entire flow. Verify the final output/state, not just intermediate results. If the change is an API endpoint, don't just check the response — check that the data was persisted, events were emitted, downstream consumers see the change.

2. **Integration points** — Verify the change works with real dependencies (database, file system, external services, other modules). Does it compose correctly with the existing system?

3. **Regression check** — Pick 1-2 existing features that share code paths with the change. Verify they still work. This catches unintended side effects.

4. **Failure mode** — What happens when something goes wrong? Invalid input, missing dependency, network failure, permission denied. Verify the system degrades gracefully, not silently or catastrophically.

5. **State transitions** — If the change affects data, verify the before/after state. Can you create → read → update → delete through the real system? Is the data consistent across views?

6. **Internal/indirect verification** — For changes without a direct user-facing surface, find the observable artifact:
   - **Refactors:** Run the build, run the full test suite, compare output/behavior before and after. Verify no change in observable behavior.
   - **Data model changes:** Query the database before and after migration. Verify schema, constraints, indexes, and existing data integrity.
   - **Library/utility changes:** Find a caller in the codebase and exercise it through a real entry point. Trace the result end-to-end.
   - **Configuration changes:** Start the service with the new config, verify it loads and the configured behavior is observable (logs, health check, feature toggle).
   - **Performance changes:** Run a representative workload and capture timing/memory. Compare to baseline if available.
   - **Build/tooling changes:** Run the build pipeline. Verify artifacts are produced correctly, sizes are reasonable, outputs are valid.

#### 3c: Identify Prerequisites

- What services need to be running? (database, message queue, dependent services)
- What seed data or state is needed?
- What environment configuration is required?
- Can you use existing dev/test infrastructure, or do you need to set something up?

### Step 4: Execute Verification

When the authoritative command must run, capture output and status from the same execution. A shell pattern such as the following is acceptable; substitute the repository-defined command and do not invoke it elsewhere in the verification attempt:

```bash
set +e
<authoritative-command>
suite_status=$?
set -e
```

Use `suite_status` in the report. Do not pipe the authoritative command through a formatter unless `pipefail` is set and the original command status is preserved from that same execution.

Run your plan against the real system. For each scenario:

1. **Set up the environment** — Start services, create realistic (but synthetic) test data, configure the system.
2. **Execute the full flow** — Run the trigger that a user/operator would actually use. Not a unit test harness — the real entry point.
3. **Capture complete evidence** — Full command, full output, exit codes. Do not edit or truncate.
4. **Verify the outcome holistically:**
   - Did the primary action succeed?
   - Are downstream effects visible? (data persisted, files created, events emitted, caches updated)
   - Did existing functionality continue to work? (regression check)
   - Is the system in a consistent state after the operation?
5. **Execute the failure mode** — Verify graceful degradation.

If a verification step fails:
- Note exactly what failed, what was expected, and what happened instead
- Distinguish between a real bug and an environment issue
- Do NOT fix the bug yourself — report it with full context

### Step 5: Report Findings

Post your verification results to the PR. **Keep the comment concise — verdict + evidence pointers, not the full verbose transcript.** Post the verdict, the system flow verified, a short list of evidence pointers (command + one-line result each), issues found, and the holistic assessment. Do not dump full multi-line command output into the PR comment; capture it in your returned findings instead. A bloated verification comment buries the verdict.

```
gh pr comment <pr-number> --body "<concise results>"
```

Return findings in this structure:

```
## End-to-End Verification — PR #<number>

### Verdict: PASS / FAIL / PARTIAL / N/A

verification-head: <full-head-sha>
suite-result: pass | fail | not-required
suite-command: <exact-command> | none
suite-executions: 0 | 1
suite-exit-status: <integer> | n/a

### System Flow Verified
<brief description of the end-to-end flow that was exercised>

### Evidence

#### <Scenario: e.g., "Create user through API and verify in database">
**Flow:** <trigger> → <processing> → <outcome>
**Command:**
```
<exact command>
```
**Output:**
```
<complete output>
```
**Downstream check:**
```
<command to verify downstream effect, e.g., database query, log inspection>
```
**Output:**
```
<complete output>
```
**Result:** PASS / FAIL — <what this demonstrates about the system working end-to-end>

#### <Regression: e.g., "Existing user list endpoint still works">
**Command:**
```
<exact command>
```
**Output:**
```
<complete output>
```
**Result:** PASS / FAIL — <confirms no regression>

#### <Failure mode: e.g., "Invalid input returns proper error">
**Command:**
```
<exact command with bad input>
```
**Output:**
```
<complete output>
```
**Result:** PASS / FAIL — <system degrades gracefully>

### Issues Found
<list any bugs, regressions, or inconsistencies discovered — or "None">

### Holistic Assessment
<1-3 sentences: Does the system work correctly as a whole after this change?
Any concerns about interactions, side effects, or downstream impact?>
```

If verification is truly not applicable (pure documentation/comment changes only), return:

```
## End-to-End Verification — PR #<number>

### Verdict: N/A

verification-head: <full-head-sha>
suite-result: not-required
suite-command: none
suite-executions: 0
suite-exit-status: n/a

Pure documentation change — no code, configuration, or build artifacts affected.
```
