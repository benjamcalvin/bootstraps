# Generic Adapter

Create a fresh isolated child, load the mapped Agent Skill explicitly, pass the complete payload, and return the child result. Map `balanced` and `frontier` to the closest available balanced and strongest models. Keep child handles for continuations. A harness that cannot provide isolated delegation or load the required skill must report the failed phase and must not execute it inline.

When the harness supports messaging or resuming an existing child handle, reuse that same child for continuations (continuing `implement-code` directly in Continuation Mode, plus follow-up delta reviews, clarifications, and re-verification), falling back to a fresh child only when subagents are strictly one-shot.
