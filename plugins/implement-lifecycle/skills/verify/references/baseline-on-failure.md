# Failure Baselining on Merge-Base

Read this reference when any authoritative verification command exits non-zero on the PR head, before classifying the verdict as `FAIL` or `PARTIAL`.

## Workflow

When the head's suite fails, run each failing command once on the PR's merge-base (`git merge-base origin/<base> <head>`) in a separate checkout (without changing or resetting the PR head execution count).

Match failures by identity (test names or rule IDs): a failure present at both SHAs is pre-existing; any new failure, setup mismatch, missing-command error, or error-class mismatch is PR-introduced and produces **FAIL**.

When every failure is pre-existing, return **PARTIAL** with `suite-result: fail`, `suite-source: executed`, `suite-exit-status: <non-zero>`, `live-check: skipped`, list the pre-existing failures under `### Issues Found` citing the merge-base SHA, and name any plan commands never run on the head because the plan stopped. A `PARTIAL` / `suite-result: fail` record is never mergeable.
