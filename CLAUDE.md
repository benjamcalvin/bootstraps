# Bootstraps

An installable marketplace of Claude Code skills, hooks, and project scaffold templates.

## Project Purpose

This repo is a curated collection of reusable patterns for bootstrapping new projects with Claude Code. It provides:

- **Skills** — Slash-command skills (`.claude/skills/`) that can be installed into any project
- **Hooks** — Lifecycle hooks (`.claude/hooks/`) for automating common workflows
- **Scaffold Templates** — Project templates and starter configurations (not a Claude Code primitive — these are our own concept)

## Architecture

```
bootstraps/
├── skills/           # Installable skill definitions
│   └── <skill>/
│       ├── skill.md  # Skill prompt
│       └── meta.json # Metadata (name, description, triggers)
├── hooks/            # Installable hook definitions
│   └── <hook>/
│       ├── hook.sh   # Hook script
│       └── meta.json # Metadata (event, description)
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
- `meta.json` files describe items for the registry and installer
- Skills follow Claude Code skill format (markdown prompt files)
- Hooks are executable shell scripts
- All items include a description, tags, and version in their metadata
- Keep skill prompts focused and composable — one skill does one thing well
- Test skills and hooks locally before publishing to the registry

## Development Workflow

1. Create new items in the appropriate directory (`skills/`, `hooks/`, `scaffold-templates/`)
2. Add `meta.json` with required metadata fields
3. Update `registry.json` to include the new item
4. Test installation into a scratch project
5. Commit with a clear description of what the item does

## Metadata Schema

### meta.json (skills)
```json
{
  "name": "skill-name",
  "description": "What this skill does",
  "version": "1.0.0",
  "tags": ["category"],
  "triggers": ["when to use this skill"]
}
```

### meta.json (hooks)
```json
{
  "name": "hook-name",
  "description": "What this hook does",
  "version": "1.0.0",
  "tags": ["category"],
  "event": "hook-event-name"
}
```
