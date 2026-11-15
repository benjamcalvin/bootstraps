# Run ledger

Track phase timestamps, spawns/continuations, risk/complexity level, rounds, and fix commits across the run (recovering counts from `git log` and PR comments if compacted); if Phase 5 skipped `verify` because no live surface changed, record `verify: skipped (no live surface)` under `- Children:`.

On every terminal path (merge, escalation, cap or stall exit, third verify FAIL, PARTIAL, or any other stop), print the ledger to the user, collapsed under `<details>`. When a PR exists and the path posts a PR comment or merge summary, append it there too. Keep the blank line after `</summary>` so Markdown renders properly.

<details>
<summary>Run ledger · <outcome> · <risk></summary>

## Run Ledger
- Risk & complexity: <Low|Moderate|High> — <reason>
- Children: <role>: <spawned> [+ <n> continuations] (<balanced|frontier|inline>), ...
- Rounds: review <n>, Phase 5 <n>
- Fix commits: <count of addresser commits>
- Wall-clock: plan/implement <m>, review <m>, verify/docs <m>, merge <m>
- Follow-up items: <out-of-delta findings, or none>
- Outcome: <merged|escalated|partial|stopped|reviewed|addressed> — <phase>

</details>
