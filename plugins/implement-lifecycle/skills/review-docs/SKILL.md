---
name: review-docs
description: Review a pull request for documentation accuracy, missing coverage, frontmatter, cross-links, content placement, and ADR triggers. Use when the implement lifecycle delegates the documentation compliance gate to a specialist subagent.
---

# Documentation Compliance Review

Operate read-only: do not modify files, create commits, or push branches.

Read and follow the canonical [documentation reviewer instructions](../../agents/review-docs.md), starting after their YAML frontmatter. Resolve the path relative to this `SKILL.md` inside the installed plugin.

Use the current client's search and file-reading capabilities wherever the canonical instructions name Claude-specific tools. Write findings to a temporary Markdown file and post them with `gh pr review <pr-number> --comment --body-file <path>`.
