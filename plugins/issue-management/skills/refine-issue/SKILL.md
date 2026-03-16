---
name: refine-issue
description: >-
  Deepen an existing GitHub issue with codebase research — sharpen acceptance criteria,
  add implementation hints, and decompose into sub-tasks if needed.
  Triggers: /refine-issue, refine issue, sharpen issue
argument-hint: <#issue-number>
license: MIT
metadata:
  version: "1.0.0"
  tags: ["issue", "refine", "planning", "research"]
  author: benjamcalvin
---

# Refine Issue

Refine GitHub issue: $ARGUMENTS

## Context

- Issue: !`gh issue view $0 --json number,title,body,labels,state,comments --jq '{number, title, body, labels: [.labels[].name], state, comment_count: (.comments | length)}'`
- Issue comments: !`gh issue view $0 --comments 2>/dev/null || echo "NO_COMMENTS"`
- Current branch: !`git branch --show-current`

## Instructions

You refine existing GitHub issues by grounding them in codebase reality. Unlike `/cleanup-issue` (which fixes form), you improve **substance** — adding technical context, sharpening acceptance criteria with real code references, and decomposing large tasks.

The goal: after refinement, an AI agent can implement the issue without any codebase exploration of its own.

### Step 1: Parse the Target

Extract the issue number from `$ARGUMENTS`. If no valid issue number is found, use `AskUserQuestion` to ask for one.

### Step 2: Understand the Issue

Read the issue body and comments from Context above. Identify:

- **Type:** bug, feature, chore, refactor, docs, test
- **Claimed scope:** What does the issue say needs to change?
- **Gaps:** What would an implementer need to know that isn't stated?

### Step 3: Research the Codebase

This is the core value of refinement. Explore the codebase to fill knowledge gaps.

1. **Locate affected code.** Use Glob/Grep/Read to find the modules, files, and functions the issue touches. Record exact paths and line numbers.

2. **Find existing patterns.** Search for analogous implementations. If the issue asks for "add pagination to the users endpoint," find another endpoint that already has pagination and note the pattern.

3. **Map the blast radius.** What other code depends on the files being changed? What tests exercise them? Run:
   - Grep for imports/references to affected modules
   - Identify test files that cover the affected code

4. **Check related work.** Search for related issues and PRs:
   ```
   gh issue list --state all --search "<relevant keywords>" --limit 10
   gh pr list --state all --search "<relevant keywords>" --limit 10
   ```
   Note anything relevant (prior attempts, related features, known constraints).

5. **Read referenced specs.** If the task touches a domain with documentation in the repo, read it.

### Step 4: Refine the Issue

Apply refinements based on your research:

#### 4a: Sharpen Acceptance Criteria

Replace vague criteria with specific, testable ones grounded in actual code:

- Before: "Pagination should work"
- After: "When `GET /api/users?page=2&limit=10` is called, the response includes `pagination.total_count`, `pagination.page`, and `pagination.per_page` fields, matching the pattern in `handlers/products.go:47-62`"

Each criterion should be independently verifiable and reference concrete types, functions, or paths where relevant.

#### 4b: Add Technical Context

Add or enhance the Technical Context section:

```markdown
## Technical Context

- **Key files:**
  - `path/to/main/file.go:L10-L45` — primary function to modify
  - `path/to/test_file.go` — existing test coverage
  - `path/to/related.go:L20` — analogous implementation to follow

- **Patterns to follow:** <describe the existing pattern with file references>

- **Dependencies:** <modules that import/use the affected code>

- **Constraints:** <discovered limitations — e.g., "this module has no external deps, keep it that way">
```

#### 4c: Decompose if Needed

If the issue requires >400 lines of changes or touches multiple independent modules, add a "Proposed PRs" section:

```markdown
## Proposed PRs

### PR 1: <imperative title>
**What:** <1-2 sentences>
**Files:**
| File | Change |
|------|--------|
| `path/to/file` | <what changes and why> |

**Acceptance criteria:**
- [ ] <criteria specific to this PR>

---

### PR 2: <imperative title>
**Depends on:** PR 1
<same structure>

### Dependency Order
<which PRs can be parallelized, which must be sequential>
```

#### 4d: Add Verification Hints

If not already present, add or enhance the Verification section:

```markdown
## Verification

- **Automated tests:** <which criteria map to tests, what test patterns to use>
- **Existing test suite:** <specific test commands or files that must continue to pass>
- **Manual checks:** <only if truly needed>
```

### Step 5: Validate

Before presenting, verify:

1. Every acceptance criterion references real code paths or APIs
2. Technical context has exact file paths (not guesses)
3. Patterns to follow are actual patterns in the codebase
4. Decomposition (if any) has clear dependency ordering
5. No new requirements were invented — only existing intent was sharpened

### Step 6: Present and Apply

Show the user the refined issue with a summary of what changed. Use `AskUserQuestion` with options:
- **Apply** — update the issue
- **Edit** — let the user request changes
- **Cancel** — discard

Update the issue:

```bash
gh issue edit <number> --body "$(cat <<'EOF'
<refined body>
EOF
)"
```

If the issue was decomposed into sub-issues, offer to create them:

```bash
gh issue create --title "<type>: <imperative summary>" --body "$(cat <<'EOF'
<sub-issue body>

Parent issue: #<parent-number>
EOF
)"
```

Report what was refined (e.g., "Sharpened 4 acceptance criteria with code references, added Technical Context section, decomposed into 2 PRs").
