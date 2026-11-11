# Changelog

All notable changes to the bootstraps marketplace will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Subagent continuation support in `implement-lifecycle` 3.24.0 across Claude Code (`resume`), Codex (`send_input`), Antigravity (`send_message`), Pi (session resume), and generic adapters; reuses existing author, reviewer, and verifier subagents for follow-ups, feedback addressing, delta reviews, referee clarifications, and re-verification while spawning fresh isolated children for new tasks, distinct roles, and convergence resets
- Progressive-disclosure references in `implement-lifecycle` 3.23.0 (`large-tier.md`, `verify-fail-loop.md`, `baseline-on-failure.md`, `special-verdicts.md`, `ci-source.md`, `issue-updates.md`)
- Native Antigravity (`agy`) support: `.agents/plugins.json` workspace manifest for native discovery, `.antigravity-plugin/plugin.json` manifests across all plugins, and `references/adapter-agy.md` adapter for Antigravity subagent invocation
- Progressive-disclosure harness adapters in `implement-lifecycle` 3.22.0 (`references/adapter-*.md` for Claude Code, Codex, Antigravity, Pi, and generic harnesses)
- Single-plugin filtering in `validate-all.sh` (`./validate-all.sh <name>`)
- Codex manifest and marketplace validation in `validate-all.sh`
- Pi package metadata and installation guidance for `implement-lifecycle`; Pi users can discover its shared skills and delegate through their separately installed `pi-subagents`

### Changed

