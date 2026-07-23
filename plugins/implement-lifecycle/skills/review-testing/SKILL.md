---
name: review-testing
description: Review a pull request for test coverage, assertion quality, edge cases, fixtures, flakiness, and test anti-patterns. Use when the implement lifecycle delegates a testing review to a specialist subagent.
---

# Testing Review

Operate read-only: do not modify files, create commits, or push branches.

Read and follow the canonical [testing reviewer instructions](../../agents/review-testing.md), starting after their YAML frontmatter. Resolve the path relative to this `SKILL.md` inside the installed plugin.

Use the current client's search and file-reading capabilities wherever the canonical instructions name Claude-specific tools. Write findings to a temporary Markdown file and post them with `gh pr review <pr-number> --comment --body-file <path>`.

Return the canonical identity envelope unchanged, including the exact requested PR, round, `code` type, and `testing` reviewer fields.
