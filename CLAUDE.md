# Bootstraps

An installable marketplace of Claude Code skills, hooks, and project scaffold templates.

## Project Purpose

This repo is a curated collection of reusable patterns for bootstrapping new projects with Claude Code. It provides:

- **Skills** — Slash-command skills (`.claude/skills/`) that can be installed into any project
- **Hooks** — Lifecycle hook configurations (`hooks/hooks.json` within plugins) for automating workflows
- **Scaffold Templates** — Project templates and starter configurations (not a Claude Code primitive — these are our own concept)

## Architecture

```
bootstraps/
├── skills/           # Installable skill definitions
│   └── <skill>/
│       ├── skill.md  # Skill prompt
│       └── meta.json # Metadata (name, description, triggers)
├── hooks/            # Hook definitions (within plugins)
│   └── hooks.json    # Hook configuration (Claude Code JSON format)
├── scaffold-templates/        # Project templates
│   └── <template>/
├── installer/        # CLI installer for marketplace
│   └── install.sh
├── registry.json     # Master registry of all available items
├── CLAUDE.md
└── README.md
```

## Conventions

- Each skill/hook is self-contained in its own directory
- Skills use `SKILL.md` with YAML frontmatter (Agent Skills open standard)
- Hooks use Claude Code's JSON format in `hooks/hooks.json` within plugins
- All items include a description, tags, and version in their metadata
- Keep skill prompts focused and composable — one skill does one thing well
- Test skills and hooks locally before publishing to the registry

## Development Workflow

1. Create new items in the appropriate directory (`skills/`, `hooks/`, `scaffold-templates/`)
2. Add `SKILL.md` with YAML frontmatter (for skills) or `hooks/hooks.json` (for hooks)
3. Update `marketplace.json` to include the new item
4. Test installation into a scratch project
5. Commit with a clear description of what the item does

## Metadata Schema

### SKILL.md (skills — Agent Skills open standard)
```yaml
---
name: skill-name
description: What this skill does
license: MIT
metadata:
  version: "1.0.0"
  tags: ["category"]
  author: author-name
---

[Skill instructions in markdown...]
```

### hooks.json (hooks — Claude Code format)
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "script-to-run.sh"
          }
        ]
      }
    ]
  }
}
```

Hook handler types: `command`, `http`, `prompt`, `agent`
