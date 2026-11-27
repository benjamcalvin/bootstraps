# Antigravity (agy) Adapter

Spawn a fresh isolated child via `invoke_subagent` with `TypeName: "self"`, instructing the child to `read_file` the mapped canonical `SKILL.md` first, followed by the complete payload. Map `balanced` to `Model: "flash"` and `frontier` to `Model: "inherit"`. Keep the returned `conversationId` for continuations. Use `swarm` (`action: "add"` with explicit `model`) only when the user explicitly pins a concrete model ID that `invoke_subagent` cannot express; otherwise prefer `invoke_subagent`.

For continuations (addressing feedback, follow-up delta reviews, clarifications, and re-verification), use `send_message` (`Recipient: "<conversationId>"`) rather than spawning a new child. Pass findings directly to the existing `implement-code` author child in its Continuation Mode without loading a second skill.

For supervision, use `schedule` (`DurationSeconds` set to the check-in interval) as the timer, `manage_subagents` (`Action: "list"`) for child status, and `manage_task` (`status`, `kill`) for a hung background task.
