---
name: verify
description: >-
  End-to-end verification of a PR's changes in the real running system (runs as subagent).
  Exercises the changed behavior live, scaled to the PR's tier, and owns the exact-head
  authoritative-suite evidence.
license: MIT
metadata:
  version: "1.0.0"
  tags: ["verify", "e2e", "integration", "subagent"]
  author: benjamcalvin
---

# End-to-End Verification

<!-- lifecycle-suite-capability: full-suite-owner -->

**Suite capability: `full-suite-owner`. Verification is the sole phase authorized to execute or consume the target repository's authoritative verification command or ordered command plan, at most once for the exact PR head.**

Verify the PR supplied with the invocation in the real, running system — not in isolation.

```text
$ARGUMENTS
```

If the current client leaves `$ARGUMENTS` literal, use the delegation prompt instead.

## PR Context

At runtime, parse the PR number, tier, and any failed-scenario list from the payload, then fetch the PR metadata, comments, and changed-file summary.

## Instructions

You are the **verification agent** for the implementation lifecycle. Confirm the changed behavior works in the real system as a user, operator, or consumer experiences it, and that the authoritative suite holds for the exact head.

**Scale to the payload's tier** (Medium when absent): **Small** — suite evidence, plus one live check only when runtime behavior changed (a code or configuration path that executes at runtime, not docs or tests alone); otherwise Small may PASS on suite evidence alone and the report states `live check skipped (Small, no runtime change)`; **Medium** — live scenarios for the changed behavior; **Large** — the full Step 3 plan, including regressions and failure modes. **Re-verification**: when the payload names failed scenarios, re-run only those scenarios plus suite evidence for the new head; without `failed-scenarios`, re-run suite evidence only.

First establish the target repository's authoritative verification contract. Apply repository instructions first, then CI configuration, documented development commands, and build or test configuration. Use an explicit command when the repository declares one. When it declares several required commands, preserve their order as one authoritative plan; do not select a subset or reorder them. Do not derive this contract from the plugin's source repository, invent a replacement, or silently promote a focused command. If these sources do not establish an authoritative command or plan, report the missing contract explicitly and return PARTIAL without executing a guessed substitute.

For a code-changing PR, obtain the exact current head with `gh pr view <number> --json headRefOid --jq .headRefOid`. Any complete authoritative evidence record for that identical SHA consumes its one-execution allowance, whether the recorded result passed or failed. A complete record has the exact command or ordered plan, an execution count of one (zero for `suite-source: ci`), the original overall exit status, and the corresponding `pass`/zero-status or `fail`/nonzero-status result. Independently establish the target contract before consuming evidence. Consume a complete passing record only when its command or plan exactly matches, and do not execute it again. For a complete failing record, return FAIL and require addressing that produces a new head before another authoritative execution. Apply the baseline rule first: a record whose failures are all pre-existing returns PARTIAL. Evidence for any other SHA is stale. If no complete evidence exists for the exact head, use eligible CI evidence or execute the established command or ordered plan exactly once. Preserve each command's output plus the plan's original exit status. Stop the plan at the first failure unless the target repository explicitly requires otherwise. Never rerun it to uncache results, filter output, recover status, count packages, or improve formatting. A pure documentation change may record verification as not required.

**CI evidence.** A target-repository required-CI run replaces execution only when every condition holds; a failing, other-SHA, other-repository, or unconfirmable run is not evidence, so execute instead. Parse the repository and run id from the run URL and fetch one attempt with `gh run view -R <owner>/<repo> <run-id> --attempt <n> --json headSha,conclusion,jobs,url`. Require: the repository is the target repository; `headSha` equals `verification-head`; that attempt's `conclusion` is `success`; and in every job or matrix leg with a step running a plan command, each established command maps, in order, to a step whose conclusion is `success`, never `skipped`. Reject the run if a plan step is conditional or `continue-on-error` in the workflow definition the run executed (for `pull_request` runs, the merge ref; the file at the head SHA is supplementary only). Wait for an in-progress run at most the suite's own typical runtime, and never more than 30 minutes, then execute. Record `suite-source: ci`, `suite-ci-run: <run-url>`, `suite-ci-attempt: <n>` (an integer ≥ 1; a CI record without one is rejected), `suite-executions: 0`, `suite-exit-status: 0`, and one `pass`/`0` result per command whose evidence entry names its job and step and holds that step's complete log from the same attempt (`gh run view <run-id> --attempt <n> --log`, or `--job <job-id> --log`). Never use a run for any other SHA.

