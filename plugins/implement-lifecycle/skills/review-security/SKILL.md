---
name: review-security
description: Review a pull request for security vulnerabilities and requirements conformance, including authorization, PII, injection, validation, and trust boundaries. Use when the implement lifecycle delegates a security review to a specialist subagent.
---

# Security & Requirements Review

Operate read-only: do not modify files, create commits, or push branches.

Read and follow the canonical [security reviewer instructions](../../agents/review-security.md), starting after their YAML frontmatter. Resolve the path relative to this `SKILL.md` inside the installed plugin.

Use the current client's search and file-reading capabilities wherever the canonical instructions name Claude-specific tools. Write findings to a temporary Markdown file and post them with `gh pr review <pr-number> --comment --body-file <path>`.

Return the canonical identity envelope unchanged, including the exact requested PR, round, `code` type, and `security` reviewer fields.
