---
name: draft-issue
description: >-
  Create well-structured GitHub issues optimized for /implement.
  Produces machine-readable issues with testable acceptance criteria.
  Triggers: /draft-issue, create an issue, write an issue
argument-hint: <brief description of what needs to be done>
license: MIT
metadata:
  version: "1.3.0"
  tags: ["issue", "draft", "planning"]
  author: benjamcalvin
---

# Draft Issue

Create a GitHub issue for: $ARGUMENTS

## Context

- Recent issues: !`gh issue list --limit 5 --json number,title --jq '.[] | "#\(.number) \(.title)"'`
- Current branch: !`git branch --show-current`

## Instructions

Good issues are the single biggest lever for `/implement` quality. A well-crafted issue gives `/implement`'s implementer and reviewers everything they need to succeed autonomously. A vague issue produces vague code.

The downstream consumer of these issues is an AI agent, so every section must be specific, unambiguous, and verifiable. But precision does not mean saturating every sentence with code references — it means putting each kind of detail at its proper altitude, so both a skimming human and an implementing agent can extract what they need.

### Writing at the Right Altitude

An issue descends through three altitude layers, and each section holds exactly one:

- **Behavior** (Problem): what the system does wrong or will do differently, in plain domain language. **No code identifiers of any kind** — no file paths, function names, or line numbers. Test: a contributor who knows the domain but has never read the code understands it completely.
- **Design** (Solution): the shape of the change in component and operation terms — which components change roles, how the flow differs before and after. Component and operation names (including endpoint routes) are allowed; files, functions, and line numbers are not.
- **Implementation** (Technical Context): the seams, exact files, patterns to mirror, and constraints. This is the layer for locational detail — `file.go:line` references, files to modify, code to mirror. Two narrow exceptions exist elsewhere: Acceptance Criteria may name the specific contract under test (see Writing Good Acceptance Criteria), and a Proposed PRs decomposition may list file paths in its tables.

A behavior- or design-layer sentence that seems to need a file reference is a sentence at the wrong altitude: move the reference down to Technical Context, not the sentence up.

Three disciplines keep the layers readable:

1. **One idea per sentence.** A sentence carrying a claim, its mechanism, and a citation is three sentences fighting — split it. Demote parenthetical asides to their own sentence or delete them.
2. **Citations end clauses; they never interrupt them.** Reference an issue, spec, or guarantee at most once per bullet, at the end. Provenance chains ("deferred from X, first flagged in Y") go in a one-line History section, never woven through the prose.
3. **The skim test.** Reading only the first sentence of each section must yield a correct summary of the issue at descending altitude. Run this check before presenting the draft.

### Step 1: Understand the Request

Parse `$ARGUMENTS` to determine:
- **Type:** Is this a bug, feature, chore, refactor, or docs task?
- **Scope:** What modules/files are likely involved?
- **Shape:** Is this one logical change a reviewer can hold in their head in one sitting — or a small batch of same-kind housekeeping changes? Choose the shape below.

If the request is vague, use the `AskUserQuestion` tool to clarify before proceeding. Do not guess at intent — surface ambiguity early.

#### Choosing the shape

Sprawl, not size, decides the shape. A long, detailed issue about one concern is fine; length and criteria count only prompt you to check for sprawl.

| The work is… | Shape |
|---|---|
| A localized bug or tweak | Small Fix template |
| One logical change, however detailed | Standard template |
| Slices of one concern that must land in sequence (schema → data layer → API) | Large template with Proposed PRs |
| Sprawling: independent concerns, subsystems, or repositories; parts waiting on owner decisions; or parts needing their own live rollout | A short parent issue stating the outcome, plus one sub-issue per deliverable, each with its own criteria and scope |
| Unrelated items | Separate issues — never one bucket issue |

Signs of hidden sprawl: a criterion that points at a spec instead of stating behavior ("behaves as the spec defines"), criteria that span unrelated components, or a criteria list that grows as decisions arrive.

**Open decisions and owner actions.** If the work needs a decision or an action only the owner can take, resolve it before drafting, or draft a separate owner-request issue that the build issue depends on. Title it `Owner request: <what is needed> (#<blocked>)` and label it `needs-owner`. Its sections are:

- **TL;DR** with a **Blocks:** line
- **Context**
- **Decisions:** a table of question, options and recommendation
- **Runbook:** exact commands or actions in order, each with its expected result
- **When done:** reply with the answers and `done`, then rerun `/implement` on the blocked issue

An issue with unanswered decisions is not ready for `/implement`.

### Step 2: Research Context

Before drafting, explore the codebase to ground the issue in reality.

1. **Find relevant code.** Use Glob/Grep/Read to locate modules, files, and patterns the implementation must interact with. Record exact file paths, and confirm each exists on the default branch, not only on an unmerged branch.
2. **Identify existing patterns.** Find analogous implementations. Note specific files and line numbers.
3. **Check related work.** Search `gh issue list --state all` and `gh pr list --state all` for related issues/PRs. Link anything relevant.
4. **Read referenced specs.** If the task touches a domain covered by specs in `docs/`, read them.
5. **Understand the blast radius.** Which tests exercise the affected code? What other modules depend on it?

### Step 3: Draft the Issue

#### Template: Small Fix

