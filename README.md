# Bootstraps

A cross-compatible Claude Code, OpenAI Codex, Antigravity (agy), and Pi collection of reusable skills and project scaffolds.

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

The Codex marketplace includes all three plugins (`bootstrap-docs`, `implement-lifecycle`, and `issue-management`).

## Install in Antigravity

Antigravity workspaces automatically discover plugins in this repository through `.agents/plugins.json`.

To install a plugin into Antigravity from a local checkout:

```sh
agy plugin install ./plugins/bootstrap-docs
agy plugin install ./plugins/implement-lifecycle
agy plugin install ./plugins/issue-management
```

To validate a plugin definition against the Antigravity plugin schema:

```sh
agy plugin validate plugins/<name> --strict
```

## Install implement-lifecycle in Pi

Pi can install the plugin directory as a local package. From a checkout of this repository, run:

```sh
pi install ./plugins/implement-lifecycle
```

This package exposes its `skills/` directory through `package.json`; restart Pi, then use `/skill:implement #42`. For lifecycle delegation, separately install [`pi-subagents`](https://github.com/nicobailon/pi-subagents); it supplies the fresh generic `delegate` child used by the Pi adapter. It is a user-managed prerequisite, not a bundled dependency.

## Install a Plugin in Claude Code

```
/plugin install bootstrap-docs@bootstraps
/plugin install implement-lifecycle@bootstraps
/plugin install issue-management@bootstraps
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
/bootstrap-docs migrate
/bootstrap-docs docs-check
/implement #42
/implement fix the login bug
/implement 17 just review
/draft-issue add user avatar support
/cleanup-issue #42
/refine-issue #42
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
/plugin uninstall issue-management@bootstraps
```

## Available Plugins

| Plugin | Claude Code | Codex | Antigravity | Pi | Description |
|--------|-------------|-------|-------------|----|-------------|
| **bootstrap-docs** | Yes | Yes | Yes | No | Set up a comprehensive, AI-readable documentation strategy in any project. Creates AGENTS.md, specs, ADRs, guides, plans, standards, and research templates. |
| **implement-lifecycle** | Yes | Yes | Yes | Yes | Streamlined implementation lifecycle scaled by risk and complexity — plan, implement, PR, bounded general review, parallel verify + docs review, and inline rule-guided merge. Pi delegation requires `pi-subagents`. |
| **issue-management** | Yes | Yes | Yes | No | Draft, clean up, and refine GitHub issues — optimized for AI agent consumption. |

### implement-lifecycle

Provides a shared lifecycle orchestrator, a rule-guided merge skill, two coding/addressing workers, a unified general reviewer, a docs reviewer, and an end-to-end verification worker across Claude Code, Codex, Antigravity (agy), Pi, and other compatible harnesses:

**Skills:**

| Skill | Description |
|-------|-------------|
| `/implement` / `$implement-lifecycle:implement` | Lean orchestrator — lifecycle of plan → implement → PR → code review loop → parallel verify + docs review → inline merge. Accepts `#issue`, PR number, or freeform task. Supports trailing instructions like "just review" or "skip planning". |
| `/merge-pr <pr-number>` / `$implement-lifecycle:merge-pr <pr-number>` | Inline Phase 6 / standalone merge following the target project's rules, guarding `Verified-Head` / `--match-head-commit`, and updating linked issues. |

**Delegated worker roles** (invoked by the orchestrator, not directly):

| Role | Description |
|-------|-------------|
| `implement-code` | Explore codebase, plan, write outcome-based tests covering new/changed behavior, implement, self-review, commit, create PR, and address review findings in Continuation Mode. |
| `implement-address` | Standalone or fresh addresser for pre-existing PRs where no `implement-code` author child exists in the session. |
| `verify` | Real-world verification worker that inspects and exercises the actual built work (data outputs/shapes, CLI execution, frontend navigation & screenshots, live services) in parallel with `review-docs` when a live/observable surface changed. |

**Review roles:**

| Role | Focus |
|-------|-------|
| `review-general` | Unified holistic reviewer covering **security**, **simplicity**, and **quality**. Defaults to 1 instance; scales to 2–3 parallel instances splitting surface area or focus only for very large/complex changes. |
| `review-docs` | Documentation and spec compliance reviewer, triggered in Phase 5 **in parallel with verification** when docs, specs, READMEs, or public interfaces change. |

The orchestrator spawns fresh generic isolated children for each new role while reusing existing children via continuations across addressing (`implement-code` Continuation Mode), Round 2 delta reviews, clarifications, and Phase-5 re-checks; Phase 6 `merge-pr` runs completely inline without spawning a subagent. Delegation uses progressive disclosure through `references/adapter-*.md` files (Claude Code, Codex, Antigravity `agy`, Pi, generic), explicitly pinning balanced models (`sonnet` in Claude Code, `medium` reasoning effort in Codex, `flash` in Antigravity). Effort is scaled by **risk and complexity** (`Low` / `Moderate` / `High`) rather than LOC line counts, with explicit instructions across every role to stay focused on the task at hand and not overthink things (`Low`: 1 round max; `Moderate`/`High`: 2 rounds max, with Round 2 running only when Round 1 accepted at least one `Action Required` defect).

The lifecycle runs with zero sidecar scratch or temp files: the PR description (including `Part of #N` slice boundaries), consolidated review comments, and inline delegation prompts serve as the sole source of truth across parallel sessions, while reviewers stay strictly read-only without running duplicate test suites. `implement-code` and `implement-address` own making automated tests, linters, and builds pass before Phase 5; Phase 5 skips `verify` when no live or observable surface changed (such as docs-only or pure internal refactors), or delegates real-world `verify` **in parallel with `review-docs`** when a runnable/visual/data surface changed, posting concise `### Verdict:` + `Verified-Head:` lines outside `<details>`. Phase 6 runs `merge-pr` inline following the target project's rules.

Enforced target-repository constraints bind policy over bundled fallbacks. Optional OpenAI `agents/openai.yaml` metadata supplies Codex presentation and invocation policy (no custom Pi agent templates). Skill instructions are bounded to `34 KB` total across all 7 skills (`11.5 KB` for `implement`) enforced by `validate-all.sh`; rare-path guidance lives in skill-local `references/` files. Reviewers return findings cleanly (`Action Required`, `Recommended`, `Minor`, `Summary`) and post nothing themselves; the orchestrator publishes one consolidated comment per code-review round with referee reasoning collapsed under `<details>`. PR descriptions, review comments, verification evidence, and run ledgers keep only actionable summaries visible and collapse detail under `<details>`. Verification flags claimed changes absent from the diff so the orchestrator corrects them before merge.

Codex CLI 0.145.0 note: full lifecycle delegation works in a standard Codex session; headless `codex exec --ephemeral` sessions fail to initialize spawned subagents.

### issue-management

Provides 3 skills for GitHub issue quality:

| Skill | Description |
|-------|-------------|
| `/draft-issue` | Create well-structured GitHub issues with testable acceptance criteria, optimized for `/implement` consumption. |
| `/cleanup-issue` | Fix formatting, fill missing sections, and clarify ambiguity in existing issues. |
| `/refine-issue` | Deepen an issue with codebase research — sharpen acceptance criteria, add implementation hints, decompose into sub-tasks. |

## License

MIT
