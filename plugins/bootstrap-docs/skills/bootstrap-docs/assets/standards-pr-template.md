# PR Standards

**Status:** Draft
**Last Updated:** {DATE}

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

Every PR description must include:

1. **Summary** — 1-3 sentences explaining what the change does and why
2. **Test evidence** — How the change was verified (test output, manual steps, or "covered by existing tests")

Include when relevant:

3. **Review focus** — Specific areas where reviewer attention is most valuable
4. **Context** — Links to related issues, PRs, specs, or ADRs

### Template

```markdown
## Summary
{What this PR does and why.}

{Closes #N — if this PR fully completes the issue}
{Part of #N — if this PR is one of several addressing the issue}

## Test evidence
{How the change was verified.}

## Review focus
{Where reviewer attention is most valuable.}
```

### Issue Linking

Use the correct keyword based on whether this PR **fully completes** the issue or is **one of several** PRs addressing it:

| Keyword | When to use |
|---------|-------------|
| `Closes #N` / `Fixes #N` | This single PR **fully completes** the issue. GitHub will auto-close the issue on merge. |
| `Part of #N` | This PR is **one of several** addressing the issue. The issue stays open for remaining work. |

**Default to `Part of #N`** when in doubt — prematurely closing a tracking issue loses visibility into remaining work. Only use `Closes` when you are certain no further PRs are needed.

### Other References

- Reference related PRs with `Depends on #N` or `See also #N`
- Link to specs or ADRs when the PR implements a design document

## PR Sizing

Small, focused PRs. Each PR should represent one logical change.

**Guidelines:**
- Target: under 400 lines of meaningful diff (excluding generated code, test fixtures, lock files)
- If a PR exceeds 600 lines, it almost certainly should be split
- A PR that touches more than 5 files across unrelated concerns should be split

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
- Single PR if the change is cohesive and under the size guidelines
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

## Related Documents

### Standards
- [Code Conventions](code-conventions.md) — Coding standards enforced in review
- [Testing Standards](testing-standards.md) — Test requirements for PR acceptance

### Operational
- {Link to development setup guide}
