# Owner requests

When work needs a decision or an action only the owner can take, open one owner-request issue for the blocked target. The owner answers there, and a later run resumes from it.

**Before opening.** Do every step you can run yourself. The request holds only what needs the owner: decisions, credentials, physical access, approvals, and paid or irreversible actions. Collect every open decision and action for the target into one request; never drip-feed them.

**Open it.** Title `Owner request: <what is needed> (#<blocked>)`, label `needs-owner` (create it if missing: `gh label create needs-owner --description "Waiting on the owner" || true`). Then comment `Blocked on #<request>` on the blocked PR and on its issue (when there is one).

```markdown
## TL;DR

<One or two sentences: what you need and what it unblocks.>

**Blocks:** #<blocked issue or PR>

## Context

<What happened, what you tried, and the evidence. Keep it short; link logs and comments.>

## Decisions

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|

## Runbook

Run these in order:

1. `<exact command or action>` — expect: <output or state>
2. …

## When done

Reply with `done`, or with the step and output where something failed; when there is a Decisions section, include your answers (`1: <option>`). Then rerun `/implement` with `#<issue>` for an issue, or the bare PR number for a PR.
```

Order the runbook so that a decision changing later steps comes before them. Write copy-pasteable commands with the expected result of each; omit the Runbook or Decisions section when empty.

**While waiting.** Continue work that does not depend on the answer, park the rest, and print the run ledger with `Outcome: awaiting owner — #<request>`. Use `escalated` only when no request could be opened.

**Resuming.** A run finds the request through the target's `Blocked on #<request>` comment, or an open `needs-owner` issue whose Blocks line names the target. When the target is blocked on an open owner request:

- **Answered:** read the answers and step results, confirm the runbook's end state yourself where you can, comment a short summary, close the request, and continue from the parked phase.
- **Not answered:** report that it is still waiting and stop; do not re-ask or open another request.