Use for a localized bug or tweak a reviewer reads in minutes. Problem may quote the evidence directly, including code identifiers in an error message or failing command; the other altitude rules do not apply.

```markdown
## Problem

<What is wrong and why it matters, with the evidence: error output,
reproduction, or observed behavior.>

## Acceptance Criteria

- [ ] <testable criterion, including a regression test for a bug>

## Out of Scope

- <what this fix must not touch>
```

#### Template: Standard Issue (Single PR)

Use when the work is one logical change that fits in a single PR.

```markdown
## Problem

<Behavior layer. What is broken, missing, or suboptimal, and why it matters.
Plain domain language with concrete examples — NO file paths, function names,
or line numbers. Someone who has never read the code must understand the gap.>

## Solution

<Design layer. The target state and the shape of the change in component
terms: which components change roles, how the flow differs before and after.
Component and operation names allowed; no files, functions, or line numbers.
Describe the target state, not implementation steps. For infrastructure or a
new capability, add one line naming the simplest built-in or existing option
and why it is not enough.>

## Acceptance Criteria

<Write criteria using structured patterns that map directly to tests:>

- [ ] When <trigger/action>, the system shall <expected behavior>
- [ ] Given <precondition>, when <action>, then <outcome>
- [ ] The <component> shall <behavior> (for invariants)
- [ ] If <error condition>, the system shall <fallback/error behavior>

<Each criterion should be independently verifiable. Include negative criteria
where important. Name the observable contract precisely (an endpoint, a
function signature) when the criterion is about it, but keep locational
detail — file paths, line numbers, patterns to mirror — in Technical Context.
Cite a spec or guarantee at the end of the bullet, not mid-clause.>

## Verification

- **Automated tests:** <which criteria map to tests? what patterns?>
- **Manual checks:** <anything requiring human/visual verification — keep minimal>
- **Existing test suite:** <must continue to pass>
- **Live steps owed:** <only for work verifiable solely on a live system: the
  rollout or check steps that remain after merge. Acceptance Criteria stay
  checkable before merge. Omit otherwise.>

## Scope

**In scope:**
- <specific deliverable 1>

**Out of scope:**
- <explicitly excluded item — why>

<details>
<summary>Technical Context</summary>

<Implementation layer — the home for file paths, line numbers, and
locational detail.>

- **Key files:** <exact paths to files the implementer must read or modify>
- **Patterns to follow:** <reference existing analogous code>
- **Constraints:** <tech stack requirements, no new dependencies, etc.>

</details>

## References

- <Links to relevant specs, ADRs, existing code, or prior issues>

## History

<Optional, one or two lines. Provenance only: what this was deferred from,
superseded by, or first flagged in. Keeps the discovery narrative out of the
sections above. Omit if there is none.>
```

#### Template: Large Issue (Multiple PRs)

Use when one concern needs several PRs that must land in sequence (schema → data layer → API). Sprawling work becomes a parent issue with sub-issues instead (see Choosing the shape).

Add these sections to the standard template:

```markdown
<details>
<summary>Proposed PRs</summary>

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

</details>

### Dependency Order

<Show the DAG — which PRs can be parallelized, which must be sequential.>

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| <what could go wrong> | <consequence> | <countermeasure> |
```

#### Collapsing detail

Keep Problem, Solution, Acceptance Criteria, Verification, and Scope visible: they are what a human reader must see. Collapse Technical Context and Proposed PRs under `<details><summary>…</summary>`, with a blank line after `</summary>` (GitHub renders Markdown inside only after one) and before `</details>`. An implementing agent reads the collapsed sections in full; a skimming human opens them only when needed.

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

**6. Name the contract under test precisely.**
- Instead of "the store method," say "`UserStore.Create(ctx, user)`"
- But keep *locational* detail (file paths, line numbers, analogous code) in Technical Context — a criterion states the observable contract, not where to find it

### Step 4: Validate the Draft

Before presenting to the user, verify:

1. Problem is framed, not just stated
2. Acceptance criteria are machine-testable, and no two conflict
3. Scope is bounded with explicit "out of scope" items
4. **Shape check:** the shape matches Choosing the shape — sprawl is split into sub-issues, not embedded as Proposed PRs; no unrelated items share an issue; no owner decision is left open
5. No ambiguity — an AI agent could start implementing without clarifying questions
6. Verification is explicit

For Standard and Large issues, also verify:

7. Technical context has exact file paths and pattern references, and references are linked
8. **Collapse check:** Technical Context and Proposed PRs sit inside `<details>` blocks with a blank line after `</summary>`
9. **Altitude check:** Problem and Solution contain zero file paths, function names, or line numbers; all code identifiers live in Acceptance Criteria (contracts only), Technical Context, and Proposed PRs file tables
10. **Skim test:** the first sentence of each section, read in order, forms a correct summary at descending altitude
11. **Sentence discipline:** no sentence carries a claim, its mechanism, and a citation at once; provenance lives only in History

Present the draft to the user via `AskUserQuestion` with options to submit as-is, edit, or cancel.

### Step 5: Submit

```
gh issue create --title "<type>: <imperative summary>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

Title format: `<type>: <imperative summary>` (under 72 characters). Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`.

For sprawling work, create the parent first, then each sub-issue with a `Parent issue: #<parent-number>` line, then edit the parent to list the sub-issues and their dependency order.

Report the created issue numbers and URLs.