- `implement-lifecycle` 3.24.0 updates orchestrator delegation and adapter references to continue existing subagents on compatible harnesses rather than spawning fresh children for every follow-up, adjusts `implement-address` to run as a continuation or fresh subagent, records continuations in the run ledger, and ensures convergence resets discard prior sessions
- `implement-lifecycle` 3.23.0 tightens instructions into lower byte budgets (56 KB total across all 12 skills, 14 KB for `implement`), adopts outcome-based test requirements covering new/changed behavior, introduces direct file-backed verification artifact handoffs (`record=<path>`), makes `<verification-record-path>` optional on `/merge-pr` (validating from comments when standalone or file when provided), adds first-class `Ready for Human Merge` reporting, and streamlines reviewer methodology and referee postures across skills
- `implement-lifecycle` 3.22.0 discounts whole-file deletions in authoritative tier classification, runs `review-docs` only on docs-only follow-up deltas, executes Phase 6 `merge-pr` inline without spawning a child, and introduces a file-backed scratch context bundle (`bundle=<path>`) across post-PR workers to eliminate redundant metadata fetching
- `bootstrap-docs` 2.2.0 adds Antigravity plugin manifest metadata
- `issue-management` 1.4.0 adds Antigravity plugin manifest metadata
- **Breaking:** `bootstrap-docs` 2.0.0 shrinks instruction files. The generated strategy doc stays under 200 lines and carries the instruction-file rules (under 200 lines, only what an agent cannot infer, budgets only fall, no per-folder index files, every `CLAUDE.md` imports `@AGENTS.md`, code referred to by symbol). Docs subfolders no longer get an `AGENTS.md`/`CLAUDE.md` pair or a Contents list; each module is a short section of the strategy doc instead. Root integration adds `@AGENTS.md` to every `CLAUDE.md` that lacks it. The per-document-type maximum line table stays as ceilings, not goals; only instruction file budgets are enforced, and budgets only ever decrease. **To migrate** a project set up with 1.x, run `/bootstrap-docs migrate`: it lists each old-style item (per-folder index pairs, Contents lists, Last Updated, Related Documents, length targets, a `CLAUDE.md` without `@AGENTS.md`, an outdated or over-length strategy doc) with its proposed change, applies only the items you confirm, and never deletes a file without explicit confirmation
- `bootstrap-docs` 1.9.0 slims the document templates: "Last Updated", the required two-way "Related Documents" section, line-number code references and the "Target Lines" table are gone (maximums remain), and the ADR module is opt-in, defaults to declined, and uses a one-page template with a when-to-write trigger (the agent drafts, a human accepts)
- `bootstrap-docs` 1.8.0 redefines specs as the shared conceptual model: both spec templates open with a Glossary and carry Invariants, Rationale, and a `Covers:` field, the product spec is the model as users see it and the technical spec the model as builders see it, and "schema, indexes" is gone from the spec definitions
- `implement-lifecycle` 3.20.0 has `review-docs` report spec glossary terms that no longer appear in the covered code, and drops its separate two-way link check
- Documented the repository's Claude Code/Codex compatibility matrix and installation flows
- `implement-lifecycle` 3.9.2 now delegates every heavy phase through generic isolated subagents that explicitly invoke the canonical worker skills, removing the distributed Claude Code worker templates
- `implement-lifecycle` 3.10.0 defines its phase-to-skill mapping once and applies it through Claude Code, Codex, Pi, and generic isolated-delegation adapters
- `implement-lifecycle` 3.11.0 pins a model tier (`balanced`/`frontier`) per lifecycle role; the Claude Code adapter passes the Agent `model` explicitly instead of inheriting
- `implement-lifecycle` 3.12.0 makes bundled `pr-check` fallbacks advisory (WARN) unless repository policy declares the rule, and `merge-pr` evaluates the checklist inline instead of spawning a child
- `implement-lifecycle` 3.13.0 classifies PRs as small/medium/large, caps Phase 4 review rounds per tier, limits follow-up rounds to the fix delta, exits on Minor-only findings, and selects specialists by tier and path triggers
- `implement-lifecycle` 3.14.0 removes the standalone Phase 4.5 docs gate; `review-docs` now runs as a triggered round-1 reviewer through the same referee and fix pass
- `implement-lifecycle` 3.15.0 scales verification by tier, accepts exact-head required-CI evidence (`suite-source: ci`), baselines suite failures on the merge-base so pre-existing-only failures return PARTIAL (the run stops for a human; not mergeable) instead of FAIL, re-verifies only failed scenarios, and caps verification at 2 fix cycles
- `implement-lifecycle` 3.16.0 prints a per-run ledger (tier, children by role and model tier, rounds, fix commits, wall-clock per phase, follow-up items) on every completed or escalated run
- `implement-lifecycle` 3.17.0 trims its skill instructions from ~125 KB to under an 80 KB byte budget (`implement` under 20 KB), moves rare-path material (reviewer-result recovery, convergence recovery, CI-evidence acceptance) into skill-local `references/`, and enforces the budget and reference existence in `validate-all.sh`
- `bootstrap-docs` 1.6.0 replaces the "document every exported symbol" code-standard rule with a comment ban and short allow-list (external constraints, untestable guarantees, `TODO(#N)`, tool directives, tool-output comments), and the testing template names tests after the guarantee they pin
- `implement-lifecycle` 3.18.0 has `implement-code` and `implement-address` add no comments outside the allow-list (with an added-line comment scan in focused verification and a commit body when the reason is not evident), and `review-general` flags added comments as non-blocking findings unless the target repository declares the policy; the PR-description altitude rules move to `implement-code/references/`
- `bootstrap-docs` 1.7.0 makes the PR standards template authoritative for description shape: a 2–3 sentence lead (marked `*(agent-drafted lead)*` until a human edits it), an "Author ran" line stating only what the author executed, a review focus, and everything else collapsed under `<details>`
- `implement-lifecycle` 3.19.0 re-syncs the `implement-code` fallback PR body and the `pr-check` checklist to that shape, collapses referee reasoning in the consolidated review comment and wraps the run ledger in `<details>` (both templates move to `implement/references/`), and has `verify` report PR-description claims absent from the diff, which the orchestrator corrects before merge; verification-record lines stay outside `<details>` so `merge-pr` can parse them
- `bootstrap-docs` 2.1.0 ships `docs-check`, a standard-library Python 3.11+ drift checker installed with `/bootstrap-docs docs-check` (also offered after `migrate`). Errors: relative links and backticked paths that do not resolve, npm/make/mise tasks named in docs that do not exist, a `CLAUDE.md` without `@AGENTS.md` or an inexactly named instruction file, an instruction file over its line budget or a raised budget, and comment lines the change adds that cite a tracker, label a step, or record history. Warnings, which never change the exit code: issue numbers or history phrasing in docs (ADRs and changelogs exempt), spec glossary terms missing from the covered code, and heavy churn under a spec's `Covers:` paths. `docs-check.toml` holds the budgets and a baseline of existing errors that only shrinks; external links are checked only with `--network`. A fixture self-test runs in `validate-all.sh`
- `implement-lifecycle` 3.21.0 has `implement-code` run `docs-check` with lint and `review-docs` run it on docs changes when the project has it, paid for by trims in both skills
- `issue-management` 1.3.0 has `draft-issue` and `refine-issue` collapse Technical Context and Proposed PRs under `<details>`, and `cleanup-issue` preserve existing `<details>` blocks
- `implement-lifecycle` 3.21.1 removes the `stop-guard` activation marker from `implement`

### Removed

- Retired and removed `bootstrap-worktrees`, `implement-cli`, `implement-team`, `second-opinion`, and `stop-guard` so the marketplace retains only the actively maintained cross-client plugins

## implement-team [0.5.0] - 2026-07-26

### Deprecated

- `implement-team` is deprecated in favour of `implement-lifecycle` (`/implement`). It remains installable but is unmaintained, receives no fixes, and will be removed in a future release

