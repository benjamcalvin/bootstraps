---
name: implement-team
description: >-
  Implementation lifecycle re-architected around Claude Code agent-teams —
  long-lived implementer and reviewer teammates with shared task list and
  mailbox messaging. Higher token cost than /implement in exchange for
  fewer speculative findings and better cross-reviewer dedupe.
  Triggers: /implement-team, implement with a team
argument-hint: <#issue | PR-number | freeform task> [instructions]
license: MIT
metadata:
  version: "0.2.0"
  tags: ["implement", "lifecycle", "review", "agent-teams", "experimental"]
  author: benjamcalvin
---

# Implement (team mode)

Orchestrate the full implementation lifecycle for: $ARGUMENTS

This skill is **experimental** and depends on Claude Code's agent-teams feature. It must pass two preflight checks before doing any work.

## Preflight

Run these checks in order. If any check fails, print the failure message exactly as written and **exit without spawning a team**. Do not proceed to the stub body, do not attempt partial work.

### Check 1 — Claude Code version >= 2.1.32

Run:

```bash
claude --version
```

Parse the version number from the output (format is usually `<major>.<minor>.<patch>` possibly followed by a suffix such as `-beta` or a build identifier). Compare against the minimum `2.1.32`.

- If `claude --version` fails to run, treat it as a failed check.
- If the reported version is **less than 2.1.32**, print this message and exit:

```
/implement-team preflight failed: Claude Code version is too old.

This plugin depends on the experimental agent-teams feature, which requires Claude Code 2.1.32 or later.

Detected version: <observed version, or "unknown" if parsing failed>
Required version: >= 2.1.32

To upgrade, follow the official instructions at:
  https://code.claude.com/docs/en/setup#update-claude-code

After upgrading, re-run /implement-team.
```

- If the version is **>= 2.1.32**, continue to Check 2.

### Check 2 — CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

Agent-teams is gated behind an environment variable. The feature will not initialize teammates unless it is set to `1` at Claude Code startup.

Check whether the variable is set:

```bash
printenv CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
```

- If the value is exactly `1`, continue to the stub body.
- Otherwise (unset, empty, or any other value), print this message and exit:

```
/implement-team preflight failed: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is not enabled.

This plugin depends on the experimental agent-teams feature, which is opt-in and must be enabled at Claude Code startup.

To enable it, add the following to your Claude Code settings.json (either the user-level file at ~/.claude/settings.json or the project-level file at .claude/settings.json):

  {
    "env": {
      "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
    }
  }

Alternatively, export it in the shell from which you launch Claude Code:

  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

Minimum Claude Code version: 2.1.32

After enabling it, fully restart Claude Code (not just /resume) and re-run /implement-team.

For more details, see: https://code.claude.com/docs/en/agent-teams
```

## Instructions

Both preflight checks passed. The full lead-side orchestration body is not yet implemented — this plugin is being built in staged PRs against issue #69.

Print this message and stop:

```
team-spawn not yet implemented — tracked in issue #69
```

Do not spawn a team, do not create tasks, do not modify any files. PRs 2–5 against issue #69 will add:

- PR 2: Reviewer teammate agent definitions (`team-reviewer-*`).
- PR 3: Implementer and verifier teammate agent definitions.
- PR 4: Full lead-side orchestration body replacing this stub.
- PR 5: `references/when-to-use.md` comparing `/implement`, `/implement-team`, `/implement-cli`.
