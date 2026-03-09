---
name: draft-issue
description: >-
  Create well-structured GitHub issues optimized for /implement.
  Produces machine-readable issues with testable acceptance criteria.
  Triggers: /draft-issue, create an issue, write an issue
argument-hint: <brief description of what needs to be done>
license: MIT
metadata:
  version: "1.0.0"
  tags: ["issue", "draft", "planning"]
  author: benjamcalvin
---

# Draft Issue

Create a GitHub issue for: $ARGUMENTS

## Context

- Recent issues: !`gh issue list --limit 5 --json number,title --jq '.[] | "#\(.number) \(.title)"'`
- Current branch: !`git branch --show-current`

## Instructions

Good issues are the single biggest lever for `/implement` quality. A well-crafted issue gives `/implement`'s planner, implementer, and reviewers everything they need to succeed autonomously. A vague issue produces vague code.

The downstream consumer of these issues is an AI agent. Every section you write should be optimized for machine comprehension: specific, unambiguous, verifiable, and grounded in concrete code references.

### Step 1: Understand the Request

Parse `$ARGUMENTS` to determine:
- **Type:** Is this a bug, feature, chore, refactor, or docs task?
- **Scope:** What modules/files are likely involved?
- **Size:** Can this be done in a single PR (target: under 400 lines changed)?

If the request is vague, use the `AskUserQuestion` tool to clarify before proceeding. Do not guess at intent — surface ambiguity early.

### Step 2: Research Context

Before drafting, explore the codebase to ground the issue in reality.

1. **Find relevant code.** Use Glob/Grep/Read to locate modules, files, and patterns the implementation must interact with. Record exact file paths.
2. **Identify existing patterns.** Find analogous implementations. Note specific files and line numbers.
3. **Check related work.** Search `gh issue list --state all` and `gh pr list --state all` for related issues/PRs. Link anything relevant.
4. **Read referenced specs.** If the task touches a domain covered by specs in `docs/`, read them.
5. **Understand the blast radius.** Which tests exercise the affected code? What other modules depend on it?

### Step 3: Draft the Issue

#### Template: Standard Issue (Single PR)

Use when the work fits in one PR (~400 lines or fewer).

```markdown
## Problem

<What is broken, missing, or suboptimal? Include concrete examples.
Be specific enough that someone unfamiliar with the codebase understands the gap.>

## Solution

<What should change, at a conceptual level. Describe the target state, not implementation steps.>

## Acceptance Criteria

<Write criteria using structured patterns that map directly to tests:>

- [ ] When <trigger/action>, the system shall <expected behavior>
- [ ] Given <precondition>, when <action>, then <outcome>
- [ ] The <component> shall <behavior> (for invariants)
- [ ] If <error condition>, the system shall <fallback/error behavior>

<Each criterion should be independently verifiable. Include negative criteria where important.>

## Verification

- **Automated tests:** <which criteria map to tests? what patterns?>
- **Manual checks:** <anything requiring human/visual verification — keep minimal>
- **Existing test suite:** <must continue to pass>

## Scope

**In scope:**
- <specific deliverable 1>

**Out of scope:**
- <explicitly excluded item — why>

## Technical Context

- **Key files:** <exact paths to files the implementer must read or modify>
- **Patterns to follow:** <reference existing analogous code>
- **Constraints:** <tech stack requirements, no new dependencies, etc.>

## References

- <Links to relevant specs, ADRs, existing code, or prior issues>
```

#### Template: Large Issue (Multiple PRs)

Use when the work requires multiple PRs (>400 lines, multiple modules).

Add these sections to the standard template:

```markdown
## Proposed PRs

### PR 1: <imperative title>

**What:** <1-2 sentences>

**Files:**
| File | Change |
|------|--------|
| `path/to/file` | <what changes and why> |

**Acceptance criteria:**
- [ ] <criterion specific to this PR>

**Verification:** <how to verify in isolation>

---

### PR 2: <imperative title>

**Depends on:** PR 1

<Same structure>

---

### Dependency Order

<Show the DAG — which PRs can be parallelized, which must be sequential.>

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| <what could go wrong> | <consequence> | <countermeasure> |
```

### Writing Good Acceptance Criteria

**1. Be specific, not aspirational.**
- Bad: "Error handling should be robust"
- Good: "When `createUser` receives an empty `email`, it returns a validation error with message containing 'email'"

**2. Every criterion must map to a test.**
Ask: "Can an AI agent write a test from this sentence alone?" If not, add detail.

**3. Include boundary conditions.**
- "When `limit` exceeds 100, the API returns a validation error (not silently capping)"

**4. Specify error behavior explicitly.**
- "If the database connection fails during import, the function returns a partial result with error count — it does not panic"

**5. Include negative criteria when important.**
- "The migration must NOT modify existing rows"

**6. Reference concrete types, functions, and paths.**
- Instead of "the store method," say "`UserStore.Create(ctx, user)`"

### Step 4: Validate the Draft

Before presenting to the user, verify:

1. Problem is framed, not just stated
2. Acceptance criteria are machine-testable
3. Scope is bounded with explicit "out of scope" items
4. Technical context has exact file paths and pattern references
5. Size is appropriate (decomposed if >400 lines)
6. No ambiguity — an AI agent could start implementing without clarifying questions
7. References are linked
8. Verification is explicit

Present the draft to the user via `AskUserQuestion` with options to submit as-is, edit, or cancel.

### Step 5: Submit

```
gh issue create --title "<type>: <imperative summary>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

Title format: `<type>: <imperative summary>` (under 72 characters). Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`.

Report the created issue number and URL.
