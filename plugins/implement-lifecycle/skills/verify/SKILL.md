---
name: verify
description: >-
  End-to-end verification of a PR's changes in the real running system (runs as subagent).
  Exercises the changed behavior live, scaled to the PR's tier, and owns the exact-head
  authoritative-suite evidence.
license: MIT
metadata:
  version: "1.1.0"
  tags: ["verify", "e2e", "integration", "subagent"]
  author: benjamcalvin
---

# End-to-End Verification

<!-- lifecycle-suite-capability: full-suite-owner -->

**Suite capability: `full-suite-owner`. Verification is the sole phase authorized to execute or consume the target repository's authoritative verification command or ordered command plan, at most once for the exact PR head.**

Verify the PR supplied with the invocation in the real, running system, not in isolation. If the client leaves `$ARGUMENTS` literal, use the delegation prompt.

```text
$ARGUMENTS
```

Parse the PR number, tier, and any failed-scenario list from the payload; fetch the PR metadata, comments, and changed-file summary. Confirm the changed behavior works as a user, operator, or consumer experiences it, and that the authoritative suite holds for the exact head. Use the client's task tracker when available.

## Scope

**Scale to the payload's tier** (Medium when absent): **Small** — suite evidence, plus one live check only when runtime behavior changed (a code or configuration path that executes at runtime, not docs or tests alone); otherwise Small may PASS on suite evidence alone and the report states `live check skipped (Small, no runtime change)`; **Medium** — live scenarios for the changed behavior; **Large** — the full Step 3 plan, including regressions and failure modes. **Re-verification**: when the payload names failed scenarios, re-run only those scenarios plus suite evidence for the new head; without `failed-scenarios`, re-run suite evidence only.

## Suite evidence

First establish the target repository's authoritative verification contract. Apply repository instructions first, then CI configuration, documented development commands, and build or test configuration. Use an explicit command when the repository declares one. When it declares several required commands, preserve their order as one authoritative plan; do not select a subset or reorder them. Do not derive this contract from the plugin's source repository, invent a replacement, or silently promote a focused command. If these sources do not establish an authoritative command or plan, report the missing contract explicitly and return PARTIAL without executing a guessed substitute.

For a code-changing PR, obtain the exact head with `gh pr view <number> --json headRefOid --jq .headRefOid`. Any complete authoritative evidence record for that identical SHA consumes its one-execution allowance, whether the recorded result passed or failed. A complete record has the exact command or ordered plan, an execution count of one (zero for `suite-source: ci`), the original overall exit status, and matching `pass`/zero or `fail`/nonzero results. Establish the contract independently before consuming evidence. Consume a complete passing record only when its command or plan exactly matches, and do not execute it again. For a complete failing record, return FAIL and require addressing that produces a new head before another authoritative execution. Apply the baseline rule first: a record whose failures are all pre-existing returns PARTIAL. Evidence for any other SHA is stale. Otherwise use eligible CI evidence or execute the established command or ordered plan exactly once. Stop the plan at the first failure unless the target repository requires otherwise. Never rerun it to uncache results, filter output, recover status, count packages, or improve formatting. A pure documentation change may record verification as not required.

**CI evidence.** A target-repository required-CI run may replace execution. Before relying on one, read `references/ci-evidence.md` and satisfy every condition there; a failing, other-SHA, other-repository, or unconfirmable run is not evidence, so execute instead.

**Baseline on failure.** When the head's suite fails, run each failing command once on the PR's merge-base (`git merge-base origin/<base> <head>`) in a separate checkout and record the results in `suite-baseline` with that SHA. This does not consume or reset the head's allowance; reuse a baseline already in the record. Match failures by identity (test names or rule ids): a failure present at both SHAs is pre-existing; any other failure, or one you cannot match, is PR-introduced and produces FAIL. A setup, missing-command, or error-class mismatch between the SHAs is PR-introduced. When every failure is pre-existing, return PARTIAL, list them under Issues Found, and name every plan command never run on the head because the plan stopped; the record keeps `suite-result: fail` and is not mergeable. Baseline results are never PR-head evidence.

