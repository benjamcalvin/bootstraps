# Bootstraps

A cross-compatible Claude Code and OpenAI Codex plugin marketplace of reusable skills, hooks, and project scaffolds.

## Prerequisites

This is a private repository. You need access to `benjamcalvin/bootstraps` on GitHub and git credentials configured (e.g. `gh auth login`).

For automatic plugin updates at Claude Code startup, set a GitHub token in your environment:

```sh
export GITHUB_TOKEN=ghp_your_token_here
```

Without this, plugins still work — you just need to update manually with `/plugin marketplace update bootstraps`.

## Install in Claude Code

Add the marketplace to Claude Code:

```
/plugin marketplace add benjamcalvin/bootstraps
```

## Browse Plugins

List available plugins:

```
/plugin marketplace list
```

Or open the interactive plugin manager:

```
/plugin
```

Navigate to the **Discover** tab to browse plugins from this marketplace.

## Install in Codex

Add the marketplace to Codex CLI:

```sh
codex plugin marketplace add benjamcalvin/bootstraps
```

Open the plugin browser with `/plugins`, install a plugin from the **Bootstraps** marketplace, and start a new session so Codex loads its skills.

The Codex marketplace currently includes `bootstrap-docs`, `implement-lifecycle`, and `issue-management`. The other plugins depend on Claude Code-specific hooks, worktree behavior, agent teams, or the Claude Agent SDK and remain available only through Claude Code.

Install the lifecycle plugin directly with:

```sh
codex plugin add implement-lifecycle@bootstraps
```

## Install a Plugin in Claude Code

```
/plugin install bootstrap-docs@bootstraps
/plugin install implement-lifecycle@bootstraps
/plugin install implement-cli@bootstraps
/plugin install implement-team@bootstraps
/plugin install issue-management@bootstraps
/plugin install bootstrap-worktrees@bootstraps
/plugin install stop-guard@bootstraps
```

Choose a scope when prompted:
- **user** (default) — available in all your projects
- **project** — available to anyone working on the current project
- **local** — only for you in the current project

## Use a Plugin

In Claude Code, invoke a plugin's skill as a slash command:

```
/bootstrap-docs
/implement #42
```

Some skills accept arguments:

```
/bootstrap-docs adr
/implement #42
/implement fix the login bug
/implement 17 just review
/implement-cli #42
/implement-team #42
/bootstrap-worktrees
/draft-issue add user avatar support
/cleanup-issue #42
/refine-issue #42
```

In Codex, mention the plugin-namespaced skill with `$`:

```text
$implement-lifecycle:implement #42
$implement-lifecycle:implement fix the login bug
$implement-lifecycle:implement 17 just review
$implement-lifecycle:merge-pr 17
$implement-lifecycle:pr-check 17
```

## Update Claude Code Plugins

```
/plugin marketplace update bootstraps
```

## Uninstall a Claude Code Plugin

```
/plugin uninstall bootstrap-docs@bootstraps
/plugin uninstall implement-lifecycle@bootstraps
/plugin uninstall implement-cli@bootstraps
/plugin uninstall implement-team@bootstraps
/plugin uninstall issue-management@bootstraps
/plugin uninstall bootstrap-worktrees@bootstraps
/plugin uninstall stop-guard@bootstraps
```

## Available Plugins

| Plugin | Claude Code | Codex | Description |
|--------|-------------|-------|-------------|
| **bootstrap-docs** | Yes | Yes | Set up a comprehensive, AI-readable documentation strategy in any project. Creates AGENTS.md, specs, ADRs, guides, plans, standards, and research templates. |
| **bootstrap-worktrees** | Yes | No | Set up project-agnostic worktree isolation with per-worktree ports, Docker Compose projects, and Claude Code hooks. |
| **implement-lifecycle** | Yes | Yes | Full implementation lifecycle with delegated implementation, parallel specialist review, verification, and merge. |
| **implement-cli** | Yes | No | CLI-based lifecycle using the Claude Agent SDK to orchestrate review/address subprocesses. |
| **implement-team** | Yes | No | Experimental lifecycle built around Claude Code agent-teams. |
| **issue-management** | Yes | Yes | Draft, clean up, and refine GitHub issues for AI agent consumption. |
| **stop-guard** | Yes | No | Claude Code Stop hook that evaluates task completion through Gemini CLI. |

### implement-lifecycle

Provides 11 cross-client skills plus 5 Claude Code reviewer-agent wrappers for the complete implementation lifecycle. Claude Code uses the named agents during review; Codex delegates to subagents that load the corresponding reviewer skills.

**Skills:**

| Skill | Description |
|-------|-------------|
| `/implement` | Lean orchestrator — 6-phase lifecycle (plan → implement → PR → review loop → verify → merge). Accepts `#issue`, PR number, or freeform task. Supports trailing instructions like "just review" or "skip planning". |
| `/merge-pr` | Validate, squash-merge, delete branch, and update linked GitHub issues with delivery status. |
| `/pr-check` | Pre-flight PR validation — branch naming, title, description, sizing, commits, references. |

