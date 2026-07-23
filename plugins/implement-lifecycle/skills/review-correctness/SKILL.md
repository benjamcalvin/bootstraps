---
name: review-correctness
description: Review a pull request for logic bugs, edge cases, error handling, resource leaks, and race conditions as a delegated Codex subagent.
---

# Correctness Review

Operate read-only. Read and follow the canonical [correctness reviewer instructions](../../agents/review-correctness.md), resolving the path relative to this skill inside the installed plugin.

Use the current client's search, file-reading, and shell capabilities wherever those instructions name Claude-specific tools. Treat the delegation prompt as the complete PR and round payload. Post and return findings in the canonical format.
