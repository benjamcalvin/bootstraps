# Run ledger

Track phase timestamps, spawns/continuations, risk/complexity level, rounds, and fix commits across the run (recovering counts from `git log` and PR comments if compacted); if Phase 5 skipped `verify` because no live surface changed, record `verify: skipped (no live surface)` under `- Children:`.

Use UTC event timestamps from the harness or PR, or read the clock at each transition. Ready means the candidate passed all agent-runnable gates and can merge or await human approval or the merge queue. Distinguish a handoff with unperformed human-only tests from a ready candidate. For an existing PR, measure from this invocation’s review entry. Show only reached milestones. Label unavailable times unknown and skipped phases skipped. Calculate elapsed time by subtracting timestamps. Count overlapping children once. Report observed human, CI, or environment waits within that elapsed time. An unexplained gap stays unattributed.

On every terminal path (merge, escalation, cap or stall exit, third verify FAIL, PARTIAL, or any other stop), print the ledger to the user, collapsed under `<details>`. When a PR exists and the path posts a PR comment or merge summary, append it there too. Keep the blank line after `</summary>` so Markdown renders properly.

<details>
<summary>Run ledger · <outcome> · <risk></summary>

## Run Ledger
- Harness and installed plugin version: <harness> <version or unknown>
- Risk & complexity: <Low|Moderate|High> — <reason>
- Children: <role>: <spawned> [+ <n> continuations] (<balanced|frontier|inline>), ...
- Rounds: review <n>, Phase 5 <n>
- Fix commits: <count of addresser commits>
- Milestones (UTC): invoked <time>, PR open or review entry <time>, review complete <time>, verify/docs complete <time>, ready <time>, merged or stopped <time>
- Wall-clock: invocation to outcome <elapsed>, PR open or review entry to ready <elapsed or not reached>
- External waits: <reason and observed interval, or none observed>
- Follow-up items: <out-of-delta findings, or none>
- Outcome: <merged|escalated|partial|stopped|reviewed|addressed> — <phase>

</details>
