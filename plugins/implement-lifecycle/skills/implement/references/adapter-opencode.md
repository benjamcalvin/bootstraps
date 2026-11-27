# OpenCode v2 Adapter

Launch fresh children with the `subagent` tool (`description` plus a `prompt` beginning `Use the skill tool to load "<skill>", then run:` followed by the complete payload). Map `balanced` to the `lifecycle-balanced` subagent when present in the subagent catalog, otherwise `general` (never `explore`, which is read-only and denies `skill` by default); map `frontier` (`implement-code` when pre-assessed `High` risk/complexity) to `lifecycle-frontier` when present, otherwise `general`.

`subagent` calls always run asynchronously in the background and return a `sessionID` immediately — keep each returned `sessionID`, stop calling tools when waiting on active subagents, and let OpenCode wake the session with their `<subagent>` completion messages (never poll in a tight loop). For continuations (addressing feedback via `implement-code` Continuation Mode, Round 2 delta reviews, clarifications, and Phase-5 re-checks), call `subagent` again passing that existing `sessionID` rather than spawning a new child.

For supervision, when no completion message arrives within the check-in interval, a single bounded shell `sleep <interval>` is the timer. Read a child's last activity from its session's last-updated time.