## implement-cli [1.4.1] - 2026-07-26

### Changed

- Marked work-in-progress and not recommended for general use; `implement-lifecycle` (`/implement`) is the supported lifecycle plugin

## second-opinion [2.2.1] - 2026-07-23

### Fixed

- Removed the hidden external `dirname` startup dependency when running with a restricted `PATH`

## implement-lifecycle [3.4.0] - 2026-07-22

### Added

- Native Codex plugin metadata, marketplace publication, and delegated reviewer skill adapters

### Changed

- Lifecycle delegation now uses explicit Claude Code named subagents or Codex subagents loading plugin-qualified skills
- Worker skills no longer depend on implicit fork metadata and remain reusable across clients

## implement-lifecycle [3.3.2] - 2026-07-22

### Changed

- Adversarial review now requires proportional remedies, a convergence stop after three non-clean rounds dominated by review-introduced complexity, and a five-round default cap unless the user explicitly authorizes more

## bootstrap-docs [1.4.1] - 2026-07-22

### Added

- Native Codex plugin metadata for the existing documentation bootstrap skill

## issue-management [1.1.1] - 2026-07-22

### Added

- Native Codex plugin metadata for the existing issue drafting, cleanup, and refinement skills

## issue-management [1.1.0] - 2026-07-19

### Changed

- `draft-issue`: new "Writing at the Right Altitude" guidance — issues descend through behavior/design/implementation layers, with locational detail confined to Technical Context and PR decomposition tables (Acceptance Criteria may name the contract under test); template sections annotated with their altitude; optional History section for provenance; validation checklist gains altitude, skim-test, and sentence-discipline checks
- `refine-issue`: refinement adds depth at the right layer instead of pushing `file:line` references into Problem/Solution; acceptance-criteria example no longer embeds file references; validation gains altitude and skim-test checks
- `cleanup-issue`: new Altitude quality dimension and "Altitude Fixes" step (3d) that moves misplaced code identifiers, split-worthy sentences, mid-clause citations, and discovery narrative to their proper homes

## implement-lifecycle [3.3.0] - 2026-07-19

### Changed

- `implement-code`: PR body template restructured into descending altitude layers — plain-language TL;DR (no code identifiers) → Design → Implementation Notes → Test evidence → Review focus — with inline altitude, citation, and skim-test rules
- `pr-check`: check 3 now fails descriptions that open with implementation bullets instead of a plain-language TL;DR; new check 8 validates altitude layering (rubric is now 8 checks)

## second-opinion [1.0.1] - 2026-07-18

### Added

- ADR-001 (`docs/adr/001-task-delegation-privilege-model.md`): task-delegation substrate choice, `consult`/`act-sandboxed`/`act-full` privilege tiers, three-boundary enforcement model, pinned `sandbox-runtime` wrapper, fail-closed posture, allowlist ownership, and risk register (issue #77)
- README security section cross-links ADR-001 and notes the consult-to-delegate roadmap

## implement-cli [1.1.4] - 2026-03-15

### Added

- `--version` global flag that reads version from `plugin.json` at runtime
- Validation for `--max-cost` (must be positive and finite) and `--max-depth` (must be >= 1)
- Unit tests for version flag, argument validation, NaN/inf edge cases, and fallback paths

## implement-cli [1.1.2] - 2026-03-15

### Fixed

- SKILL.md path resolution: replaced `$(dirname "$0")` (invalid in skill context) with Glob-based discovery
- `validate-all.sh` now works from any directory via `cd "$(dirname "${BASH_SOURCE[0]}")"` guard

## bootstrap-docs [1.2.0] - 2026-03-10

### Added

- Changelog template asset following Keep a Changelog format
- Changelog document type in strategy template taxonomy

## implement-lifecycle [2.1.0] - 2026-02-26

### Added

- Full implementation lifecycle with adversarial PR review
- Plan, implement, PR, review/address loop, merge workflow
- Specialist reviewer agents (correctness, security, architecture, testing)
- Referee evaluation and filtered action plans
- Draft-issue skill for creating well-structured GitHub issues
- PR-check skill for validating PRs against standards
- Merge-pr skill with issue update automation
- Verify skill for end-to-end verification

## bootstrap-worktrees [1.0.0] - 2026-02-24

### Added

- Setup skill for project-agnostic worktree isolation
- Per-worktree port allocation and Docker Compose project templates
- Script templates for worktree lifecycle management

## bootstrap-docs [1.1.0] - 2026-02-22

### Added

- Implementation sequence guidance in Phase 6 summary
- Audit mode for re-run progress tracking

### Changed

- Phase 6 summary now includes ordered workflow as actionable next steps