**Subagent skills** (invoked by the orchestrator, not directly):

| Skill | Description |
|-------|-------------|
| `implement-code` | Explore codebase, plan, write tests first, implement, self-review, commit, and create PR. |
| `implement-address` | Address filtered review findings from the referee's action plan. |
| `verify` | End-to-end verification — exercises the real running system, checks downstream effects, regression tests existing flows. |

**Portable reviewer roles** (invoked in parallel during the review loop):

| Agent/skill | Focus |
|-------------|-------|
| `review-correctness` | Logic bugs, edge cases, error handling, race conditions |
| `review-security` | AuthZ, injection risks, PII handling, spec conformance |
| `review-architecture` | Pattern consistency, module boundaries, coupling, forward-looking design |
| `review-testing` | Test coverage, assertion quality, edge cases, test anti-patterns |
| `review-docs` | Docs compliance gate (Phase 4.5) — missing docs for new behavior, stale docs contradicted by code changes, frontmatter/cross-link correctness |

### implement-cli

Single-skill plugin that mirrors the `/implement` lifecycle but delegates heavy work to Python Agent SDK subprocesses.

| Skill | Description |
|-------|-------------|
| `/implement-cli` | Same 6-phase lifecycle as `/implement` (plan → implement → PR → review loop → docs gate → verify → merge), but the orchestrator runs review/address phases as `claude-agent-sdk` subprocesses with native async parallelism. Accepts the same argument shapes and trailing instructions as `/implement`. |

### implement-team

**Experimental.** Requires Claude Code `>= 2.1.32` and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Re-architects the implementation lifecycle around long-lived teammates that share a task list and mailbox instead of forked one-shot subagents.

| Skill | Description |
|-------|-------------|
| `/implement-team` | Full implementation lifecycle run by an orchestrator ("lead") that coordinates persistent `team-implementer`, `team-verifier`, and reviewer teammates. Lead is the sole GitHub publisher; reviewers post findings to the shared task list only. Trades higher token cost for fewer speculative findings and cross-reviewer dedupe. |

| Agent | Role |
|-------|------|
| `team-implementer` | Long-lived implementer. Acts only on lead direction; refuses reviewer work requests and answers batched factual questions only. |
| `team-verifier` | Long-lived verifier. Runs end-to-end verification on lead invocation and reports PASS/FAIL/PARTIAL/N/A evidence. |
| `team-reviewer-correctness` | Correctness specialist — same focus as `review-correctness`, with persistent-team messaging discipline. |
| `team-reviewer-security` | Security / requirements-conformance specialist. |
| `team-reviewer-architecture` | Architecture and design specialist. |
| `team-reviewer-testing` | Test-quality specialist. |
| `team-reviewer-docs` | Docs compliance specialist (invoked only in the Phase 4.5 gate). |

### bootstrap-worktrees

Single-skill plugin for project-agnostic worktree isolation.

| Skill | Description |
|-------|-------------|
| `/bootstrap-worktrees` | Discover services in a project, assign per-worktree port offsets, generate `scripts/create-worktree.sh` and `scripts/remove-worktree.sh`, wire up Docker Compose project isolation, and register Claude Code hooks so new sessions land in isolated environments. |

### issue-management

Provides 3 skills for GitHub issue quality:

| Skill | Description |
|-------|-------------|
| `/draft-issue` | Create well-structured GitHub issues with testable acceptance criteria, optimized for `/implement` consumption. |
| `/cleanup-issue` | Fix formatting, fill missing sections, and clarify ambiguity in existing issues. |
| `/refine-issue` | Deepen an issue with codebase research — sharpen acceptance criteria, add implementation hints, decompose into sub-tasks. |

### stop-guard

A Stop hook — no skills to invoke. Once installed, it activates when any session transcript contains `<!-- stop-guard:active -->`.

**Requires:** [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`npm install -g @google/gemini-cli`), [jq](https://jqlang.github.io/jq/)

**How it works:** When Claude tries to stop, the hook calls Gemini to independently evaluate whether the task is complete. If incomplete, it blocks the stop and tells Claude what to finish. If complete (or if human input is needed), it allows the stop.

**Activation:** Include `<!-- stop-guard:active -->` in a skill's output or type it directly in conversation. Optionally provide context:

```
<!-- stop-guard:context {"task": "implement feature X", "criteria": ["tests pass"]} -->
```

**Safety:** Opt-in per session, max 3 continuations (configurable), fail-open on any error, 60s timeout.

**Configuration** (optional): `~/.config/stop-guard/config.json`

```json
{"max_continuations": 3, "model": "gemini-3-flash-preview"}
```

**Testing:** Run the evaluator against any session without triggering the hook:

```
./plugins/stop-guard/hooks/test-stop-guard.sh ~/.claude/projects/<project>/<session>.jsonl
```

See [stop-guard/README.md](plugins/stop-guard/README.md) for full documentation.

## License

MIT
