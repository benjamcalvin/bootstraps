---
name: pr
description: >-
  Branch, commit, PR, review, and merge — take current work to production.
  Handles the full PR lifecycle: creates a branch if needed, commits uncommitted work,
  opens the PR, runs standards checks, does adversarial review, addresses findings, and merges.
  Triggers: /pr, ship this, create a PR, send this to production
argument-hint: [PR-number | branch-description]
license: MIT
metadata:
  version: "1.0.0"
  tags: ["pr", "ship", "review", "merge"]
  author: benjamcalvin
---

# PR: Ship Current Work

Take the current work to production: $ARGUMENTS

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Existing PR for this branch: !`gh pr list --head "$(git branch --show-current)" --json number,title,state --jq '.[0] // empty' 2>/dev/null || echo "NONE"`
- Recent commits: !`git log --oneline -5`

## Instructions

You are a **lean orchestrator** that takes finished work from the current branch to a merged PR. You do NOT write features or fix bugs — that's what `/implement` is for. You handle the PR lifecycle: branch, commit, push, create PR, validate, review, address feedback, and merge.

**You MUST use the Task tools** (`TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`) throughout.

**Task tracking rules:**
1. Create a task for each phase before starting.
2. One `in_progress` at a time. Mark `completed` the moment it finishes.
3. Keep the list truthful — delete or update tasks if scope changes.

---

### Entry Point

Parse `$ARGUMENTS` to determine where to start:

1. **Bare number (e.g., `42`):** This is a PR number. Verify it exists with `gh pr view <number>`. Skip to Phase 4 (Validate).
2. **No arguments or freeform text:** Start from Phase 1. If freeform text is provided, use it as context for the branch name and commit message.

Check the Context above:
- If `Git status` is empty AND no existing PR exists AND no arguments were given, there's nothing to do. Tell the user.
- If an existing PR is shown in Context, record its number — you may be able to skip Phase 3.

---

### Phase 1: Branch Setup

**If already on a feature branch** (anything other than `main`), stay on it.

**If on `main`:**
1. Check that there are uncommitted changes or recent commits not on a remote. If `main` is clean with nothing to ship, stop and tell the user.
2. Create a feature branch based on the changes:
   - Examine `git status` and `git diff` to understand what changed
   - Pick an appropriate type: `feat`, `fix`, `refactor`, `style`, `docs`, `test`, `chore`
   - Create the branch: `git checkout -b <type>/<short-description>`

---

### Phase 2: Commit Remaining Work

Check for uncommitted changes (`git status`). If there are any:

1. **Understand the changes.** Run `git status` and `git diff` (staged and unstaged). Read changed files if needed to understand what was done.
2. **Stage relevant files.** Add specific files — not `git add .` or `git add -A` (avoids accidentally staging sensitive files or build artifacts).
3. **Craft a commit message.** Use `<type>: <imperative summary>` format. The message should describe *what* changed and *why*, not just list files.
4. **Commit.**

If there are multiple logical changes, separate them into distinct commits. No "WIP" or "fixup" commits.

If there are no uncommitted changes, skip this phase.

---

### Phase 3: Push and Create PR

1. **Push the branch:**
   ```bash
   git push -u origin HEAD
   ```

2. **Check for existing PR.** If the Context above shows an existing PR for this branch, use that PR number and skip creation.

3. **Create the PR:**
   ```bash
   gh pr create --title "<type>: <imperative summary>" --body "$(cat <<'EOF'
   ## Summary
   <1-3 sentences: what this change does and why>

   ## Test evidence
   <what was verified — e.g., "npm test — all passed", "pytest — all passed">

   ## Review focus
   <areas where review attention is most valuable>
   EOF
   )"
   ```

4. Record the PR number for subsequent phases.

---

### Phase 4: Validate (PR Standards Check)

Invoke the `pr-check` skill:

```
Skill tool -> skill: "pr-check", args: "<pr-number>"
```

**If any checks FAIL:**
- Fix what you can automatically (update PR title, edit description, amend commit messages)
- Re-run the check
- If a FAIL can't be fixed (e.g., PR is too large), flag it to the user

**If all checks PASS or WARN:** proceed to Phase 5.

---

### Phase 5: Review/Address Loop

Loops until clean. Each round: Specialist reviewers → Referee (you) → Addresser. **10-round escalation limit.**

#### Before Round 1

**Rebase on main** to ensure the review runs against current code:

```bash
git fetch origin main
git rebase origin/main
```

If conflicts arise, resolve them and run the full test suite. Force-push the rebased branch:

```bash
git push --force-with-lease
```

Then fetch a lightweight PR summary:
```bash
gh pr view <number>
gh pr view <number> --json files --jq '.files[] | "\(.path) (+\(.additions)/-\(.deletions))"'
```

Do **NOT** fetch the full diff. Read specific files when spot-checking during refereeing.

#### Step A: Invoke Reviewers

**Dynamically select** specialists based on change complexity:

- `review-correctness` — Logic bugs, edge cases, error handling, race conditions
- `review-security` — Spec conformance, authZ, PII, injection risks
- `review-standards` — Conventions, test coverage, PR format, branch targeting

**Invoke selected reviewers in parallel:**

```
Agent tool → agent: "review-correctness", prompt: "Review PR #<pr-number>, round <round-number>"
Agent tool → agent: "review-security", prompt: "Review PR #<pr-number>, round <round-number>"
Agent tool → agent: "review-standards", prompt: "Review PR #<pr-number>, round <round-number>"
```

#### Step B–E: Referee, Post Decisions, Invoke Addresser, Evaluate

Follow the same referee/address loop as documented in the `/implement` skill's Phase 4 (Steps B through E). The process is identical:

1. **Referee** every finding — Accept, Downgrade, or Reject
2. **Post** referee decisions to GitHub and write findings to a temp file
3. **Invoke** the addresser: `Skill tool → skill: "implement-address", args: "<pr-number> <round> <findings-file>"`
4. **Evaluate** whether to continue or escalate (10-round limit)

---

### Phase 6: Merge

Invoke the `merge-pr` skill:

```
Skill tool -> skill: "merge-pr", args: "<pr-number>"
```

Report the final result: PR URL, merge status, and any issues updated.

---

## Escalation

Stop and consult the user when:

- On `main` with no changes and no arguments — nothing to ship
- Merge conflicts that can't be resolved automatically
- CI checks failing for unclear reasons
- Human review approval needed (relayed from `merge-pr`)
- The PR is too large to pass `pr-check` sizing and can't be split automatically
- Any situation requiring judgment about whether to proceed
