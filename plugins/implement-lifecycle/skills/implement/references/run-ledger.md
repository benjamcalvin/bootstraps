# Run ledger

Persist phase timestamps (`phase_times`), spawns/continuations (`agents`), size tier, risk lenses, rounds, and `fix_commits` in `state.json` as you go. Always re-read `state.json` before printing so ledger metrics survive context compactions; if Phase 5 ran via the inline fast gate, record `verify: inline (fast-gate)` under `- Children:`.

On every terminal path (merge, escalation, cap or stall exit, third verify FAIL, PARTIAL, or any other stop), print the ledger to the user, collapsed under `<details>`. When a PR exists and the path posts a PR comment or merge summary, append it there too. Keep the blank line after `</summary>` so Markdown renders properly.

<details>
<summary>Run ledger · <outcome> · <tier></summary>

## Run Ledger
- Tier: <Small|Medium|Large> (<net lines>) + lenses [<none|security|correctness|docs>] — <reason>
- Children: <role>: <spawned> [+ <n> continuations] (<balanced|frontier|inline>), ...
- Rounds: review <n>, verification <n>
- Fix commits: <count of addresser commits>
- Wall-clock: plan/implement <m>, review <m>, verify <m>, merge <m>
- Follow-up items: <out-of-delta findings, or none>
- Outcome: <merged|escalated|partial|stopped|reviewed|addressed> — <phase>

</details>
