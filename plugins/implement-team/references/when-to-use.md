# When to use `/implement-team`

Three implementation-lifecycle commands ship from this marketplace. They target the same phases (plan, implement, review/address, docs gate, verify, merge) but differ in architecture, token cost, maturity, and environment requirements. Pick based on task shape, cost tolerance, and whether the experimental agent-teams feature is available.

## Decision table

| Task shape | Recommended command | Why |
|------------|---------------------|-----|
| Routine / small / narrowly scoped change (typo, one-file fix, well-understood feature) | `/implement` | Lowest token cost, mature, single-session forked subagents are sufficient for a small change. No environment setup required. |
| Default lifecycle work on a normal-sized feature or bug | `/implement` | Good default. The forked-subagent orchestrator handles the standard lifecycle cleanly for the majority of tasks. |
| Ambiguous, cross-module, or long-running task where reviewers benefit from persistent context | `/implement-team` | Long-lived reviewer teammates share a task list and dedupe with each other across rounds. Fewer speculative findings and less cross-reviewer overlap than parallel forked subagents. |
| Security-sensitive change where every reviewer finding must be triaged against the others | `/implement-team` | The shared task list + mailbox messaging lets reviewers cross-check each other before findings reach the lead referee. Reduces duplicated or contradictory security findings. |
| Multi-provider orchestration, CI execution, or cost-optimization with non-Anthropic models | `/implement-cli` | Python Agent SDK subprocess orchestration supports multiple providers and is designed for non-interactive execution with explicit cost/session tracking. |
| Large batch, unattended, or scripted run where you need structured JSON output and a run directory | `/implement-cli` | Every invocation returns a `tracking` block with session IDs, costs, tokens, and a `run_dir` holding all artifacts. Built for observability and scripting. |
| Experimental / research work willing to trade token cost for better reviewer collaboration | `/implement-team` | Explicitly experimental. Accepts higher token cost in exchange for the agent-teams collaboration model. |
| Environment cannot enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` or cannot run Claude Code 2.1.32+ | `/implement` or `/implement-cli` | `/implement-team` preflight will exit without doing work if either requirement is unmet. |

## The three commands at a glance

### `/implement` (plugin: `implement-lifecycle`)

Lean orchestrator that delegates all heavy work to forked subagents within a single Claude Code session. Mature (version 3.x), lowest token cost, no special environment requirements. This is the good default — pick it unless you have a specific reason to reach for one of the others.

- Architecture: single-session orchestrator + forked subagents (`implement-code`, `implement-address`, reviewer agents, `verify`, `merge-pr`).
- Review model: reviewers run in parallel and post their own PR comments; the orchestrator referees findings.
- Strengths: mature, cheap, portable, works out of the box.

### `/implement-team` (plugin: `implement-team`, this plugin)

Same lifecycle re-architected around Claude Code's experimental agent-teams feature. Long-lived implementer and reviewer teammates share a task list and exchange directed messages via a mailbox. The team lead is the **sole GitHub publisher** — reviewers write findings to the shared task list, the lead synthesizes and posts a single authoritative round-N comment.

- Architecture: persistent teammates spawned once per run; shared task list; `SendMessage` mailbox; lead-only GitHub publisher.
- Review model: reviewers dedupe with siblings in the shared task list before the lead referees. Fewer speculative findings, less cross-reviewer overlap, one clean PR timeline comment per round instead of four.
- Strengths: better cross-reviewer collaboration on long or cross-cutting tasks.
- Tradeoffs: higher token cost than `/implement`; depends on experimental agent-teams; one team per session; caveats below.
- Status: experimental (version 0.x).

### `/implement-cli` (plugin: `implement-cli`)

CLI-based multi-provider implementation lifecycle using the Python Agent SDK for subprocess orchestration. The orchestrator is a Claude Code session; heavy work runs as `claude-agent-sdk` subprocesses with native async parallelism. Each run gets a unique `run_dir` holding prompts, findings files, and a `run_context.json` with full session history.

- Architecture: Claude Code orchestrator + subprocess agents via `claude-agent-sdk`; explicit cost/depth caps via `--max-cost` and `--max-depth`.
- Review model: same referee-over-specialist-reviewers pattern as `/implement`, executed through CLI subprocess calls.
- Strengths: multi-provider support, structured JSON tracking, session resume and debug commands, suitable for CI / non-interactive / cost-optimized runs.
- Tradeoffs: requires the CLI toolchain and Python Agent SDK; more setup than `/implement`.

## Experimental caveats for `/implement-team`

`/implement-team` depends on Claude Code's experimental agent-teams feature. It will refuse to run (preflight fails) if either of the first two conditions is not met. The remaining items are behavioral constraints of the feature itself.

- **Environment variable required.** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` must be set at Claude Code startup. Set it in `~/.claude/settings.json` or `.claude/settings.json` under `env`, or export it in the shell that launches Claude Code. Toggling it mid-session does not take effect — you must fully restart Claude Code (not just `/resume`).
- **Minimum Claude Code version.** 2.1.32 or later. `claude --version` must report a version `>= 2.1.32` for preflight to pass.
- **One team per session.** A Claude Code session can host at most one agent-team at a time. Do not attempt to run `/implement-team` concurrently with another team-spawning command in the same session.
- **`/resume` and `/rewind` break in-process teammates.** In-process teammates do not survive `/resume`, and `/rewind` can desynchronize them from the lead. If you need to pause and come back to a run, expect to restart the team rather than resume it.
- **No nested teams.** A teammate cannot itself spawn a team. This plugin's lead spawns teammates directly and does not recurse.
- **Higher token cost.** Persistent teammates hold context across rounds and exchange messages, which costs more tokens than the forked-subagent model used by `/implement`. Expect meaningfully higher spend per lifecycle run. Budget accordingly.
- **tmux / iTerm2 caveats for split-pane display.** The default in-process mode is portable and has no terminal dependencies. Optional split-pane rendering of teammate activity relies on tmux or iTerm2 and is not guaranteed to work in every environment. Stick with the default in-process mode unless you have explicitly configured and verified a split-pane setup.

Preflight for these conditions is enforced in `plugins/implement-team/skills/implement-team/SKILL.md` — the skill exits with a user-facing message rather than attempting partial work.

## Links

- Agent-teams documentation: https://code.claude.com/docs/en/agent-teams
- `/implement` skill: `plugins/implement-lifecycle/skills/implement/SKILL.md`
- `/implement-team` skill: `plugins/implement-team/skills/implement-team/SKILL.md`
- `/implement-cli` skill: `plugins/implement-cli/skills/implement-cli/SKILL.md`
