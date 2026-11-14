# Codex Adapter

Launch fresh children with `spawn_agent` whose prompt begins `Use $implement-lifecycle:<skill>`, followed by the complete payload and `bundle=` path. Map `balanced` to the harness's default coding model with **`reasoning_effort: "medium"`** on all `balanced` subagents (especially `review-*`, `implement-address`, and `verify`; never `"high"` on reviewers or verifiers). Map `frontier` (`implement-code` when pre-classified `Large`) to the strongest coding model with `reasoning_effort: "high"`. Immediately record the returned agent ID in `state.json`.

For continuations (addressing feedback, follow-up delta reviews, clarifications, and re-verification), look up the agent ID in `state.json` and send follow-ups to that existing agent with `send_message` or `followup_task` followed by `wait_agent` rather than spawning a new subagent. Reuse the existing `implement-code` author agent directly in its Continuation Mode for addressing without loading a second skill.
