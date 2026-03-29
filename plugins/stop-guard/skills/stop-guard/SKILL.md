---
name: stop-guard
description: >-
  Install a Claude Code Stop hook that evaluates task completion via Gemini CLI.
  Blocks premature stops and tells Claude to continue when work is incomplete.
  Triggers: /stop-guard, install stop guard, set up stop hook
context: fork
agent: general-purpose
allowed-tools: Read, Write, Glob, Grep, Bash(chmod *), Bash(bash -n *), Bash(mkdir *), Bash(ls *), Bash(which *), Bash(jq *)
license: MIT
metadata:
  version: "1.0.0"
  tags: ["hook", "stop", "guard", "completion", "evaluator", "gemini"]
  author: benjamcalvin
---

# Stop Guard

Install a Claude Code Stop hook that uses Gemini CLI as an independent evaluator to determine whether a task is truly complete before allowing Claude to stop.

## Context

- Skill source directory: $SKILL_DIR
- Arguments: $ARGUMENTS

---

## Phase 1: Prerequisites

Check that required tools are available:

1. Run `which jq` — if not found, tell the user to install jq and stop
2. Run `which gemini` — if not found, tell the user to install the Gemini CLI (`npm install -g @google/gemini-cli`) and stop

Both must be present to continue.

---

## Phase 2: Configuration

Ask the user for their preferences:

1. **Max continuations** — How many times should the hook block a stop before giving up? Default: 3
2. **Evaluator model** — Which Gemini model to use? Default: `gemini-3-flash-preview`

Write the config to `.claude/stop-guard-config.json`:

```json
{
  "max_continuations": 3,
  "model": "gemini-3-flash-preview"
}
```

Create the `.claude/` directory if it doesn't exist.

---

## Phase 3: Script Generation

1. Read `$SKILL_DIR/assets/stop-guard.sh.tmpl`
2. Replace `{{CONFIG_PATH}}` with the absolute path to `.claude/stop-guard-config.json` (use `$(pwd)/.claude/stop-guard-config.json`)
3. Create directory `.claude/hooks/` if it doesn't exist
4. Write the result to `.claude/hooks/stop-guard.sh`
5. Run `chmod +x .claude/hooks/stop-guard.sh`
6. Run `bash -n .claude/hooks/stop-guard.sh` to verify syntax — if errors, fix them before proceeding

---

## Phase 4: Hook Registration

Read `$SKILL_DIR/assets/hooks-settings.json.tmpl`. Replace `{{SCRIPT_PATH}}` with the absolute path to `.claude/hooks` (use `$(pwd)/.claude/hooks`).

Check if `.claude/settings.json` exists:

**If it doesn't exist:** Create `.claude/` directory and write the hook config directly.

**If it exists:** Parse the existing settings. Check for existing `Stop` hooks:

- **If no Stop hooks exist:** Merge the new hook entries into the existing `hooks` object (or create the `hooks` key if absent).
- **If Stop hooks already exist:** Show the user the existing hooks and the new one. Ask: "Replace existing Stop hooks, keep existing, or abort?"

After writing, confirm the hooks are correctly configured by re-reading the file and validating it's valid JSON.

---

## Phase 5: Summary

Report to the user:

1. Config location: `.claude/stop-guard-config.json`
2. Hook script: `.claude/hooks/stop-guard.sh`
3. Hook registered in: `.claude/settings.json`
4. Max continuations: (configured value)
5. Evaluator model: (configured value)

Then explain the **activation interface**:

> **How to activate stop-guard in a session:**
>
> The hook only fires when the session transcript contains the activation marker.
> Any skill or prompt that wants stop-guard protection should include this text
> in its output:
>
> ```
> <!-- stop-guard:active -->
> ```
>
> Optionally, provide structured context for the evaluator:
>
> ```
> <!-- stop-guard:context {"task": "implement feature X", "criteria": ["tests pass", "PR created"]} -->
> ```
>
> The hook checks the transcript for these markers. No marker = no evaluation.
> Each session has its own transcript, so parallel sessions don't interfere.

---

## Important Notes

- The hook is **fail-open**: if Gemini CLI fails or times out, Claude is allowed to stop normally
- Counter state is stored in `$HOME/.cache/stop-guard/` keyed by session ID
- Logs are written to `$HOME/.claude/logs/stop-guard.log`
- The hook has a 15-second timeout enforced by Claude Code
