---
name: implement-plan
description: Explore codebase and plan implementation for implement workflow (runs as subagent)
context: fork
agent: general-purpose
argument-hint: <task description and optional instructions>
license: MIT
metadata:
  version: "1.0.0"
  tags: ["implement", "plan", "subagent"]
  author: benjamcalvin
---

# Plan Implementation

Plan the implementation for the following task:

$ARGUMENTS

## Context

- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`

## Project Standards

Read project-level instructions if they exist. Check for:

- `AGENTS.md` — Development principles, critical invariants, privacy rules
- `CLAUDE.md` — Project-specific workflow instructions
- Standards or conventions docs in `docs/` or `docs/specs/standards/`

You do not need to read all of these. Read the ones relevant to the task.

## Instructions

You are the **planner** for the `/implement` workflow. Your job is to explore the codebase, understand the problem, and produce a concrete implementation plan. You do NOT write code — you plan.

Use the **Task tools** (`TaskCreate`, `TaskUpdate`) to track your progress through the steps below.

### Step 1: Understand the Task

Read the task description above carefully. Identify:
- What needs to change (feature, fix, refactor, etc.)
- Any referenced specs, ADRs, or issues
- Ambiguities or missing context

If specs or issues are referenced, read them with the Read tool. If an issue number is mentioned, fetch it with `gh issue view <N>`.

### Step 2: Explore the Codebase

Use Glob, Grep, and Read to understand:
- Which modules and files are relevant
- Existing patterns in the codebase that the implementation should follow
- Test structure and conventions in the affected areas
- Dependencies between affected modules

Focus on understanding. Do not explore exhaustively — target the areas the task touches.

### Step 3: Define Acceptance Criteria

Write verifiable acceptance criteria. Each criterion should be testable — something you can prove true or false after implementation. Be specific:

- **Good:** "The `createUser` method validates that `email` is non-empty and returns an error if not"
- **Bad:** "User creation handles edge cases"

### Step 4: Identify Test Cases

List the tests that must pass iff the acceptance criteria are satisfied. Include:
- Happy path for each criterion
- Edge cases (empty input, nil values, boundary conditions)
- Error cases (invalid input, unauthorized access, missing dependencies)
- Regression tests if modifying existing behavior

### Step 5: Plan the Implementation

Identify:
- Files to create or modify, in order
- The minimum viable approach (simplicity first)
- Dependencies between changes (what must happen first)
- Any risks or open questions

### Output

Return your plan in this structure:

```
## Acceptance Criteria
1. <criterion>
2. <criterion>

## Test Cases
1. <test description> → verifies criterion N
2. <test description> → verifies criterion N

## Implementation Plan
1. <file> — <what to change and why>
2. <file> — <what to change and why>

## Sequencing
<which changes depend on which, any ordering constraints>

## Risks / Open Questions
<anything the implementer should be aware of>
```
