# Special Verdicts: Missing Contract and Documentation-Only

Read this reference when no authoritative verification contract can be established or when all changed files are documentation or comments only.

## Missing Contract (`PARTIAL`)

When target repository sources establish no authoritative verification command or plan, stop without running a guessed substitute, return **Verdict: PARTIAL** (never mergeable), list checked sources under `Evidence`, and record:
- `suite-result: missing-contract`
- `suite-source: none`
- `suite-ci-run: none`
- `suite-ci-attempt: none`
- `suite-command: none`
- `suite-exit-status: n/a`
- `live-check: skipped`

## Documentation-Only (`N/A`)

When every changed file is documentation or comments only, return **Verdict: N/A** with:
- `suite-result: not-required`
- `suite-source: none`
- `suite-ci-run: none`
- `suite-ci-attempt: none`
- `suite-command: none`
- `suite-exit-status: n/a`
- `live-check: skipped`
