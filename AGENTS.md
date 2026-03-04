# Bootstraps

A plugin marketplace of reusable skills, hooks, and project scaffolds for AI coding agents.

## Structure

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
└── README.md
```

## Conventions

- Each plugin is self-contained under `plugins/`
- Skills follow the [Agent Skills open standard](https://agentskills.io/specification) — `SKILL.md` with YAML frontmatter
- One plugin does one thing well
- Plugins can bundle skills, hooks, agents, and assets
- See existing plugins for schema examples

## Development

1. Create directory under `plugins/`
2. Add `plugin.json` (name, description, version, author, license)
3. Add `SKILL.md` and/or hook configurations
4. Add entry to `marketplace.json`
5. Validate: `./validate-all.sh`
