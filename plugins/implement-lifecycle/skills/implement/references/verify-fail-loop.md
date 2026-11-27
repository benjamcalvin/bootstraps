# Phase 5 Failure Loop

Read this reference when `verify` returns **FAIL** and/or parallel `review-docs` returns accepted `Action Required` findings.

Allow at most 2 FAIL → address → re-verify cycles; on a third FAIL, do not address again: post an escalation comment listing the unresolved failures, open an owner request per `owner-request.md` carrying them, then print the run ledger and stop.

## Addressing Phase 5 Failures

Batch `verify` failures and any accepted `Action Required` doc findings into one inline Action Required table (`| # | Finding | Severity | Details |`, with expected vs. actual and how to fix).

Delegate the fixes through the active harness adapter without editing code yourself: continue the existing author child (or spawn a fresh `implement-address` child if no author child exists in the run):

```text
Payload: <pr-number> verify-<round-number>
<inline Action Required Phase 5 findings table>
```

Phase 5 fix rounds count from 1, independent of Phase 4.

## Scoped Re-verification & Doc Re-check

Continue the failed check(s) on the new head. Target failed scenarios and directly affected behavior. If only docs failed but an earlier live verdict now names an old head, continue the verifier for the relevant real-world smoke on the candidate head before merge. Use the existing child unless unavailable:

```text
Payload: <pr-number> risk=<Low|Moderate|High> [failed-scenarios=<names>]
```
