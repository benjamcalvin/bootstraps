# Bootstraps

A Claude Code plugin marketplace of reusable skills, hooks, and project scaffolds.

## Prerequisites

This is a private repository. You need access to `benjamcalvin/bootstraps` on GitHub and git credentials configured (e.g. `gh auth login`).

For automatic plugin updates at Claude Code startup, set a GitHub token in your environment:

```sh
export GITHUB_TOKEN=ghp_your_token_here
```

Without this, plugins still work — you just need to update manually with `/plugin marketplace update bootstraps`.

## Install

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

## Install a Plugin

```
/plugin install bootstrap-docs@bootstraps
/plugin install implement-lifecycle@bootstraps
```

Choose a scope when prompted:
- **user** (default) — available in all your projects
- **project** — available to anyone working on the current project
- **local** — only for you in the current project

## Use a Plugin

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
/review-pr 17
/draft-issue add user avatar support
```

## Update Plugins

```
/plugin marketplace update bootstraps
```

## Uninstall a Plugin

```
/plugin uninstall bootstrap-docs@bootstraps
/plugin uninstall implement-lifecycle@bootstraps
```

## Available Plugins

| Plugin | Description |
|--------|-------------|
| **bootstrap-docs** | Set up a comprehensive, AI-readable documentation strategy in any project. Creates AGENTS.md, specs, ADRs, guides, plans, standards, and research templates. |
| **implement-lifecycle** | Full implementation lifecycle with adversarial PR review — plan, implement, PR, review/address loop, merge. |

### implement-lifecycle

Provides 7 skills and 4 reviewer agents for the complete implementation lifecycle:

**Skills:**

| Skill | Description |
|-------|-------------|
| `/implement` | Lean orchestrator — 6-phase lifecycle (plan → implement → PR → review loop → verify → merge). Accepts `#issue`, PR number, or freeform task. Supports trailing instructions like "just review" or "skip planning". |
| `/draft-issue` | Create well-structured GitHub issues with testable acceptance criteria, optimized for `/implement` consumption. |
| `/merge-pr` | Validate, squash-merge, delete branch, and update linked GitHub issues with delivery status. |
| `/pr-check` | Pre-flight PR validation — branch naming, title, description, sizing, commits, references. |

**Subagent skills** (invoked by the orchestrator, not directly):

| Skill | Description |
|-------|-------------|
| `implement-code` | Explore codebase, plan, write tests first, implement, self-review, commit, and create PR. |
| `implement-address` | Address filtered review findings from the referee's action plan. |
| `verify` | End-to-end verification — exercises the real running system, checks downstream effects, regression tests existing flows. |

**Reviewer agents** (invoked in parallel during the review loop):

| Agent | Focus |
|-------|-------|
| `review-correctness` | Logic bugs, edge cases, error handling, race conditions |
| `review-security` | AuthZ, injection risks, PII handling, spec conformance |
| `review-architecture` | Pattern consistency, module boundaries, coupling, forward-looking design |
| `review-testing` | Test coverage, assertion quality, edge cases, test anti-patterns |

## License

MIT
