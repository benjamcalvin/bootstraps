# Bootstraps

A Claude Code plugin marketplace of reusable skills, hooks, and project scaffolds.

## Project Purpose

This repo is a curated collection of reusable patterns for bootstrapping new projects with Claude Code, distributed as a plugin marketplace. Install with `/plugin marketplace add benjamcalvin/bootstraps`.

## Architecture

```
bootstraps/
├── marketplace.json       # Plugin marketplace manifest
├── plugins/               # All distributable plugins
│   └── <plugin>/
│       ├── plugin.json    # Plugin metadata
│       ├── SKILL.md       # Skill definition (Agent Skills open standard)
│       ├── hooks/         # Hook configurations (if any)
│       │   └── hooks.json
│       ├── assets/        # Templates, schemas, data files
│       └── references/    # On-demand documentation
├── CLAUDE.md
└── README.md
```

## Conventions

- Each plugin is self-contained in its own directory under `plugins/`
- Skills use `SKILL.md` with YAML frontmatter (Agent Skills open standard)
- Hooks use Claude Code's JSON format in `hooks/hooks.json`
- One plugin does one thing well
- Plugins can bundle skills + hooks + agents + assets

## Development Workflow

1. Create a new plugin directory under `plugins/`
2. Add `plugin.json` with name, description, version, author, license
3. Add `SKILL.md` (for skills) and/or `hooks/hooks.json` (for hooks)
4. Add entry to `marketplace.json`
5. Validate: `claude plugin validate plugins/<name>`
6. Test locally: `claude --plugin-dir plugins/<name>`

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
