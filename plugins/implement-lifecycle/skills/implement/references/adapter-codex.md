# Codex Adapter

Launch fresh children with `spawn_agent` whose prompt begins `Use $implement-lifecycle:<skill>`, followed by the complete payload. Map `balanced` to the harness's default coding model with **`reasoning_effort: "medium"`** on all `balanced` subagents (especially `review-*`, `implement-address`, and `verify`; never `"high"` on reviewers or verifiers). Map `frontier` (`implement-code` when pre-assessed `High` risk/complexity) to the strongest coding model with `reasoning_effort: "high"`. Keep the returned agent ID for continuations.

For supervision, always pass `wait_agent` an explicit `timeout_ms` equal to the current check-in interval (minutes, up to its 3600000 maximum); its 30-second default turns waiting into tight polling. A timeout summary means no child reported in that interval.

For continuations (addressing feedback, follow-up delta reviews, clarifications, and re-verification), send follow-ups to that existing agent with `send_message` or `followup_task` followed by `wait_agent` rather than spawning a new subagent. Reuse the existing `implement-code` author agent directly in its Continuation Mode for addressing without loading a second skill.
