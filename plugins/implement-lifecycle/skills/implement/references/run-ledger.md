# Run ledger

Track phase durations and tally execution metrics as you go: spawned children and continuations per role and tier, addresser commits (from each Commits list, including verify fixes), and out-of-delta follow-ups.

On every terminal path (merge, escalation, cap or stall exit, third verify FAIL, PARTIAL, or any other stop), print the ledger to the user, collapsed under `<details>`. When a PR exists and the path posts a PR comment or merge summary, append it there too. Keep the blank line after `</summary>` so Markdown renders properly.

<details>
<summary>Run ledger · <outcome> · <tier></summary>

## Run Ledger
- Tier: <Small|Medium|Large> — <reason>
- Children: <role>: <spawned> [+ <n> continuations] (<balanced|frontier>), ...
- Rounds: review <n>, verification <n>
- Fix commits: <count of addresser commits>
- Wall-clock: plan/implement <m>, review <m>, verify <m>, merge <m>
- Follow-up items: <out-of-delta findings, or none>
- Outcome: <merged|escalated|partial|stopped|reviewed|addressed> — <phase>

</details>
