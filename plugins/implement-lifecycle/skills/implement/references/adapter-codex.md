# Codex Adapter

Spawn a generic isolated subagent whose prompt begins `Use $implement-lifecycle:<skill>`, followed by the complete payload and context-bundle path. Map `balanced` to the harness's balanced/default coding model and `frontier` to its strongest model. Save the returned agent ID.

For continuations (addressing feedback, follow-up delta reviews, clarifications, corrections, and re-verification), send follow-up instructions and payloads to that existing agent (`send_input` and `wait`) rather than spawning a new subagent. On the first address pass, direct the existing author agent to `Use $implement-lifecycle:implement-address`.
