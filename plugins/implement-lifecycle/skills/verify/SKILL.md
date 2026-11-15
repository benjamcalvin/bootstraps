---
name: verify
description: "Delegated implement-lifecycle worker: exact-head verification and live runtime evidence."
license: MIT
metadata:
  version: "2.0.0"
  tags: ["verify", "e2e", "integration", "subagent"]
  author: benjamcalvin
---

# End-to-End Verification

<!-- lifecycle-suite-capability: full-suite-owner -->

**Suite capability: `full-suite-owner`. Sole phase authorized to produce authoritative exact-head suite signoff (at most one full execution per PR head).**

Verify the PR in the real, running system (use the delegation prompt if `$ARGUMENTS` is literal).

```text
$ARGUMENTS
```

Parse PR number, `tier=`, and optional `failed-scenarios=` from the prompt; inspect PR metadata, comments, and `--json files` via `gh pr view <number>`. For `Part of #N` slice PRs, verify **this slice's stated scope and changed behavior** — never return `PARTIAL` solely because deferred parent-issue items are unbuilt.

## Scope

Scale to `tier=` (`Medium` when absent):
- **Small** — suite evidence, plus one live check only when runtime behavior changed; otherwise Small may PASS on suite evidence alone (`live-check: skipped`, report `live check skipped (Small, no runtime change)`).
- **Medium** — suite evidence plus live scenarios covering changed behavior (`live-check: pass`).
- **Large** — suite evidence plus changed behavior, regression scenarios on shared paths, and failure modes.
- **Re-verification:** when `failed-scenarios=` is supplied, re-run only those scenarios plus suite evidence for the new head; without `failed-scenarios`, re-run suite evidence only.

## Suite evidence

Establish the target repository's authoritative verification contract: apply repository instructions first, then CI configuration, documented dev commands, and build/test config. Preserve multiple required commands in order as one plan; never subset or reorder them. If no authoritative contract can be established or only docs/comments changed, read `references/special-verdicts.md`.

Fetch `gh pr view <number> --json headRefOid --jq .headRefOid`. An authoritative verification comment already posted for that identical `verification-head` consumes its one-execution allowance. Use eligible CI evidence (`references/ci-evidence.md` — a failing, other-SHA, other-repo, or unconfirmable run is not evidence, so execute instead) or run the authoritative command/plan once on `verification-head`.

On any non-zero command exit, read `references/baseline-on-failure.md` before classifying `FAIL` vs `PARTIAL`. Re-check `headRefOid` after execution; if the head moved, return `FAIL` for the new head.

## Steps

### Step 1: Check Claims & Existing Evidence
Compare each change the PR description claims with `gh pr diff <number>` and list missing claims under `### Claim Mismatches`. Reuse manual comment evidence only when it gives exact commands, unedited output, and matches current head.

### Step 2: Plan & Execute Live Scenarios (when in scope)
Exercise real entry points end to end (trigger → changed code → observable outcome) per Scope. Never edit or fix source code yourself.

### Step 3: Report Findings
Post a single concise `gh pr comment <pr-number>` keeping every `verification-record: v2` header line **outside** any `<details>` block, since `merge-pr` parses them, and collapsing command/live output under `<details>` with a blank line after `</summary>`:

```markdown
## End-to-End Verification — PR #<number>

### Verdict: PASS / FAIL / PARTIAL / N/A

verification-record: v2
verification-head: <full-head-sha>
suite-result: pass | fail | missing-contract | not-required
suite-source: executed | ci | none
suite-ci-run: <run-url> | none
suite-ci-attempt: <n> | none
suite-command: <exact-command-or-ordered-JSON-command-array> | none
suite-exit-status: <integer> | n/a
live-check: pass | fail | skipped | partial

### Issues Found
<PR-introduced bugs, or pre-existing merge-base failures labeled with merge-base SHA — or "None">

### Claim Mismatches
<claimed changes absent from the diff, or "None">

<details>
<summary>Evidence</summary>

#### <Suite or Scenario>
**Flow:** <command or trigger → outcome>
**Output:** <unedited output summary>
**Result:** PASS / FAIL / SKIPPED — <what this demonstrates>
</details>
```
