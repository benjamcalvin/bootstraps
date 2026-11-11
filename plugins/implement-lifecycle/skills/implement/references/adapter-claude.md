# Claude Code Adapter

Spawn a generic isolated subagent whose prompt begins `Use the implement-lifecycle:<skill> plugin skill`, followed by the complete payload and context-bundle path. Pass the Agent tool's `model` parameter explicitly: `"sonnet"` for `balanced`; omit it (inherit) for `frontier`. Save the returned `agentId`.

For continuations (addressing feedback, follow-up delta reviews, clarifications, corrections, and re-verification), reuse that existing subagent: pass `resume: "<agentId>"` to the Agent tool (or `SendMessage` when available) with the follow-up payload and instructions instead of spawning a new subagent. For addressing, resume the author agent (`implement-code`) directing it: `Use the implement-lifecycle:implement-address plugin skill`.
