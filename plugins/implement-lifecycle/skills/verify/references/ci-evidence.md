# CI evidence for the authoritative suite

Read this before setting `suite-source: ci` in `verification-record: v2` instead of executing the authoritative command or plan.

A target-repository required-CI run replaces execution only when every condition holds; a failing, other-SHA, other-repository, or unconfirmable run is not evidence, so execute instead. Parse the repository and run id from the run URL and fetch that attempt with `gh run view -R <owner>/<repo> <run-id> --attempt <n> --json headSha,conclusion,jobs,url`.

Require:
- The repository is the target repository and `headSha` equals `verification-head`.
- That attempt's `conclusion` is `success`, with integer attempt `≥ 1`.
- In every job or matrix leg running any plan command, every established command maps, in order, to a step whose conclusion is `success` (never `skipped`), with no conditional or `continue-on-error` plan steps in the executed workflow definition (check the merge ref for `pull_request` runs).

Wait for an in-progress run at most the suite's own typical runtime, and never more than 30 minutes, then execute locally. Set `suite-source: ci`, `suite-ci-run: <run-url>`, `suite-ci-attempt: <n>`, `suite-exit-status: 0`, and quote key job/step output in the collapsed `Evidence` section of the verification comment.
