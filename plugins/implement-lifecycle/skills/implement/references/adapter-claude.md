# Claude Code Adapter

Spawn a generic isolated subagent whose prompt begins `Use the implement-lifecycle:<skill> plugin skill`, followed by the complete payload and context-bundle path. Pass the Agent tool's `model` parameter explicitly: `"sonnet"` for `balanced`; omit it (inherit) for `frontier`.
