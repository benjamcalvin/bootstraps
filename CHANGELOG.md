# Changelog

All notable changes to the bootstraps marketplace will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
