# Phase 5 Failure Loop

Read this reference when `verify` returns **FAIL** and/or parallel `review-docs` returns accepted `Action Required` findings.

Allow at most 2 FAIL → address → re-verify cycles; on a third FAIL, do not address again: post an escalation comment listing the unresolved failures, then print the run ledger, stop, and inform the user.

## Addressing Phase 5 Failures

Batch `verify` failures and any accepted `Action Required` doc findings into one inline Action Required table (`| # | Finding | Severity | Details |`, with expected vs. actual and how to fix).

Delegate the fixes through the active harness adapter without editing code yourself: continue the existing author child (or spawn a fresh `implement-address` child if no author child exists in the run):

```text
Payload: <pr-number> verify-<round-number>
<inline Action Required Phase 5 findings table>
```

Phase 5 fix rounds count from 1, independent of Phase 4.

## Scoped Re-verification & Doc Re-check

After fixes are committed, continue only the failed Phase 5 check(s) (`verify` and/or `review-docs`, spawning fresh only if none exists / one-shot harness). For `verify`, pass `failed-scenarios=<names>` so re-verification targets what failed:

```text
Payload: <pr-number> risk=<Low|Moderate|High> [failed-scenarios=<names>]
```
