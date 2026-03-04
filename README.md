# Bootstraps

A Claude Code plugin marketplace of reusable skills, hooks, and project scaffolds.

## Prerequisites

This is a private repository. You need access to `benjamcalvin/bootstraps` on GitHub and git credentials configured (e.g. `gh auth login`).

For automatic plugin updates at Claude Code startup, set a GitHub token in your environment:

```sh
export GITHUB_TOKEN=ghp_your_token_here
```

Without this, plugins still work — you just need to update manually with `/plugin marketplace update bootstraps`.

## Install

Add the marketplace to Claude Code:

```
/plugin marketplace add benjamcalvin/bootstraps
```

## Browse Plugins

List available plugins:

```
/plugin marketplace list
```

Or open the interactive plugin manager:

```
/plugin
```

Navigate to the **Discover** tab to browse plugins from this marketplace.

## Install a Plugin

```
/plugin install bootstrap-docs@bootstraps
```

Choose a scope when prompted:
- **user** (default) — available in all your projects
- **project** — available to anyone working on the current project
- **local** — only for you in the current project

## Use a Plugin

Invoke a plugin's skill as a slash command:

```
/bootstrap-docs
```

Some skills accept arguments:

```
/bootstrap-docs adr
/bootstrap-docs specs
```

## Update Plugins

```
/plugin marketplace update bootstraps
```

## Uninstall a Plugin

```
/plugin uninstall bootstrap-docs@bootstraps
```

## Available Plugins

| Plugin | Description |
|--------|-------------|
| **bootstrap-docs** | Set up a comprehensive, AI-readable documentation strategy in any project. Creates AGENTS.md, specs, ADRs, guides, plans, standards, and research templates. |

## License

MIT
