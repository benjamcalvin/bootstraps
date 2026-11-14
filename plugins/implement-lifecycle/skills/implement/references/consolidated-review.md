# Consolidated review comment

Post this once per round. Reviewer findings and each referee decision stay visible; the referee reasoning collapses under `<details>`, with a blank line after `</summary>` so GitHub renders the Markdown inside.

```markdown
## Review Round <N> — Consolidated Review & Referee Decisions

**Reviewers run:** general<, triggered risk lenses, if any>
**Tier:** <Small|Medium|Large> (<net changed lines> net lines)
**Specialist rationale:** <trigger per selected lens (`review-security` / `review-correctness` / `review-docs`), or "none — triggers did not apply">

### Reviewer Findings
#### General
<returned findings verbatim under their headings>
#### <Specialty — one per reviewer invoked; "no findings" when clean>

### Referee Decisions
| # | Finding | Reviewer | Reviewer Severity | Decision |
|---|---------|----------|-------------------|----------|

**Findings forwarded to addresser:** <count>

<details>
<summary>Referee reasoning</summary>

| # | Concern (Valid/Unproven) | Reasoning / smallest remedy |
|---|--------------------------|-----------------------------|

</details>
```
