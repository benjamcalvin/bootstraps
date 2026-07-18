---
name: second-opinion
description: >-
  Consult external AI CLIs (Codex, Antigravity) headlessly for an independent
  second-opinion code review of the current changes, then synthesize their findings.
  Triggers: /second-opinion, second opinion, ask codex to review, ask antigravity to review
argument-hint: "[codex|antigravity|all] [scope: staged | branch | PR number | <git range>]"
license: MIT
metadata:
  version: "1.0.0"
  tags: ["review", "codex", "antigravity", "second-opinion", "headless", "multi-provider"]
  author: benjamcalvin
---

# Second Opinion

Get an independent code review from external AI CLIs: $ARGUMENTS

You orchestrate the review: build one prompt, fan it out to each requested
provider in parallel, then synthesize the results. The providers run headlessly
and read-only — they can explore the repo but cannot modify it.

## Step 1: Determine Providers

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/consult.sh" list
```

- If the user named a provider (`codex` or `antigravity`), use only that one — but
  verify it appears in the list, and tell the user if it doesn't (see
  **Installation** below).
- Otherwise use **all** available providers.
- If none are available, stop and show the user the installation instructions.

## Step 2: Determine Scope and Build the Diff

Pick the scope from the arguments, defaulting to the first of these that is non-empty:

| Scope argument | Diff command |
|---|---|
| PR number (e.g. `123` or `#123`) | `gh pr diff <n>` (also fetch `gh pr view <n>` for title/description) |
| explicit git range | `git diff <range>` |
| `staged` | `git diff --staged` |
| `branch` (or default) | `git diff <base>...HEAD` where base is `origin/main` or the repo default branch |
| working tree (fallback if branch diff is empty) | `git diff` |

If the resulting diff is empty, stop and tell the user there is nothing to review.

## Step 3: Build the Prompt

Create a run directory and write one prompt file shared by all providers:

```bash
RUN_DIR=$(mktemp -d -t second-opinion.XXXXXX)
```

`$RUN_DIR` holds the full diff (which may contain secrets), so treat its cleanup
as mandatory on **every** exit path, not just the happy one. If you abort after
this point for any reason — a provider fails, the diff turns out empty, an
unexpected error — run `rm -rf "$RUN_DIR"` before returning to the user, mirroring
the trap-based hygiene `run_codex` uses for its own temp file. The Step 5 cleanup
below is only the success-path case of this same rule.

Read the template at `$CLAUDE_PLUGIN_ROOT/assets/prompts/review.md` and write
`$RUN_DIR/prompt.md` with the placeholders filled in:

- `$SCOPE_DESCRIPTION` — one or two sentences: what is being reviewed (branch
  names, PR title/description if applicable, and the diff stat). For a PR,
  include the PR body so the reviewer knows the intent.
- `$DIFF_CONTENT` — the full diff inside a fenced ```diff block. If the diff
  exceeds ~4000 lines, instead include the diff stat plus the most important
  hunks, and note that the reviewer should read the listed files for the rest.

## Step 4: Run Providers in Parallel

**First, capture a read-only baseline.** The providers are supposed to run
read-only (codex via `--sandbox read-only`, antigravity via print-mode tool
denial), but that per-provider guarantee is the load-bearing contract of this
plugin. Record the repo state *before* launching anything so you can detect
in-tree mutations. Use `--ignored` so writes to git-ignored files (e.g. `.env`,
`*.pem`) — a prime target for a read-only escape — are also caught:

```bash
git status --porcelain --ignored > "$RUN_DIR/git-status.before"
git rev-parse HEAD > "$RUN_DIR/git-head.before"
```

This check covers tracked and ignored files *inside the worktree* only. Writes
outside the tree (e.g. `~/.ssh`, `~/.aws/credentials`) are not observable here
and remain part of maintainer verification against a real install.

Launch every provider as a background Bash task so they run concurrently
(reviews typically take 1–5 minutes each):

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/consult.sh" codex "$RUN_DIR/prompt.md" > "$RUN_DIR/codex.md"
```

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/consult.sh" antigravity "$RUN_DIR/prompt.md" > "$RUN_DIR/antigravity.md"
```

Wait for all background tasks to finish. Exit codes: `2` means the CLI is not
installed, `3` means it ran but failed (check stderr). If one provider fails,
continue with the others and note the failure in your summary.

**Then, verify the read-only contract held.** After all providers finish,
re-capture the repo state and compare:

```bash
git status --porcelain --ignored > "$RUN_DIR/git-status.after"
git rev-parse HEAD > "$RUN_DIR/git-head.after"
diff "$RUN_DIR/git-status.before" "$RUN_DIR/git-status.after"
diff "$RUN_DIR/git-head.before" "$RUN_DIR/git-head.after"
```

If either `diff` shows a difference, the working tree or HEAD changed while the
providers were running — a provider may have violated the read-only contract.
**Surface this loudly at the top of your synthesis** (which files changed, and
which provider run it coincides with) and warn the user to inspect and revert
before trusting the review. If both diffs are empty, note it briefly — but scope
the claim precisely: state that no tracked or ignored in-tree changes were
detected, and that writes outside the worktree are not covered by this check and
remain part of maintainer verification. Then proceed.

## Step 5: Synthesize

Read each provider's output file, then present a single consolidated review:

1. **Consensus findings first** — issues flagged by more than one provider (or
   by a provider *and* your own reading of the diff) are the highest-signal
   items. Say who flagged them.
2. **Unique findings** — attribute each to its provider. Before relaying a
   finding, sanity-check it against the actual code; drop findings that are
   factually wrong and say you did so.
3. **Verdict** — a short overall assessment: ship it, fix Action-Required
   items first, or needs rework.

Keep provider attribution visible throughout (e.g. `[codex]`, `[antigravity]`) so
the user can judge the sources. Do not act on any finding — this skill only
reports. Offer next steps (fix, post to PR) and let the user choose.

Once you have read the provider output files and produced the synthesis, remove
the run directory so runs don't leave temp dirs behind (mirroring the trap-based
cleanup `run_codex` does for its own temp file):

```bash
rm -rf "$RUN_DIR"
```

## Installation

If a provider is missing, show the user the relevant install command:

- **Codex CLI**: `npm install -g @openai/codex` (or `brew install codex`), then `codex login`
- **Antigravity CLI**: `curl -fsSL https://antigravity.google/cli/install.sh | bash`, then run `agy` once to log in (or set `ANTIGRAVITY_API_KEY`)

## Configuration

Optional environment variables:

- `SECOND_OPINION_CODEX_MODEL` — override the Codex model
- `SECOND_OPINION_ANTIGRAVITY_MODEL` — override the Antigravity model (see `agy models`)
