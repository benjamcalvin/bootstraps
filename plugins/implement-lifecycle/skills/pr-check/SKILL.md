---
name: pr-check
description: >-
  Validate a PR against PR standards before requesting review.
  Checks branch naming, title, description, commits, references, and scope.
  Triggers: /pr-check, check this PR, validate PR
license: MIT
metadata:
  version: "2.2.0"
  tags: ["pr", "check", "standards", "validation"]
  author: benjamcalvin
---

# PR Standards Check

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Prefer fast package- or target-scoped checks during iteration (using the repository's default check only when fast and no narrower check exists); `verify` owns authoritative exact-head suite signoff.**

Pre-flight validation for PRs.

```text
$ARGUMENTS
```

If the client leaves `$ARGUMENTS` literal, use the invoking prompt. Without a PR number, inspect the current branch's PR when available; if no PR exists, check only what can be validated locally and say so.

## Instructions

Inspect the branch, PR metadata, and comments; determine the actual base branch before inspecting commits and diff size. Read explicit user direction and the target repository's governing instructions and contribution docs first: they take precedence over the bundled checks below for branch names, commits, PR formatting, required references, and blocking/advisory status. Use a bundled check only where target policy is silent, and label it as a fallback. A fallback check never blocks.

Result per check: **PASS**, **WARN** (minor deviation or bundled-fallback miss), or **FAIL** (violates repository-declared blocking rule). A fallback check never blocks.

### Checks (bundled fallbacks)

1. **Branch naming** — `<type>/<short-description>`, type one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`; lowercase, hyphen-separated.
2. **PR title** — `<type>: <imperative summary>`, type matching the branch, under 72 characters, no trailing period, imperative mood ("Add", not "Added").
3. **Lead** — the description opens with 2–3 plain-language sentences on what changes and why, before any mechanism and with no code identifiers; an unattended agent's lead ends with `*(agent-drafted lead)*`.
4. **Shape** — an `Author ran:` line naming only commands the author executed, then `**Review focus:**`, then the rest under `<details><summary>…</summary>` with a blank line after `</summary>`. No living sections ("Progress log", "Live status").
5. **Commit messages** — `<type>: <summary>`; no "WIP" or "fixup" commits.
6. **References** — a related issue is referenced with `Closes #N` / `Fixes #N` only when this PR fully completes it, else `Part of #N`.
7. **Altitude layering** — the lead has no file paths, function names, or line numbers; collapsed design reasoning is in component terms; code identifiers appear from Implementation Notes down; citations end their bullet.

### Scope Note (advisory — not scored)

Judge whether the PR is **one logical change a reviewer can hold in their head in one sitting**, or small housekeeping. This is cohesion, not size: an ADR, module scaffold, or rename is one change; a PR fixing a bug *and* refactoring unrelated code is two. Give a one-line observation: cohesive, or the seam to split along. Never score it or treat it as a blocker.

### Output Format

```markdown
## PR Standards Check

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 1 | Branch naming | PASS/WARN/FAIL | ... |
| 2 | PR title | PASS/WARN/FAIL | ... |
| 3 | Lead | PASS/WARN/FAIL | ... |
| 4 | Shape | PASS/WARN/FAIL | ... |
| 5 | Commit messages | PASS/WARN/FAIL | ... |
| 6 | References | PASS/WARN/FAIL | ... |
| 7 | Altitude layering | PASS/WARN/FAIL | ... |

**Result: X/7 passing, Y warnings, Z failures** (fallback misses count as warnings, not failures)

**Scope (advisory):** <one line — cohesive, or the seam it should be split along>
```

If there are failures, add a brief "Suggested Fixes" section.
