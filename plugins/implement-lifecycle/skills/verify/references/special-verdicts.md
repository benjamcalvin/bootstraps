# Special Verdicts: Missing Contract and Documentation-Only

Read this reference when no authoritative contract can be established or when all changed files are documentation or comments only.

## Missing Contract (PARTIAL)

When target sources do not establish an authoritative command or plan, report the missing contract explicitly and return PARTIAL without executing a guessed substitute. The missing-contract/PARTIAL record is canonical:

`suite-result: missing-contract`, `suite-command: none`, `suite-executions: 0`, `suite-exit-status: n/a`, and an empty `suite-command-results` list. This state is not mergeable. List the checked target sources under Evidence.

```json
{"verification-record":"v1","verification-head":"<full-head-sha>","suite-result":"missing-contract","suite-command":null,"suite-executions":0,"suite-exit-status":null,"suite-command-results":[],"suite-evidence":{}}
```

## Documentation-Only (N/A)

For a pure documentation or comment change, return verdict N/A with `suite-result: not-required`, `suite-command: none`, `suite-executions: 0`, `suite-exit-status: n/a`, and an empty `suite-command-results` list:

```json
{"verification-record":"v1","verification-head":"<full-head-sha>","suite-result":"not-required","suite-command":null,"suite-executions":0,"suite-exit-status":null,"suite-command-results":[],"suite-evidence":{}}
```