**Baseline on failure.** When the head's suite fails, run each failing command once on the PR's merge-base (`git merge-base origin/<base> <head>`) in a separate checkout and record the results in `suite-baseline` with that SHA. This does not consume or reset the head's allowance; reuse a baseline already in the record. Match failures by identity (test names or rule ids): a failure present at both SHAs is pre-existing; any other failure, or one you cannot match, is PR-introduced and produces FAIL. A setup, missing-command, or error-class mismatch between the SHAs is PR-introduced. When every failure is pre-existing, return PARTIAL, list them under Issues Found, and name every plan command never run on the head because the plan stopped; the record keeps `suite-result: fail` and is not mergeable. Baseline results are never PR-head evidence.

Record suite evidence as a canonical `verification-record:v1` in both the returned result and PR comment using these exact fields:

```text
verification-record: v1
verification-head: <full-head-sha>
suite-result: pass | fail | missing-contract | not-required
suite-source: executed | ci
suite-ci-run: <run-url> | none
suite-ci-attempt: <n> | none
suite-command: <exact-command-or-ordered-JSON-command-array> | none
suite-executions: 0 | 1
suite-exit-status: <integer> | n/a
suite-command-results: <ordered-result-list> | []
suite-baseline: <merge-base-sha> <ordered-result-list> | none
```

An absent `suite-source` means `executed`; absent `suite-ci-run`, `suite-ci-attempt`, or `suite-baseline` means `none`.

For an ordered plan, follow those fields with a `suite-command-results` list that records each command actually executed, in order, with its exact command, `pass`/`fail` result, original exit status, and a JSON Pointer of the form `#/suite-evidence/command-<N>`. A passing plan must contain evidence for every declared command. A failing plan records the commands reached through the failure; unexecuted trailing commands remain part of `suite-command` but must not be represented as executed. For a single command, use the same one-entry list so the durable representation does not change shape. Baseline results use the same entry shape with pointers `#/suite-evidence/baseline-command-<N>`.

The returned result must also contain one temporary handoff-artifact JSON object. It preserves the canonical record semantically and adds a `suite-evidence` object: comment values `none` and `n/a` serialize as JSON `null`, `suite-baseline` serializes as `{"head":"<merge-base-sha>","command-results":[...]}`, and `suite-command-results` remains an ordered JSON array of structured result objects. Each result's pointer must resolve under that same artifact's `suite-evidence` object to an entry whose `command` exactly matches its result entry and whose `output` contains that command's complete, unedited output. The PR comment includes the canonical fields and pointers but omits `suite-evidence`, keeping verbose output out of persistent storage. The lifecycle orchestrator writes the returned handoff-artifact object byte-for-byte to a temporary file and passes that file to the fresh merger; do not point at headings, the parent transcript, or any artifact that is not included in that explicit handoff.

The missing-contract/PARTIAL record is canonical: `suite-result: missing-contract`, `suite-command: none`, `suite-executions: 0`, `suite-exit-status: n/a`, and an empty `suite-command-results` list. This state is not mergeable. A documentation-only N/A record uses the same command, execution, status, and empty-results values with `suite-result: not-required`.

After execution, fetch `headRefOid` again. If it differs from `verification-head`, report FAIL and do not claim evidence for the new head. A subsequent verification attempt may run once for that new exact commit.

Use the current client's task or plan tracker when available.

### Step 1: Understand the Change

Read the PR description, changed files, linked issues, and the context bundle. Identify what a user, operator, or consumer now experiences differently, what triggers the changed code, what it produces downstream, and what is directly observable (responses, persisted state, files, logs, build artifacts). Trace callers with search tools.

### Step 2: Check for Existing Evidence

Read the PR description's "Manual verification" section and PR comments for evidence with the exact command, complete unedited output, and what it demonstrates. Reuse it for a scenario only when it exercises that behavior end to end at the current head. For authoritative-suite evidence, additionally require the complete canonical record above and an exact `verification-head` match. General manual evidence never substitutes for those fields.

### Step 3: Plan Scenarios

