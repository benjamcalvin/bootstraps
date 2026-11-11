# Verification Failure Loop

Read this reference when `verify` returns **FAIL**.

Allow at most 2 FAIL → address → re-verify cycles; on a third FAIL, do not address again: post an escalation comment listing the unresolved failures, then print the run ledger, stop, and inform the user.

## Addressing Verification Failures

`verify` only posts a PR comment, so write its failures to a findings file yourself (`# Verification Findings — Round <N>`, Step C's table, severity Action Required, with expected vs. actual and how to fix). No referee step: `verify` is self-vetting.

Delegate the fixes through the active harness adapter without editing code yourself: continue the existing author child (or spawn a fresh `implement-address` child if no author child exists in the run):

```text
Payload: <pr-number> verify-<round-number> <resolved-verify-findings-path> bundle=<resolved-context-bundle-path>
```

Verify rounds count from 1, independent of Phase 4.

## Scoped Re-verification

After fixes are committed, continue the existing `verify` child (or spawn a fresh `verify` child on one-shot harnesses) with the failed scenarios, or without `failed-scenarios` when only the suite failed:

```text
Payload: <pr-number> tier=<Small|Medium|Large> record=<resolved-verification-record-path> [failed-scenarios=<names>] bundle=<resolved-context-bundle-path>
```
