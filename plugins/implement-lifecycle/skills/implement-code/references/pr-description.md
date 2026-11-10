# PR description shape

Only the lead, the "Author ran" line, and the review focus stay visible; everything else collapses under `<details>`.

- **Lead:** behavior only, in plain language with **no file paths, function names, or line numbers**. It ends with `*(agent-drafted lead)*` until a human edits it.
- **Author ran:** only commands you executed, with their results. CI and verification results arrive later as checks and comments, so never claim them.
- **`<details>`:** keep a blank line after `</summary>`; GitHub renders Markdown inside only after one. Design is in component terms; code identifiers appear from Implementation Notes down.
- No living sections ("Progress log", "Live status").
- One idea per sentence; cite an issue or spec at the end of a bullet, never mid-clause; keep review chronology ("round 1 added X") out.
- Skim test: the lead, then the first sentence of each collapsed section, summarizes the PR at descending altitude.