Size the plan by tier. Each scenario runs the real entry point end to end — trigger → changed code → observable outcome — and checks the final state, not an intermediate result:

- **Changed behavior** (Medium and Large; one check for Small when runtime behavior changed): the primary use case through the real flow, including downstream effects such as persisted data, emitted events, or generated files.
- **Regression** (Large): one or two existing flows that share code paths with the change.
- **Failure mode** (Large): invalid input, a missing dependency, or denied permission degrades gracefully.

Without a user-facing surface, exercise the nearest observable artifact: a real caller of a library change, the service started with the changed configuration, the produced build artifact, or before/after schema and data for a migration. For refactors or performance changes, compare before and after on the nearest observable artifact. Use existing dev/test infrastructure.

### Step 4: Execute Verification

When the authoritative command or ordered plan must run, capture output and status from that same execution. A shell pattern such as the following is acceptable for a single command; substitute the target-repository command and do not invoke it elsewhere in the verification attempt. For an ordered plan, apply the same status-preserving rule to each declared command, execute the plan once in order, and record the exact commands actually reached:

```bash
set +e
<authoritative-command>
suite_status=$?
set -e
```

Use `suite_status` in the report. Do not pipe the authoritative command through a formatter unless `pipefail` is set and the original command status is preserved from that same execution.

For each scenario, set up the environment with synthetic data, run the real entry point, capture the full command, output, and exit code without editing or truncation, and check the final observable state.

If a step fails, report what failed, expected versus actual, and whether it is a real bug or an environment issue. Do NOT fix it yourself.

### Step 5: Report Findings

Post your verification results to the PR. **Keep the comment concise — verdict + the complete durable `verification-record:v1`, not the full verbose transcript.** Include every exact command, result, original status, and evidence pointer. Return the handoff-artifact JSON with every pointer resolved to its unedited output; the fresh merger receives that object through its temporary file rather than relying on the comment or parent transcript. A bloated verification comment buries the verdict.

```
gh pr comment <pr-number> --body "<concise results>"
```

Return findings in this structure:

```
## End-to-End Verification — PR #<number>

### Verdict: PASS / FAIL / PARTIAL / N/A

verification-record: v1
verification-head: <full-head-sha>
suite-result: pass | fail | missing-contract | not-required
suite-source: executed | ci
suite-ci-run: <run-url> | none
suite-ci-attempt: <n> | none
suite-command: <exact-command-or-ordered-JSON-command-array> | none
suite-executions: 0 | 1
suite-exit-status: <integer> | n/a
suite-command-results:
  - command: <exact-command>
    result: pass | fail
    exit-status: <integer>
    evidence-pointer: "#/suite-evidence/command-<N>"
suite-baseline: <merge-base-sha> <ordered-result-list> | none

handoff-artifact:
  {"verification-record":"v1",...,"suite-evidence":{"command-<N>":{"command":"<exact-command>","output":"<complete-unedited-output>"}}}

### Evidence

#### <Scenario: changed behavior, regression, or failure mode>
**Flow:** <trigger> → <processing> → <outcome>
**Command:**
```
<exact command>
```
**Output:**
```
<complete output>
```
**Result:** PASS / FAIL — <what this demonstrates end to end>

### Issues Found
<PR-introduced bugs or regressions, and pre-existing failures labeled as such — or "None">
```

For `PARTIAL` because no authoritative contract can be established, use the same template with the canonical missing-contract values and `suite-command-results: []`; explain which target sources were checked under Evidence. For an ordered plan, render `suite-command` as an ordered JSON string array and repeat the result entry for every command actually reached. Complete, unedited outputs live only in the handed-off artifact at the locations resolved by each result's `#/suite-evidence/command-<N>` JSON Pointer.

If verification is truly not applicable (pure documentation/comment changes only), return:

```
## End-to-End Verification — PR #<number>

### Verdict: N/A

verification-record: v1
verification-head: <full-head-sha>
suite-result: not-required
suite-command: none
suite-executions: 0
suite-exit-status: n/a
suite-command-results: []

handoff-artifact:
  {"verification-record":"v1","verification-head":"<full-head-sha>","suite-result":"not-required","suite-command":null,"suite-executions":0,"suite-exit-status":null,"suite-command-results":[],"suite-evidence":{}}

Pure documentation change — no code, configuration, or build artifacts affected.
```
