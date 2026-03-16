---
name: cleanup-issue
description: >-
  Fix formatting, fill missing sections, and clarify ambiguity in existing GitHub issues.
  Triggers: /cleanup-issue, clean up issue, fix issue formatting
argument-hint: <#issue-number>
license: MIT
metadata:
  version: "1.0.0"
  tags: ["issue", "cleanup", "formatting"]
  author: benjamcalvin
---

# Cleanup Issue

Clean up GitHub issue: $ARGUMENTS

## Context

- Issue: !`gh issue view $0 --json number,title,body,labels,state --jq '{number, title, body, labels: [.labels[].name], state}'`
- Issue comments: !`gh issue view $0 --comments 2>/dev/null || echo "NO_COMMENTS"`
- Issue template patterns: !`gh issue list --limit 5 --json number,title --jq '.[] | "#\(.number) \(.title)"'`

## Instructions

You clean up existing GitHub issues so they are well-structured, unambiguous, and ready for implementation by an AI agent. You do **not** change the intent or scope — only the form and clarity.

### Step 1: Parse the Target

Extract the issue number from `$ARGUMENTS`. If no valid issue number is found, use `AskUserQuestion` to ask for one.

### Step 2: Assess the Issue

Read the issue body from Context above. Evaluate it against these quality dimensions:

| Dimension | What to check |
|-----------|---------------|
| **Structure** | Does it have clear sections (Problem, Solution, Acceptance Criteria, etc.)? |
| **Formatting** | Consistent markdown, proper code blocks, readable tables? |
| **Completeness** | Are key sections missing entirely? (Problem, Acceptance Criteria, Scope) |
| **Clarity** | Are there vague phrases, ambiguous pronouns, or undefined terms? |
| **Actionability** | Could an AI agent start implementing from this issue without clarifying questions? |

### Step 3: Fix Issues

Apply fixes in order of impact:

#### 3a: Structural Fixes

If the issue lacks clear sections, restructure it using the standard template:

```markdown
## Problem

<extracted from existing content>

## Solution

<extracted from existing content>

## Acceptance Criteria

- [ ] <extracted or inferred from existing content>

## Scope

**In scope:**
- <extracted>

**Out of scope:**
- <extracted or inferred>

## Technical Context

- **Key files:** <extracted if present>
```

Preserve all original information. Do not invent new requirements — only reorganize what exists.

#### 3b: Formatting Fixes

- Fix broken markdown (unclosed code blocks, malformed links, inconsistent heading levels)
- Convert inline code references to backtick format
- Convert unstructured lists of requirements into checkbox acceptance criteria
- Ensure code snippets have language annotations

#### 3c: Clarity Fixes

- Replace vague language with specific terms where the meaning is unambiguous from context
  - "the endpoint" → "`POST /api/users`" (if identifiable)
  - "it should work" → "returns HTTP 200 with the created resource"
- Flag genuinely ambiguous statements with `<!-- CLARIFICATION NEEDED: ... -->` comments rather than guessing
- Expand acronyms on first use if they aren't widely known

#### 3d: Acceptance Criteria Polish

If acceptance criteria exist but are weak, strengthen them:

- Bad: "Error handling works" → Good: "When `createUser` receives an empty `email`, it returns a 400 with a validation error"
- Bad: "Tests pass" → Good: "Unit tests cover the happy path and at least one error case for each new public function"

Only sharpen criteria that are clearly implied by the existing issue. Do **not** add new requirements.

### Step 4: Present the Diff

Show the user a before/after comparison of the key changes. Use `AskUserQuestion` with options:
- **Apply** — update the issue
- **Edit** — let the user request changes
- **Cancel** — discard

### Step 5: Apply

Update the issue:

```bash
gh issue edit <number> --body "$(cat <<'EOF'
<cleaned-up body>
EOF
)"
```

Report what changed (e.g., "Added missing Acceptance Criteria section, fixed 3 formatting issues, clarified 2 ambiguous statements").
