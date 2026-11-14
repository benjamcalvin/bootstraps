# Convergence-recovery decision

Read this when the Phase 4 escalation exit fires: the Round 2 cap is reached with unresolved Action Required findings, or a scope/convergence guard fires. Do not default to stopping. Diagnose why the loop is not converging and choose one path:

- **Revise-and-reset — original scope insufficiently specific.** The reviews kept surfacing ambiguity: underspecified acceptance criteria, conflicting requirements, or findings the original issue never pinned down. Capture what the reviews revealed about the real requirement, reset the branch to a clean head, revise the issue to be specific and unambiguous, and open a **clean PR** built on the revised issue. Clear `agents` in `state.json` and spawn fresh children for the new loop so drifted context is not carried over.
- **Restart-clean — gone off track.** The loop is dominated by review-introduced architecture or scope creep that drifted from the original issue. Discard the drifted work and restart with **clearer guidelines** that bind the work to the original scope. Clear `agents` in `state.json` and spawn fresh children so drifted context is not carried over. Update the issue with notes that give clearer instructions; even a partial clarification (an added constraint, a boundary, a worked example, or an explicit "out of scope" note) materially improves the next attempt.
- **Escalate to the user.** The stall is a genuinely hard ambiguity that self-revision cannot resolve, or the user should choose between the paths. Self-recovery is not mandatory. Post this comment, print the run ledger, stop, and tell the user directly:

```markdown
## Escalation — Review Loop Stopped

Review loop stopped after <N> round(s).

### Unresolved items
<each unresolved item with what was attempted>

Requesting human review.
```

Recovery means starting a NEW loop (revised or clean), never continuing the stalled one: clear `agents` in `state.json` and spawn fresh children so drifted context is not carried over. Do not extend the same loop past the round cap without explicit user authorization.
