# Run ledger

Print the ledger in this shape. Keep the `<details>` wrapper, and the blank line after `</summary>`, wherever it is posted to the PR.

```markdown
<details>
<summary>Run ledger · <outcome> · <tier></summary>

## Run Ledger
- Tier: <Small|Medium|Large> — <reason>
- Children: <role>: <count> (<balanced|frontier>), ...
- Rounds: review <n>, verification <n>
- Fix commits: <count of addresser commits>
- Wall-clock: plan/implement <m>, review <m>, verify <m>, merge <m>
- Follow-up items: <out-of-delta findings, or none>
- Outcome: <merged|escalated|partial|stopped|reviewed|addressed> — <phase>

</details>
```
