# Bootstraps

A cross-compatible Claude Code, OpenAI Codex, OpenCode (v2), Antigravity (agy), and Pi collection of reusable skills and project scaffolds.

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

## Install in OpenCode (v2)

All three plugins ship native dependency-free OpenCode v2 Server plugin entrypoints (`package.json` + `opencode.js`). Install them globally in OpenCode v2 (`v2.2+`) with Git subdirectory specs:

```sh
opencode plugin add "github:benjamcalvin/bootstraps#main::path:plugins/bootstrap-docs"
opencode plugin add "github:benjamcalvin/bootstraps#main::path:plugins/implement-lifecycle"
opencode plugin add "github:benjamcalvin/bootstraps#main::path:plugins/issue-management"
```

For SSH key auth without HTTPS GitHub credentials, use `git+ssh://`:

```sh
opencode plugin add "git+ssh://git@github.com/benjamcalvin/bootstraps.git#main::path:plugins/implement-lifecycle"
```

Or load from a local checkout directly in `~/.config/opencode/opencode.jsonc` (or a project's `opencode.jsonc`):

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [
    "/path/to/bootstraps/plugins/bootstrap-docs",
    "/path/to/bootstraps/plugins/implement-lifecycle",
    "/path/to/bootstraps/plugins/issue-management"
  ]
}
```

### Pinning a balanced model in OpenCode (v2)

`implement-lifecycle` runs code reviewers, addresser workers, and real-world verifiers on a `balanced` model tier. In `~/.config/opencode/opencode.jsonc`, either configure a dedicated `lifecycle-balanced` subagent (recommended when keeping `general` unchanged) or pass `options.balancedModel` to apply a balanced default to built-in `general` when it has no explicit model:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [
    {
      "package": "github:benjamcalvin/bootstraps#main::path:plugins/implement-lifecycle",
      "options": {
        "balancedModel": "anthropic/claude-sonnet-4-6"
      }
    }
  ],
  "agents": {
    "lifecycle-balanced": {
      "mode": "subagent",
      "model": "anthropic/claude-sonnet-4-6",
      "description": "Balanced-tier worker for implement-lifecycle review, addressing, and verification"
    }
  }
}
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

### OpenCode (v2)

Each OpenCode v2 plugin registers its public skills (selectable via the `skill` tool or `/command` completion) and slash commands:

```
/bootstrap-docs
/implement #42
/merge-pr 42
/draft-issue add user avatar support
/cleanup-issue #42
/refine-issue #42
```

Internal lifecycle worker skills (`implement-code`, `implement-address`, `review-general`, `review-docs`, `verify`) set `opencode/autoinvoke: false` so they stay out of top-level auto-discovery while spawned subagents load them explicitly by ID via `skill`.

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

| Plugin | Claude Code | Codex | OpenCode v2 | Antigravity | Pi | Description |
|--------|-------------|-------|-------------|-------------|----|-------------|
| **bootstrap-docs** | Yes | Yes | Yes | Yes | No | Set up a comprehensive, AI-readable documentation strategy in any project. Creates AGENTS.md, specs, ADRs, guides, plans, standards, and research templates. |
| **implement-lifecycle** | Yes | Yes | Yes | Yes | Yes | Streamlined implementation lifecycle scaled by risk and complexity — plan, implement, PR, bounded general review, parallel verify + docs review, and inline rule-guided merge. Pi delegation requires `pi-subagents`. |
| **issue-management** | Yes | Yes | Yes | Yes | No | Draft, clean up, and refine GitHub issues — optimized for AI agent consumption. |

### implement-lifecycle

Provides a shared lifecycle orchestrator, a rule-guided merge skill, two coding/addressing workers, a unified general reviewer, a docs reviewer, and an end-to-end verification worker across Claude Code, Codex, OpenCode (v2), Antigravity (agy), Pi, and other compatible harnesses:

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
| `review-docs` | Reviews docs and specs in parallel with verification when needed. For Low changes confined to docs, skill wording or tests, the general reviewer also covers docs unless the project requires an independent docs reviewer. |

The orchestrator spawns fresh generic isolated children for each new role while reusing existing children via continuations across addressing (`implement-code` Continuation Mode), Round 2 delta reviews, clarifications, and Phase-5 re-checks; Phase 6 `merge-pr` runs completely inline without spawning a subagent. Delegation uses progressive disclosure through `references/adapter-*.md` files (Claude Code, Codex, OpenCode v2, Antigravity `agy`, Pi, generic), explicitly pinning balanced models (`sonnet` in Claude Code, `medium` reasoning effort in Codex, `lifecycle-balanced` / `balancedModel` in OpenCode v2, `flash` in Antigravity). Effort is scaled by **risk and complexity** (`Low` / `Moderate` / `High`) rather than LOC line counts, with explicit instructions across every role to stay focused on the task at hand and not overthink things (`Low`: 1 round max; `Moderate`/`High`: 2 rounds max, with Round 2 running only when Round 1 accepted at least one `Action Required` defect).

The PR and delegation prompts carry the run state. Writers run affected automated checks in the owning repository. The candidate merge commit gets each required check once in its required environment. Corrections use focused checks and isolated failure diagnosis. The first runnable integration slice exercises a real user interaction. Phase 5 skips live verification when the change has no live surface. Otherwise the verifier reports its verdict and tested commit. Phase 6 runs `merge-pr` inline under the project's rules. The ledger reports elapsed time from observed milestones and identifies external waits.

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
