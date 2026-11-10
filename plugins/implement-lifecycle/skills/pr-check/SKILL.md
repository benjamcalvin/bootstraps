---
name: pr-check
description: >-
  Validate a PR against PR standards before requesting review.
  Checks branch naming, title, description, commits, references, and scope.
  Triggers: /pr-check, check this PR, validate PR
license: MIT
metadata:
  version: "2.1.0"
  tags: ["pr", "check", "standards", "validation"]
  author: benjamcalvin
---

# PR Standards Check

<!-- lifecycle-suite-capability: focused-only -->

**Suite capability: `focused-only`. Run focused tests, lint, builds, and acceptance commands only. Do not execute or consume the target repository's authoritative verification command or ordered command plan. Final verification owns that evidence.**

Pre-flight validation for PRs.

```text
$ARGUMENTS
```

If the client leaves `$ARGUMENTS` literal, use the invoking prompt. Without a PR number, inspect the current branch's PR when available; if no PR exists, check only what can be validated locally and say so.

## Instructions

Inspect the branch, PR metadata, and comments; determine the actual base branch before inspecting commits and diff size. Read explicit user direction and the target repository's governing instructions and contribution docs first: they take precedence over the bundled checks below for branch names, commits, PR formatting, required references, and blocking/advisory status. Use a bundled check only where target policy is silent, and label it as a fallback. A fallback check never blocks.

Result per check:
- **PASS** — meets the standard
- **WARN** — minor deviation, or any bundled-fallback miss
- **FAIL** — violates a repository-declared blocking rule; say what must change

A repository-declared rule carries its declared status; otherwise a miss is WARN.

### Checks (bundled fallbacks)

1. **Branch naming** — `<type>/<short-description>`, type one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`; lowercase, hyphen-separated.
2. **PR title** — `<type>: <imperative summary>`, type matching the branch, under 72 characters, no trailing period, imperative mood ("Add", not "Added").
3. **Lead** — the description opens with 2–3 plain-language sentences on what changes and why, before any mechanism and with no code identifiers; an unattended agent's lead ends with `*(agent-drafted lead)*`. Opening with implementation bullets is a miss.
4. **Shape** — an `Author ran:` line naming only commands the author executed (claimed CI or verification results are a miss), then `**Review focus:**`, then the rest under `<details><summary>…</summary>` with a blank line after `</summary>`. No living sections ("Progress log", "Live status").
5. **Commit messages** — `<type>: <summary>`; no "WIP", "fixup", or "wip" commits.
6. **References** — a related issue is referenced with `Closes #N` / `Fixes #N` only when this PR fully completes it, else `Part of #N`. WARN when no reference exists, or when `Closes #N` is used for what looks like a sub-task (the issue has criteria this PR does not address).
7. **Altitude layering** — the lead has **no** file paths, function names, or line numbers; collapsed design reasoning is in component terms, with code identifiers only from Implementation Notes down; no sentence carries a claim, its mechanism, and a citation at once, and citations end their bullet; no review chronology ("round 1 added..."). Isolated slips are minor; a lead saturated with identifiers is a severe miss.

### Scope Note (advisory — not scored)

Judge whether the PR is **one logical change a reviewer can hold in their head in one sitting**, or a small batch of same-kind housekeeping. This is cohesion, not size: one ADR, a module scaffold, or a mechanical rename is one change at any size; a small PR that fixes a bug *and* refactors an unrelated module is two. Give a one-line observation: cohesive, or the seam to split along. When the PR is over-scoped, recommend splitting the out-of-scope work into child issues before implementation proceeds; splitting early is far cheaper than mid-lifecycle. Never score it, count lines against a threshold, or treat it as a blocker.

### Output Format

```
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
