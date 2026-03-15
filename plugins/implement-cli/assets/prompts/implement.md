# Implement

Implement the following task. Linked issue number: $ISSUE_NUMBER (0 = none).

## Task

$TASK_DESCRIPTION

## Plan

$PLAN

## Instructions

Read project-level instructions (AGENTS.md, CLAUDE.md) for critical invariants.

1. **Create a feature branch** if on main: `git checkout -b <type>/<short-description>`
2. **Write tests first** — follow existing test patterns in the codebase
3. **Write production code** — minimum code to make tests pass, follow existing patterns
4. **Run the full test suite** — all tests and lints must pass
5. **Self-review** — read every changed file, fix issues
6. **Commit** — `<type>: <summary>` format, imperative mood
7. **Push and create PR:**
   ```bash
   git fetch origin main && git rebase origin/main
   git push -u origin HEAD
   gh pr create --title "<type>: <summary>" --body "<body with Summary, Test evidence, Review focus>"
   ```

If issue number is not 0, include `Closes #$ISSUE_NUMBER` in the PR body.

## Output

Return exactly:
```
PR_NUMBER: <number>
PR_TITLE: <title>
SUMMARY: <1-2 sentence summary>
```
