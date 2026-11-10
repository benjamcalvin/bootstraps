# PR Standards

**Status:** Draft

## Overview

Standards for pull requests in {PROJECT_NAME}. PRs are the primary unit of collaboration. These conventions keep PRs reviewable, traceable, and easy to navigate.

## Branch Naming

Format: `<type>/<short-description>`

| Type | Use |
|------|-----|
| `feat/` | New functionality |
| `fix/` | Bug fixes |
| `refactor/` | Restructuring without behavior change |
| `perf/` | Performance optimizations |
| `docs/` | Documentation only |
| `test/` | Test additions or fixes |
| `chore/` | Build, CI, tooling, dependency updates |

**Rules:**
- Lowercase, hyphen-separated: `feat/user-auth`, `fix/query-timeout`
- Short but descriptive — a reader should understand the intent without opening the PR
- No issue numbers in branch names (reference issues in the PR description instead)

## PR Titles

Format: `<type>: <imperative summary>`

The type prefix matches the branch type. The summary uses imperative mood ("Add", "Fix", "Refactor"), not past tense.

```
feat: Add user authentication flow
fix: Prevent timeout on large query results
docs: Add PR standards
refactor: Extract shared validation into core module
test: Add benchmark for search queries
chore: Upgrade database driver to v5
```

**Rules:**
- Under 72 characters
- No period at the end
- Specific enough to understand without reading the description

## PR Description

A description shows only what the reviewer must see. The lead, the "Author ran" line, and the review focus stay visible; everything else the author or agent wrote collapses under a `<details>` block.

### Template

```markdown
{2–3 sentences: what changes and why, in plain language}

{Closes #N | Part of #N} · Author ran: {commands and results}

**Review focus:** {the decisions a reviewer should weigh}

<details>
<summary>{model name, or author} · design, implementation, test evidence</summary>

## Design
...
</details>
```

**Rules:**
- The lead is plain language with no code identifiers. A lead drafted by an unattended agent ends with `*(agent-drafted lead)*` until a human edits it.
- "Author ran" states only what the author executed. CI and verification results arrive later as checks and comments.
- A blank line follows `</summary>`; GitHub only renders Markdown inside `<details>` after one.
- No living sections ("Progress log", "Live status").
- A comment that another tool parses keeps its parsed lines outside any `<details>` block.
- Agent-written review summaries, run ledgers, and long issues follow the same shape: what the reader must act on stays visible, and supporting detail collapses.
- Link related issues, PRs, specs, or ADRs where they apply.

### Issue Linking

Use the correct keyword based on whether this PR **fully completes** the issue or is **one of several** PRs addressing it:

| Keyword | When to use |
|---------|-------------|
| `Closes #N` / `Fixes #N` | This single PR **fully completes** the issue. GitHub will auto-close the issue on merge. |
| `Part of #N` | This PR is **one of several** addressing the issue. The issue stays open for remaining work. |

**Default to `Part of #N`** when in doubt — prematurely closing a tracking issue loses visibility into remaining work. Only use `Closes` when you are certain no further PRs are needed. Omit the reference when there is no issue.

### Other References

- Reference related PRs with `Depends on #N` or `See also #N`
- Link to specs or ADRs when the PR implements a design document

## PR Scope

**A PR is one logical change that a reviewer can hold in their head in one sitting.**

Line count is a symptom, not the standard. A single ADR, a new module's scaffold, and a mechanical rename are each one logical change however many lines they span; a 200-line PR that fixes a bug *and* refactors an unrelated module is two changes and should be split.

**Signals a PR should be split:**
- The summary needs an "and" to describe what it does
- A reviewer must context-switch between unrelated concerns to evaluate it
- It mixes a refactor with a behavior change — the behavior change becomes invisible inside the noise
- Understanding the later files requires re-reading the earlier ones

**Housekeeping exception:** a batch of small, independent, low-risk changes of the same kind — dependency bumps, typo fixes, a lint sweep — may ship as one PR even though they are not one logical change. Reviewing them together is cheaper than reviewing them apart, and they share a single verdict. Keep the batch to one kind of change, and say so in the title (`chore: bump test dependencies`).

**Splitting strategies:**
- Refactor first, then build on top (separate PRs)
- Interface/contract in one PR, implementation in the next
- Tests for existing behavior in one PR, behavior change + updated tests in the next

## Stacking

When a feature requires multiple sequential PRs, stack them:

1. Each PR in the stack targets the previous PR's branch (not the main branch)
2. Title includes the stack position: `feat: Add user store (1/3)`
3. First PR description includes the full stack outline
4. Merge from the bottom up — once the base PR merges, retarget the next PR

**When to stack vs. single PR:**
- Single PR if the change is cohesive by the scope test above
- Stack if the feature has natural layers (schema → data layer → API) or if reviewing everything at once would be unwieldy

## Commits Within a PR

Each commit should be a coherent, self-contained step. Reviewers read commit-by-commit for larger PRs.

**Rules:**
- Commit messages follow the same `<type>: <summary>` format as PR titles
- Each commit should compile and pass tests (no "WIP" or broken intermediate states)
- Separate refactoring commits from behavior-change commits
- Squash fixup commits before requesting review

## Draft PRs

Use draft PRs for:
- Work-in-progress that needs early feedback on approach
- PRs blocked on another PR in a stack
- Spikes or experiments not ready for merge

Convert to ready-for-review when the PR meets all standards above.

---
