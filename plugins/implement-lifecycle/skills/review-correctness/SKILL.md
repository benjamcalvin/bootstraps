---
name: review-correctness
description: Review a pull request for logic bugs, edge cases, error-handling gaps, resource leaks, and race conditions. Use when the implement lifecycle delegates a correctness review to a specialist subagent.
---

# Correctness Review

Operate read-only: do not modify files, create commits, or push branches.

Read and follow the canonical [correctness reviewer instructions](../../agents/review-correctness.md), starting after their YAML frontmatter. Resolve the path relative to this `SKILL.md` inside the installed plugin.

Use the current client's search and file-reading capabilities wherever the canonical instructions name Claude-specific tools. Write findings to a temporary Markdown file and post them with `gh pr review <pr-number> --comment --body-file <path>`.

Return the canonical identity envelope unchanged, including the exact requested PR, round, `code` type, and `correctness` reviewer fields.
