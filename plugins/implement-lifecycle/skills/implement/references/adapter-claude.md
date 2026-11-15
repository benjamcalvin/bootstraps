# Claude Code Adapter

Spawn a fresh isolated subagent whose prompt begins `Use the implement-lifecycle:<skill> plugin skill`, followed by the complete payload. Pass the Agent tool's `model` parameter explicitly: `"sonnet"` for `balanced`; omit it (inherit) for `frontier`. **Never omit `model` on any `review-*`, `implement-address`, or `verify` spawn**, because omitting `model` silently inherits `opus`. Keep the returned `agentId` for continuations.

For continuations (addressing feedback, follow-up delta reviews, clarifications, and re-verification), reuse that existing subagent via `resume: "<agentId>"` on the Agent tool (or `SendMessage` when available) rather than spawning a new subagent. Continue the existing `implement-code` author agent directly with its findings payload (using its Continuation Mode without loading a second skill).
