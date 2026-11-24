---
name: verify
description: "Delegated implement-lifecycle worker: real-world verification by inspecting and exercising the actual work."
metadata:
  opencode/autoinvoke: false
---

# Real-World Verification

Verify the PR in practice by inspecting and exercising the actual built work (use the delegation prompt if `$ARGUMENTS` is literal).

```text
$ARGUMENTS
```

**Automated test suites are not your job.** Unit/integration suites, linters, and builds were already run by the implementer or CI; do not spend Phase 5 re-running test suites, and never report `PASS` merely because unit tests passed. Your job is **real-world, hands-on verification** using the environment and tools available.

Parse PR number, `risk=<Low|Moderate|High>` (`Moderate` when absent), and optional `failed-scenarios=` from the prompt; inspect PR metadata, comments, and `--json files` via `gh pr view <number>`. **Stay focused on the task at hand; do not overthink.** For `Part of #N` slice PRs, verify **this slice's stated scope and changed behavior** — never return `PARTIAL` solely because deferred parent-issue items are unbuilt.

## What to Verify

For an integration, exercise the named user interaction through the actual consumer or provider. Reuse inspectable evidence from the same head, environment and scenario when project rules permit. If only a stand-in was exercised and the real boundary remains unavailable, report PARTIAL with the missing interaction.

Exercise and inspect the real built artifact matching what changed:
- **Data, queries, migrations, or pipelines** — run against representative inputs and **inspect the actual output rows, schemas, counts, edge values, and persisted state** to confirm the data genuinely looks right (not merely exit code 0).
- **CLI, TUI, scripts, or tools** — invoke the real command/binary across realistic flags, inputs, and error cases; inspect actual stdout/stderr, exit codes, and generated files or side effects.
- **Frontend or web UI** — launch or open the running app, navigate the affected views in a browser, exercise interactions and states, inspect layout/console/network errors, and capture **screenshots** or visual evidence.
- **APIs, services, configs, or background jobs** — hit live endpoints/workers or load configs through the real consumer and inspect responses, state transitions, and logs.
- **No runnable or observable real-world surface** (docs/comments only, type-only edits, or pure internal refactors with no live surface beyond automated tests) — return **Verdict: N/A** immediately without inventing busywork.

## Depth & Guardrails

Scale hands-on depth to risk and complexity without inventing contrived scenarios:
- **`Low`** — quick smoke check of the changed real-world surface and output inspection.
- **`Moderate`** — exercise the primary changed flows and inspect real outputs, UI, or data.
- **`High`** — exercise changed flows, realistic edge/failure cases, and boundary/state interactions, inspecting resulting data, UI, or state thoroughly.
- **Re-verification (`failed-scenarios=<names>`):** re-verify the named scenarios (plus sanity-check directly affected output) on the current `headRefOid`.
- **Exact-head & baseline check:** record `gh pr view <number> --json headRefOid --jq .headRefOid` before starting and re-check afterward (if moved, return **FAIL**). If startup or a live scenario fails for reasons that appear unrelated to the PR, test `git merge-base origin/<base> <head>` in a separate checkout: if the exact failure already reproduces there, return **PARTIAL** citing the merge-base SHA (pre-existing; never mergeable); if introduced by the PR, return **FAIL**. If verification requires unavailable credentials, hardware, or external systems, return **PARTIAL** naming what could not be verified rather than faking live evidence.

## Steps

### Step 1: Check Claims & Real-World Behavior
Compare each change the PR description claims with `gh pr diff <number>` and list missing claims under `### Claim Mismatches`. Exercise and inspect real-world behavior cleanly; never edit source code or docs.

### Step 2: Post Concise Verification Comment
Post one `gh pr comment <pr-number>` keeping `### Verdict:` and `Verified-Head:` **outside** `<details>` (and collapsing real-world evidence under `<details>` with a blank line after `</summary>`):

```markdown
## Real-World Verification — PR #<number>

### Verdict: PASS / FAIL / PARTIAL / N/A
Verified-Head: <full-head-sha>

### Issues Found
<PR-introduced bugs/data/UI issues, unavailable checks, or pre-existing merge-base failures citing merge-base SHA — or "None">

### Claim Mismatches
<claimed changes absent from the diff, or "None">

<details>
<summary>Evidence</summary>

<real-world checks, inspected data/outputs, CLI results, or screenshot notes>
</details>
```
