# Failure Baselining on Merge-Base

Read this reference when any authoritative verification command exits non-zero, before classifying the verdict as `FAIL` or `PARTIAL`.

## Workflow

When the head's suite fails, run each failing command once on the PR's merge-base (`git merge-base origin/<base> <head>`) in a separate checkout and record the results in `suite-baseline` with that SHA. This does not consume or reset the head's allowance; reuse a baseline already in the record.

Match failures by identity (test names or rule ids): a failure present at both SHAs is pre-existing; any other failure, or one you cannot match, is PR-introduced and produces FAIL. A setup, missing-command, or error-class mismatch between the SHAs is PR-introduced.

When every failure is pre-existing, return PARTIAL, list them under Issues Found, and name every plan command never run on the head because the plan stopped; the record keeps `suite-result: fail` and is not mergeable. Baseline results are never PR-head evidence.

Baseline entries use pointers `#/suite-evidence/baseline-command-<N>` in `suite-evidence`.