**Record.** Write suite evidence as a canonical `verification-record:v1` in both the returned result and the PR comment, using the exact fields of the Step 5 template. An absent `suite-source` means `executed`; absent `suite-ci-run`, `suite-ci-attempt`, or `suite-baseline` means `none`. `suite-command-results` lists each command actually executed, in order, with its exact command, `pass`/`fail`, original exit status, and pointer `#/suite-evidence/command-<N>`; use a one-entry list for a single command. A passing plan has an entry for every declared command; a failing plan records commands through the failure, and unexecuted trailing commands stay in `suite-command` but are never shown as executed. Baseline entries use pointers `#/suite-evidence/baseline-command-<N>`.

**Handoff artifact.** Also return one JSON object that preserves the record (comment `none`/`n/a` → JSON `null`; `suite-baseline` → `{"head":"<merge-base-sha>","command-results":[...]}`; results as an ordered array of objects) and adds `suite-evidence`: each pointer must resolve there to an entry whose `command` exactly matches and whose `output` is that command's complete, unedited output. The PR comment omits `suite-evidence`. The fresh merger receives only this object; never point at headings, the parent transcript, or anything outside it.

The missing-contract/PARTIAL record is canonical: `suite-result: missing-contract`, `suite-command: none`, `suite-executions: 0`, `suite-exit-status: n/a`, and an empty `suite-command-results` list. This state is not mergeable. A documentation-only N/A record uses the same command, execution, status, and empty-results values with `suite-result: not-required`.

After execution, fetch `headRefOid` again. If it differs from `verification-head`, report FAIL and claim no evidence for the new head; a later attempt may run once for that commit.

## Steps

### Step 1: Understand the Change

From the PR, linked issues, and context bundle, identify what users or consumers now experience differently, what triggers the changed code, its downstream effects, and what is observable (responses, persisted state, files, logs, artifacts).

**Claims against the diff.** Compare each change the PR description claims with `gh pr diff <number>`, and list every claimed change absent from the diff under Claim Mismatches. A mismatch alone does not change the verdict; the orchestrator corrects the description.

### Step 2: Check for Existing Evidence

Reuse manual evidence from the PR description or comments for a scenario only when it has the exact command and complete unedited output and exercises that behavior end to end at the current head. Authoritative-suite evidence additionally needs the complete canonical record and an exact `verification-head` match.

### Step 3: Plan Scenarios

Each scenario runs the real entry point end to end (trigger → changed code → observable outcome) and checks the final state:

- **Changed behavior** (Medium and Large; one check for Small when runtime behavior changed): the primary use case through the real flow, including downstream effects.
- **Regression** (Large): one or two existing flows sharing code paths with the change.
- **Failure mode** (Large): invalid input, a missing dependency, or denied permission degrades gracefully.

Without a user-facing surface, exercise the nearest observable artifact (a real caller of a library, the service with changed configuration, the built artifact, or a before/after comparison for migrations, refactors, and performance changes) using existing dev/test infrastructure.

### Step 4: Execute Verification

Capture the authoritative command's output and status from the same single execution; for an ordered plan, do this per command, in order:

```bash
set +e
<authoritative-command>
suite_status=$?
set -e
```

Do not pipe it through a formatter unless `pipefail` is set and the original status is preserved from that same execution. For each scenario, use synthetic data, run the real entry point, and capture the full command, output, and exit code unedited. If a step fails, report expected versus actual and whether it is a real bug or an environment issue. Do NOT fix it yourself.

### Step 5: Report Findings

Post a concise PR comment (`gh pr comment <pr-number>`): the verdict, the complete `verification-record:v1` with every command, result, status, and pointer, Issues Found, and Claim Mismatches, not the verbose transcript. Keep every record line outside any `<details>` block, since merge-pr parses them; collapse any evidence you include. Return:

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

### Issues Found
<PR-introduced bugs or regressions, and pre-existing failures labeled as such — or "None">

### Claim Mismatches
<claimed changes absent from the diff, or "None">

<details>
<summary>Evidence</summary>

#### <Scenario>
**Flow:** <trigger> → <processing> → <outcome>
**Command:** <exact command>
**Output:** <complete output>
**Result:** PASS / FAIL — <what this demonstrates end to end>
</details>
```

For missing-contract PARTIAL, use the canonical values and list the target sources checked under Evidence. For an ordered plan, `suite-command` is a JSON string array with one result entry per command reached. For a pure documentation/comment change, return verdict N/A with `suite-result: not-required`, the canonical empty values, and this handoff artifact:

```
{"verification-record":"v1","verification-head":"<full-head-sha>","suite-result":"not-required","suite-command":null,"suite-executions":0,"suite-exit-status":null,"suite-command-results":[],"suite-evidence":{}}
```
