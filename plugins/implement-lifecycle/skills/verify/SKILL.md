---
name: verify
description: "Delegated implement-lifecycle worker: exact-head verification and live runtime evidence."
---

# End-to-End Verification

<!-- lifecycle-suite-capability: full-suite-owner -->

**Suite capability: `full-suite-owner`. Sole phase authorized to produce authoritative exact-head suite signoff (at most one full execution per PR head).**

Verify the PR in the real, running system (use the delegation prompt if `$ARGUMENTS` is literal).

```text
$ARGUMENTS
```

Parse PR number, `risk=<Low|Moderate|High>` (`Moderate` when absent), and optional `failed-scenarios=` from the prompt; inspect PR metadata, comments, and `--json files` via `gh pr view <number>`. **Stay focused on the task at hand; do not overthink.** For `Part of #N` slice PRs, verify **this slice's stated scope and changed behavior** — never return `PARTIAL` solely because deferred parent-issue items are unbuilt.

## Scope

Scale checks to risk and complexity without inventing contrived scenarios:
- **Low** — suite evidence, plus one quick smoke check only if runtime behavior changed (otherwise PASS on suite evidence alone and report `live check skipped (Low, no runtime change)`).
- **Moderate** — suite evidence plus live checks exercising the changed behavior.
- **High** — suite evidence plus changed behavior, key edge/failure modes, and shared-path regressions.
- **Re-verification:** when `failed-scenarios=` is supplied, re-run only those scenarios plus suite evidence for the new head; without `failed-scenarios`, re-run suite evidence only.

## Suite evidence

- **Docs/comments only:** return **Verdict: N/A** without running tests.
- **Contract discovery:** apply repository instructions (`AGENTS.md`, `CLAUDE.md`), CI workflow commands, documented dev commands, and build/test config. If none establishes an authoritative command/plan, stop without running a guessed substitute and return **PARTIAL**.
- **Single exact-head signoff:** fetch `gh pr view <number> --json headRefOid --jq .headRefOid`. Reuse a passing required-CI run when the target repository's CI already ran the full plan cleanly on `headRefOid`; otherwise run the command/plan once on `headRefOid` and re-check `headRefOid` afterward (if moved, return **FAIL**).
- **Merge-base baselining on failure:** if any command fails locally, run each failing command once on `git merge-base origin/<base> <head>` in a separate checkout. If every failure already matches at both SHAs, return **PARTIAL** citing the merge-base SHA (pre-existing; never mergeable); if any failure is new, return **FAIL**.

## Steps

### Step 1: Check Claims & Live Behavior
Compare each change the PR description claims with `gh pr diff <number>` and list missing claims under `### Claim Mismatches`. Exercise real runtime entry points when in scope; never edit source code or docs.

### Step 2: Post Concise Verification Comment
Post one `gh pr comment <pr-number>` keeping `### Verdict:` and `Verified-Head:` **outside** `<details>` (and collapsing command/scenario output under `<details>` with a blank line after `</summary>`):

```markdown
## End-to-End Verification — PR #<number>

### Verdict: PASS / FAIL / PARTIAL / N/A
Verified-Head: <full-head-sha>

### Issues Found
<PR-introduced bugs, or pre-existing merge-base failures citing merge-base SHA — or "None">

### Claim Mismatches
<claimed changes absent from the diff, or "None">

<details>
<summary>Evidence</summary>

<commands/scenarios run and concise output>
</details>
```
