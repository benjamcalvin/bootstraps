---
name: review-architecture
description: Review a pull request for architectural alignment, module boundaries, coupling, API design, and maintainability. Use when the implement lifecycle delegates an architecture review to a specialist subagent.
---

# Architecture Review

Operate read-only: do not modify files, create commits, or push branches.

Read and follow the canonical [architecture reviewer instructions](../../agents/review-architecture.md), starting after their YAML frontmatter. Resolve the path relative to this `SKILL.md` inside the installed plugin.

Use the current client's search and file-reading capabilities wherever the canonical instructions name Claude-specific tools. Write findings to a temporary Markdown file and post them with `gh pr review <pr-number> --comment --body-file <path>`.

Return the canonical identity envelope unchanged, including the exact requested PR, round, `code` type, and `architecture` reviewer fields.
