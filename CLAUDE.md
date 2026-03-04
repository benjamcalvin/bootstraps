# Bootstraps

A Claude Code plugin marketplace of reusable skills, hooks, and project scaffolds.

## Why

Curated collection of reusable patterns for bootstrapping new projects with Claude Code. Distributed as a standard plugin marketplace — no custom installer needed.

## What

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
├── validate-all.sh        # Plugin validation script
├── CLAUDE.md
└── README.md
```

## How

### Install

```bash
/plugin marketplace add benjamcalvin/bootstraps
/plugin install bootstrap-docs@bootstraps
```

### Create a new plugin

1. Create directory under `plugins/`
2. Add `plugin.json` (name, description, version, author, license)
3. Add `SKILL.md` and/or `hooks/hooks.json`
4. Add entry to `marketplace.json`

### Validate and test

```bash
./validate-all.sh                          # Validate all plugins
claude plugin validate plugins/<name>      # Validate one plugin
claude --plugin-dir plugins/<name>         # Test locally
claude --debug                             # Debug hook matching
```

## Conventions

- Each plugin is self-contained under `plugins/`
- Skills use `SKILL.md` with YAML frontmatter ([Agent Skills standard](https://agentskills.io/specification))
- Hooks use Claude Code JSON format in `hooks/hooks.json` (handler types: command, http, prompt, agent)
- One plugin does one thing well
- Plugins can bundle skills + hooks + agents + assets
- See existing plugins for schema examples (e.g., `plugins/bootstrap-docs/plugin.json`, `plugins/bootstrap-docs/SKILL.md`)
