---
name: verify
description: Delegated implement-lifecycle worker: exact-head verification and live runtime evidence.
license: MIT
metadata:
  version: "1.2.0"
  tags: ["verify", "e2e", "integration", "subagent"]
  author: benjamcalvin
---

# End-to-End Verification

<!-- lifecycle-suite-capability: full-suite-owner -->

**Suite capability: `full-suite-owner`. Sole phase authorized to produce authoritative exact-head suite signoff (at most one full execution per PR head).**

Verify the PR supplied with the invocation in the real, running system. If the client leaves `$ARGUMENTS` literal, use the delegation prompt.

```text
$ARGUMENTS
```

Parse the PR number, tier, record path (`record=`), failed scenarios, and `bundle=` path from the payload; read the supplied context-bundle file when provided, fetching PR metadata, comments, and `--json files` only when absent.

## Scope

**Scale to the payload's tier** (Medium when absent): **Small** — suite evidence, plus one live check only when runtime behavior changed; otherwise Small may PASS on suite evidence alone and the report states `live check skipped (Small, no runtime change)`. **Medium** — live scenarios for changed behavior; **Large** — the full Step 3 plan, including regressions and failure modes. **Re-verification**: when the payload names failed scenarios, re-run only those scenarios plus suite evidence for the new head; without `failed-scenarios`, re-run suite evidence only.

## Suite evidence

Establish the target repository's authoritative verification contract. Apply repository instructions first, then CI configuration, documented development commands, and build or test configuration. Use an explicit command when the repository declares one. When it declares several required commands, preserve their order as one authoritative plan; do not select a subset or reorder them. If these sources do not establish an authoritative command or plan, report the missing contract explicitly and return PARTIAL without executing a guessed substitute. When no authoritative contract can be established or when all changed files are documentation/comments only, read `references/special-verdicts.md`.

For code changes, fetch `gh pr view <number> --json headRefOid --jq .headRefOid`. Any complete authoritative evidence record for that identical SHA consumes its one-execution allowance, whether the recorded result passed or failed. Consume a matching passing record without re-executing. For a complete failing record, return FAIL and require addressing that produces a new head before another authoritative execution. Otherwise use eligible CI evidence or execute the established command or ordered plan exactly once.

**CI evidence.** Before relying on one, read `references/ci-evidence.md` and satisfy every condition there; a failing, other-SHA, other-repository, or unconfirmable run is not evidence, so execute instead.

**Baseline on failure.** When any authoritative command exits non-zero, read `references/baseline-on-failure.md` before classifying FAIL vs PARTIAL.

**Direct file handoff.** Write the JSON verification artifact directly to `record=<path>` (or a scratch file) with file tools or python/jq scripts. Map comment `none`/`n/a` to JSON `null`, adding `suite-evidence` mapping each `command-<N>` pointer to `{"command": "<exact-command>", "output": "<complete-unedited-output>"}`. Do not dump escaped JSON into the LLM message.

After execution, re-check `headRefOid`. If it differs from `verification-head`, report FAIL and claim no evidence for the new head.

## Steps

### Step 1: Understand the Change & Check Claims

Compare each change the PR description claims with `gh pr diff <number>`, and list every claimed change absent from the diff under Claim Mismatches.

### Step 2: Check Existing Evidence

Reuse manual evidence from comments only when it has the exact command, unedited output, and exercises behavior at current head.

### Step 3: Plan Scenarios

Each scenario runs the real entry point end to end (trigger → changed code → observable outcome):
- **Changed behavior** (Medium/Large; one check for Small when runtime behavior changed)
- **Regression** (Large) — flows sharing code paths with the change
- **Failure mode** (Large) — invalid input or denied permissions degrade gracefully

### Step 4: Execute Verification

Run the authoritative command or plan once on `verification-head`, capturing its exit code and output. Run planned live scenarios. Do NOT fix failing code yourself.

### Step 5: Report Findings

Post a concise PR comment (`gh pr comment <pr-number>`): verdict, `verification-record:v1`, Issues Found, Claim Mismatches, and collapsed Evidence. Keep every record line outside any `<details>` block, since merge-pr parses them; collapse any evidence you include. Return:

```markdown
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
verification-record-file: <resolved-path>

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
