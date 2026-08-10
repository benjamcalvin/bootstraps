# Bootstraps

A cross-compatible Claude Code, OpenAI Codex, and Pi collection of reusable skills, hooks, and project scaffolds.

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

## Install implement-lifecycle in Pi

Pi can install the plugin directory as a local package. From a checkout of this repository, run:

```sh
pi install ./plugins/implement-lifecycle
```

This package exposes its `skills/` directory through `package.json`; restart Pi, then use `/skill:implement #42`. For lifecycle delegation, separately install [`pi-subagents`](https://github.com/nicobailon/pi-subagents); it supplies the generic `delegate` child used by the Pi adapter. The adapter explicitly requests fresh context for every child and retries or recovers empty reviewer results before refereeing. It is a user-managed prerequisite, not a bundled dependency.

## Install a Plugin in Claude Code

```
/plugin install bootstrap-docs@bootstraps
/plugin install implement-lifecycle@bootstraps
/plugin install issue-management@bootstraps
/plugin install bootstrap-worktrees@bootstraps
/plugin install stop-guard@bootstraps
/plugin install second-opinion@bootstraps
```

`implement-cli` (WIP) and `implement-team` (deprecated) remain installable but are not recommended — use `implement-lifecycle` instead:

```
/plugin install implement-cli@bootstraps
/plugin install implement-team@bootstraps
```

Choose a scope when prompted:
- **user** (default) — available in all your projects
- **project** — available to anyone working on the current project
- **local** — only for you in the current project

## Use a Plugin

### Claude Code

Invoke a plugin's skill as a slash command:

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
/bootstrap-worktrees
/draft-issue add user avatar support
/cleanup-issue #42
/refine-issue #42
/second-opinion staged
```

### Codex

Invoke the currently published Codex plugins' skills with their plugin-qualified names:

```
$bootstrap-docs:bootstrap-docs
$implement-lifecycle:implement #42
$issue-management:draft-issue add user avatar support
$issue-management:cleanup-issue #42
$issue-management:refine-issue #42
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
/plugin uninstall second-opinion@bootstraps
```

## Available Plugins

| Plugin | Claude Code | Codex | Pi | Description |
|--------|-------------|-------|----|-------------|
| **bootstrap-docs** | Yes | Yes | No | Set up a comprehensive, AI-readable documentation strategy in any project. Creates AGENTS.md, specs, ADRs, guides, plans, standards, and research templates. |
| **bootstrap-worktrees** | Yes | No | No | Set up project-agnostic worktree isolation with per-worktree ports, Docker Compose projects, and config files. Discovers services and generates create/remove scripts plus Claude Code hooks. |
| **implement-lifecycle** | Yes | Yes | Yes | Full implementation lifecycle with adversarial PR review — plan, implement, PR, review/address loop, docs gate, verify, merge. Pi delegation requires `pi-subagents`. |
| **implement-cli** | Yes | No | No | **WIP — not recommended for general use.** CLI-based variant of the implementation lifecycle using the Python Agent SDK to orchestrate review/address subprocesses with native async parallelism. |
| **implement-team** | Yes | No | No | **Deprecated — use implement-lifecycle instead.** Implementation lifecycle re-architected around Claude Code agent-teams — long-lived implementer and reviewer teammates with shared task list and mailbox messaging. |
| **issue-management** | Yes | Yes | No | Draft, clean up, and refine GitHub issues — optimized for AI agent consumption. |
| **stop-guard** | Yes | No | No | Stop hook that evaluates task completion via Gemini CLI and blocks premature stops. Opt-in per session via activation marker. |
| **second-opinion** | Yes | No | No | Consult external AI CLIs (Codex, Antigravity) headlessly for an independent, read-only second-opinion code review of your changes. |

### implement-lifecycle

Provides a shared lifecycle orchestrator, two utility skills, three delegated worker roles, a baseline general reviewer, four optional targeted specialists, and a separate docs gate across Claude Code, Codex, Pi, and other compatible harnesses:

**Skills:**

| Skill | Description |
|-------|-------------|
| `/implement` / `$implement-lifecycle:implement` | Lean orchestrator — 6-phase lifecycle (plan → implement → PR → review loop → verify → merge). Accepts `#issue`, PR number, or freeform task. Supports trailing instructions like "just review" or "skip planning". |
| `/merge-pr` / `$implement-lifecycle:merge-pr` | Validate, squash-merge, delete branch, and update linked GitHub issues with delivery status. |
| `/pr-check` / `$implement-lifecycle:pr-check` | Pre-flight PR validation — branch naming, title, description, commits, references, plus an advisory scope note. |

**Delegated worker roles** (invoked by the orchestrator, not directly):

| Role | Description |
|-------|-------------|
| `implement-code` | Explore codebase, plan, write tests first, implement, self-review, commit, and create PR. |
| `implement-address` | Address filtered review findings from the referee's action plan. |
| `verify` | End-to-end verification — exercises the real running system, checks downstream effects, regression tests existing flows. |

**Review roles:**

| Role | Focus |
|-------|-------|
| `review-general` | Baseline holistic reviewer for requirements, project conventions, established patterns, scope, integration, and test adequacy. |
| `review-correctness` | Optional targeted specialist for logic bugs, edge cases, error handling, and race conditions. |
| `review-security` | Optional targeted specialist for AuthZ, injection risks, and PII handling. |
| `review-architecture` | Optional targeted specialist for module boundaries, coupling, and forward-looking design. |
| `review-testing` | Optional targeted specialist for test coverage, assertion quality, edge cases, and test anti-patterns. |
| `review-docs` | Separate Phase 4.5 docs-compliance gate for missing docs, stale docs, and frontmatter/cross-link correctness. |

Heavy phases always run in fresh generic isolated delegated children. The canonical phase-to-skill mapping is shared by every harness: Claude Code selects `implement-lifecycle:<skill>`, Codex selects `$implement-lifecycle:<skill>`, and Pi's user-installed `pi-subagents` launches a generic `delegate` child with `skill: <skill>` and explicit fresh context. Compatible harnesses must explicitly load the mapped Agent Skill, pass the complete payload and context bundle, return a non-empty child result, and never fall back to inline execution when isolation or skill loading is unavailable. Selected reviewers run in parallel and all canonical structured results return before refereeing. Model selection remains a per-delegation decision.

Focused acceptance commands belong to implementation and review workers. Final verification alone owns the lifecycle-wide suite, records its exit status on the exact final commit, and runs it no more than once; matching recorded evidence is reused. Documentation findings always pass through review, address, and re-review before verification.

The skill-local `agents/openai.yaml` files are optional OpenAI skill metadata that supplies presentation and invocation policy. They are not subagent definitions, are retained for Codex compatibility, and do not change the harness-neutral worker behavior. No custom Pi agent templates are distributed.

Reviewers return their findings to the orchestrator and post nothing themselves. The orchestrator is the sole publisher to the PR timeline: it publishes one consolidated comment per round carrying every reviewer's findings plus its referee decisions.

Codex CLI 0.145.0 note: full lifecycle delegation works in a standard Codex session; headless `codex exec --ephemeral` sessions fail to initialize spawned subagents.

### implement-cli

> **🚧 Work in progress — not recommended for general use.** Unfinished and not
> stable; its reviewer prompts drift from the canonical `implement-lifecycle`
> review skills (tracked in
> [#96](https://github.com/benjamcalvin/bootstraps/issues/96)) and its behaviour
> may change without notice. Use
> `implement-lifecycle` (`/implement`) for day-to-day work.

Single-skill plugin that mirrors the `/implement` lifecycle but delegates heavy work to Python Agent SDK subprocesses.

| Skill | Description |
|-------|-------------|
| `/implement-cli` | Same 6-phase lifecycle as `/implement` (plan → implement → PR → review loop → docs gate → verify → merge), but the orchestrator runs review/address phases as `claude-agent-sdk` subprocesses with native async parallelism. Accepts the same argument shapes and trailing instructions as `/implement`. |

Reviewers return their findings to the orchestrator and post nothing themselves; the orchestrator is the sole publisher, posting one consolidated comment per round.

### implement-team

> **⚠️ Deprecated — no longer maintained.** Use `implement-lifecycle`
> (`/implement`) instead: it covers the same lifecycle, works on both Claude Code
> and Codex, and does not depend on the experimental agent-teams runtime.
> `implement-team` stays installable so existing users are not broken, but it
> receives no fixes and will be removed in a future release.

Requires Claude Code `>= 2.1.32` and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Re-architects the implementation lifecycle around long-lived teammates that share a task list and mailbox instead of forked one-shot subagents.

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

### second-opinion

Single-skill plugin that consults external AI CLIs for an independent code review.

| Skill | Description |
|-------|-------------|
| `/second-opinion` | Fan out a review of the current changes to every supported external CLI installed (OpenAI Codex, Google Antigravity), run them read-only in parallel, cross-check findings, and present one consolidated review with per-provider attribution and consensus items first. Accepts an optional scope (`staged`, a PR number, or a git range) and/or a provider name (`codex` / `antigravity`); defaults to branch-vs-main across all available providers. Only reports — never applies fixes. |

See [second-opinion/README.md](plugins/second-opinion/README.md) for full documentation.

## License

MIT
