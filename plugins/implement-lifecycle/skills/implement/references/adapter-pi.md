# Pi Adapter

With the user-installed `pi-subagents` prerequisite available, launch a generic `delegate` child with `skill: <skill>`, `context: "fresh"`, and the complete payload and `bundle=` path. Map `balanced` to the delegate's balanced model and `frontier` to its strongest. Record returned handles in `state.json`. Do not use or distribute custom Pi agent definitions.

For continuations (addressing feedback, follow-up delta reviews, clarifications, and re-verification), when `pi-subagents` exposes session or agent resumption, continue that child's session from `state.json` (continuing `implement-code` directly in Continuation Mode); otherwise fall back to a new `delegate` call with `context: "fresh"` and `bundle=<path>`.
