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
| **implement-lifecycle** | Yes | Yes | Yes | Yes | Full implementation lifecycle with adversarial PR review — plan, implement, PR, review/address loop (docs reviewed in round 1), verify, merge. Pi delegation requires `pi-subagents`. |
| **issue-management** | Yes | Yes | Yes | No | Draft, clean up, and refine GitHub issues — optimized for AI agent consumption. |

### implement-lifecycle

Provides a shared lifecycle orchestrator, two utility skills, three delegated worker roles, a baseline general reviewer, four optional targeted specialists, and a conditional docs reviewer across Claude Code, Codex, Antigravity (agy), Pi, and other compatible harnesses:

**Skills:**

| Skill | Description |
|-------|-------------|
| `/implement` / `$implement-lifecycle:implement` | Lean orchestrator — lifecycle of plan → implement → PR → review loop → verify → merge. Accepts `#issue`, PR number, or freeform task. Supports trailing instructions like "just review" or "skip planning". |
| `/merge-pr <pr-number> [verification-record-path]` / `$implement-lifecycle:merge-pr <pr-number> [verification-record-path]` | Merge a verified PR following repository policy and post issue updates; validates exact-head verification record from comment or optional record path. Evaluated inline by the orchestrator in Phase 6 or executed standalone. |
| `/pr-check` / `$implement-lifecycle:pr-check` | Pre-flight PR validation — branch naming, title, description, commits, references, plus an advisory scope note. |

**Delegated worker roles** (invoked by the orchestrator, not directly):

| Role | Description |
|-------|-------------|
| `implement-code` | Explore codebase, plan, write outcome-based tests covering new/changed behavior, implement, self-review, commit, and create PR. |
| `implement-address` | Address filtered review findings from the referee's action plan. |
| `verify` | End-to-end verification and sole authoritative-suite owner — scales live scenarios by tier, records one execution or exact-head required-CI evidence, baselines suite failures on the merge-base, and writes structured verification artifacts directly to the requested record path. |

**Review roles:**

| Role | Focus |
|-------|-------|
| `review-general` | Baseline holistic reviewer for requirements, project conventions, established patterns, scope, integration, and test adequacy. |
| `review-correctness` | Optional targeted specialist for logic bugs, edge cases, error handling, and race conditions. |
| `review-security` | Optional targeted specialist for AuthZ, injection risks, and PII handling. |
| `review-architecture` | Optional targeted specialist for module boundaries, coupling, and forward-looking design. |
| `review-testing` | Optional targeted specialist for test coverage, assertion quality, edge cases, and test anti-patterns. |
| `review-docs` | Round-1 reviewer, triggered when docs or user-facing interfaces change (or the tier is Large), for missing docs, stale docs, and frontmatter/cross-link correctness. |

The orchestrator spawns fresh generic isolated delegated children for each new task and distinct role, while continuing existing subagents across follow-ups, feedback addressing, delta reviews, clarifications, and re-verification (falling back to fresh spawns on convergence resets or one-shot harnesses); Phase 6 `merge-pr` is evaluated inline without spawning a child. Delegation instructions use progressive disclosure through skill-local `references/adapter-*.md` files (Claude Code, Codex, Antigravity `agy`, Pi, and generic adapters). Authoritative tier classification discounts whole-file deletions in line counts while inspecting all changed paths for risk surfaces. The orchestrator maintains a scratch context-bundle file per PR outside the codebase, refreshed each round, and passes `bundle=<path>` to post-PR children to eliminate redundant `gh pr view` fetches. Follow-up review rounds run `review-docs` only when the prior round accepted only documentation findings and the delta touches documentation files only; empty or structurally incomplete reviewer results are recovered or retried before refereeing.

Every lifecycle skill declares a machine-checkable, command-neutral suite capability. `verify` is the sole `full-suite-owner`; it discovers the target repository's authoritative verification command or ordered command plan from repository instructions, CI, development documentation, and build/test configuration. The orchestrator, implementers, addressers, reviewers, PR checker, and merger are `focused-only` and may run focused checks without executing or consuming that plan. Verification evidence records the exact command or ordered plan once for the exact PR head (or a successful required-CI run attempt whose steps ran that plan on the same head in the target repository, which merge independently re-confirms), and merge uses that verified SHA as an atomic precondition. When every suite failure is also present on the merge-base, verification returns PARTIAL: the run stops for a human, the record is not mergeable, and nothing is sent back for fixes; verification fix cycles are capped at 2.

Enforced target-repository constraints are binding; explicit user direction selects only among permitted choices, and unresolved conflicts stop the merge. Bundled conventions are fallbacks only when both sources are silent about toolchains, branch names, commits, PR formatting, required checks, approvals, merge method, or branch retention. Findings handoffs use harness-provided or system-created temporary paths passed explicitly between workers, and verification writes a structured verification artifact directly to the requested record path for inline or standalone merge.

The skill-local `agents/openai.yaml` files are optional OpenAI skill metadata that supplies presentation and invocation policy. They are not subagent definitions, are retained for Codex compatibility, and do not change the harness-neutral worker behavior. No custom Pi agent templates are distributed.

Skill instructions are held to a byte budget (56 KB across all lifecycle skills, 14 KB for `implement`) enforced by `validate-all.sh`, because every child re-reads them. Material needed only on a named path (Large-tier triggers and convergence audits, verification failure loops, reviewer-result recovery, baseline-on-failure workflow, special-verdict records, CI source validation, linked issue update templates, and the PR-description, review-comment, and run-ledger templates) lives in skill-local `references/` files that the skill reads only on that path.

Reviewers return their findings to the orchestrator and post nothing themselves. The orchestrator is the sole publisher to the PR timeline: it publishes one consolidated comment per round carrying every reviewer's findings plus its referee decisions, with the referee reasoning collapsed under `<details>`.

PR descriptions, review comments, and run ledgers show only what the reader must act on and collapse the rest of the agent's detail under `<details>`. Verification flags any change the PR description claims that the diff does not contain, and the orchestrator corrects the description before merge.

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
