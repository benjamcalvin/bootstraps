# CI Source Verification for Merge

Read this reference when validating exact-head verification evidence where `suite-source` is `ci`.

## Validation Rules

Require `suite-executions: 0` and `suite-exit-status: 0`. Reject a record whose `suite-ci-attempt` is none or not an integer ≥ 1; otherwise parse the repository and run id from `suite-ci-run` and fetch that attempt with `gh run view -R <owner>/<repo> <run-id> --attempt <suite-ci-attempt> --json headSha,conclusion,jobs,url`.

Require the repository to be the target repository, its `headSha` to equal `verification-head`, that attempt's `conclusion` to be `success`, and, in every job or matrix leg with a step running a plan command, each established command to map in order to a `success` step, none `skipped`; reject a conditional or `continue-on-error` plan step in the workflow definition the run executed (for `pull_request`, the merge ref).

Reject a run for any other SHA, repository, or attempt.
