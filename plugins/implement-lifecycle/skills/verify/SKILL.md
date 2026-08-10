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

**You are the single authoritative owner of the full test-suite run for this lifecycle.** Implementer and addresser run focused tests on their own changes; you run or consume valid evidence for the complete suite against the final head as part of verification. Do not delegate the full-suite run to earlier phases. **The full-suite run is conditional on change type:** for a pure documentation change (markdown/comments only) the full suite is not required — that is the N/A path below.

For any code change, enforce this exact-head execution discipline:

1. **Record the final commit SHA before selecting commands.**
2. Search the delegation payload, orchestration notes, PR description, and comments for a durable authoritative-suite record containing the command, commit SHA, original exit status, and an output/evidence pointer.
3. **Any complete authoritative-suite result, passing or failing, consumes the one-run allowance when its recorded commit SHA exactly matches that final commit.** Reuse a passing result; report a nonzero result as verification failure without rerunning it.
4. When no matching execution record exists, perform the authoritative run. **Execute the authoritative full-suite command at most once for that commit.** Capture output and the original exit status from that single execution. Use a shell form that records the status immediately while preserving it as the verification outcome.
5. **Do not rerun it to uncache results, filter output, recover an exit status, count results, or improve report formatting.** Derive any presentation summary from the captured output. If the single execution's evidence is incomplete, report verification as incomplete or failed instead of executing the suite again.
6. Immediately after the execution, fetch the current PR head again. If it differs from the recorded commit, preserve the stale commit's evidence record, report that the current head remains unverified, and do not reuse or rerun the suite for the stale commit.
7. Return a concise durable evidence record with the command, verified commit SHA, original exit status, and an output/evidence pointer. The orchestrator must retain this record across fresh children and resumes and pass it to merge.

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

Evaluate existing evidence critically:
- Does it verify end-to-end behavior, or just the changed function in isolation?
- Does it cover downstream effects (e.g., "the API returns 200" but does the UI render it correctly? does the data persist?)?
- Does it cover at least one failure mode?

If evidence is adequate *and* covers holistic behavior, reuse it for those scenarios. For code changes, return only after the exact-head authoritative-suite requirement above is also satisfied. If the existing evidence only covers isolated behavior, note the gap and proceed.

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

Post your verification results to the PR. **Keep the main comment concise — verdict + evidence pointers, not an expanded verbose transcript.** The comment must contain the durable authoritative-suite record: command, verified commit SHA, original exit status, and a stable output/evidence pointer. Prefer an existing CI log or artifact URL as the pointer. When no durable external pointer exists for a locally executed suite, preserve its complete output in a collapsed `<details>` block in the same PR comment and point the record to that block. This keeps the evidence discoverable across fresh children and resumed runs without obscuring the verdict.

```
gh pr comment <pr-number> --body "<concise results>"
```

Return findings in this structure:

```
## End-to-End Verification — PR #<number>

### Verdict: PASS / FAIL / PARTIAL / N/A

### Final Commit
<exact commit SHA verified>

### Authoritative Suite
<command, verified commit SHA, original exit status, output/evidence pointer, and whether the evidence was reused or executed once>

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

Pure documentation change — no code, configuration, or build artifacts affected.
```
