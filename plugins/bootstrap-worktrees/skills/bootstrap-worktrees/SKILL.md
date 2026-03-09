---
name: bootstrap-worktrees
description: >-
  Set up project-agnostic worktree isolation with per-worktree ports,
  Docker Compose projects, and config files. Discovers services, generates
  create/remove scripts and Claude Code hook configuration.
  Triggers: /bootstrap-worktrees, set up worktree isolation, bootstrap worktrees
argument-hint: "[audit]"
context: fork
agent: general-purpose
license: MIT
metadata:
  version: "1.0.0"
  tags: ["worktree", "isolation", "docker", "compose", "ports", "hooks"]
  author: benjamcalvin
---

# Bootstrap Worktree Isolation

Set up project-agnostic worktree isolation so multiple Claude Code sessions can work on different branches simultaneously without port conflicts, database collisions, or stale container leaks.

## Context

- Skill source directory: $SKILL_DIR
- Arguments: $ARGUMENTS

Before starting, gather context by running these commands:

1. Check for existing config: `cat .bootstraps-worktree-config.yml 2>/dev/null || echo "NO_CONFIG_FILE"`
2. Check for existing scripts: `ls scripts/create-worktree.sh scripts/remove-worktree.sh 2>/dev/null || echo "NO_SCRIPTS"`
3. Check for compose files: `ls compose.yml docker-compose.yml 2>/dev/null || echo "NO_COMPOSE"`
4. Check for hook config: `cat .claude/settings.json 2>/dev/null || echo "NO_SETTINGS"`

## Instructions

This skill runs six phases to set up worktree isolation. It is **re-runnable** — it checks what exists and only regenerates what's needed.

**Template files** are in the skill's `assets/` directory at `$SKILL_DIR/assets/`. Read them on demand with the Read tool only when that phase needs them.

---

### Phase 0: Preferences

Check if `.bootstraps-worktree-config.yml` exists (from the context-gathering step above).

**If NO_CONFIG_FILE:** Proceed to Phase 1 (discovery) to build the config from scratch.

**If config exists:** Parse it and confirm with the user: "Found existing worktree config with N services. Re-run setup or modify?" Options:

- **Re-run**: Regenerate scripts from existing config (skip to Phase 4).
- **Modify**: Go to Phase 2 to adjust services interactively.
- **Cancel**: Stop.

---

### Phase 1: Service Discovery

Scan the project to discover services that need port isolation. Check these sources in order:

#### 1a. Docker Compose files

Look for `compose.yml`, `docker-compose.yml`, or `compose.yaml` in the project root and common subdirectories (`docker/`, `infra/`, `.docker/`). For each compose file found, extract:

- **Service names** from the `services:` block
- **Port mappings** from `ports:` entries (e.g., `"5432:5432"`, `"${DB_PORT}:5432"`)
- **Environment variable references** in port mappings (e.g., `${DB_PORT:-5432}`)

For each service with port mappings, create a service entry:

```yaml
- name: <service_name>           # e.g., "postgres", "redis"
  env_var: <PORT_ENV_VAR>        # e.g., "DB_PORT", "REDIS_PORT"
  default_port: <number>         # The port from the compose mapping
  range_start: <number>          # Start of allocation range
  range_end: <number>            # End of allocation range
```

**Range allocation strategy**: For each service, compute the range based on the default port:

- If the default port is below 1024, pick a high range (e.g., default 5432 → range 5432–5532)
- Otherwise, use default_port as range_start and default_port + 99 as range_end
- Ensure ranges don't overlap between services (shift if needed)

#### 1b. Environment files

Scan `.env`, `.env.example`, `.env.sample`, `.env.development` for variables matching `*_PORT` patterns. Cross-reference with compose discoveries — add any ports found here that weren't in compose.

#### 1c. Config files

Scan for port references in common config files: `mise.toml`, `mise.local.toml`, `Procfile`, `Makefile`, `docker-compose.override.yml`. Add any new port env vars discovered.

#### 1d. External resource detection

Scan environment files for variables matching patterns that suggest external/shared resources:

- `*_URL`, `*_ENDPOINT` — API endpoints
- `*_API_KEY`, `*_SECRET` — credentials
- `*_BUCKET`, `*_QUEUE` — cloud resources
- `*_WEBHOOK` — webhook URLs
- `DATABASE_URL` (when pointing to a remote host, not localhost)

Record these as shared resources that **cannot** be isolated per-worktree.

If **no services are discovered**, inform the user: "No services with port bindings found. You can define services manually." Then proceed to Phase 2 with an empty service list for manual entry.

---

### Phase 2: Interactive Confirmation

Present the discovered services to the user in a clear table:

```
Discovered services:
  # | Service     | Env Var      | Default Port | Range
  1 | postgres    | DB_PORT      | 5432         | 5432–5531
  2 | redis       | REDIS_PORT   | 6379         | 6379–6478
  3 | app-server  | SERVER_PORT  | 8080         | 8080–8179
```

Ask the user to confirm or modify:

- **Accept all**: Proceed with discovered services as-is.
- **Modify**: Allow the user to:
  - **Remove** a service (by number)
  - **Add** a service (name, env var, default port, range)
  - **Edit** a service's env var, port, or range
- **Start fresh**: Discard discoveries and define manually.

Also present any shared resources discovered:

```
Shared resources detected (cannot be isolated per-worktree):
  - DATABASE_URL → postgres://prod-host:5432/mydb (external database)
  - STRIPE_API_KEY → sk_live_... (shared API key)
  - S3_BUCKET → my-app-uploads (shared bucket)
```

Warn the user about each shared resource and ask if they want to note any mitigations (e.g., per-worktree schema prefix, test API keys).

Also ask:

- **Compose prefix**: Project name prefix for Docker Compose (default: repo directory name). Used as `<prefix>-<worktree-slug>`.
- **Scripts directory**: Where to write generated scripts (default: `scripts/`).
- **Config file formats**: Which config files to generate per-worktree:
  - `.env` (always generated)
  - `mise.local.toml` — if `mise.toml` exists in the project
  - Other formats the user specifies
- **Compose file path**: Which compose file to use (auto-detected, confirm with user).
- **Branch delete env var**: Environment variable name for optional branch deletion on remove (default: `<UPPER_REPO_NAME>_WORKTREE_DELETE_BRANCH`).

---

### Phase 3: Build Configuration

Construct the full configuration and save to `.bootstraps-worktree-config.yml`:

```yaml
project_name: "<repo_name>"
compose_prefix: "<prefix>"
compose_file: "compose.yml"
scripts_dir: "scripts"
delete_branch_env_var: "MYPROJECT_WORKTREE_DELETE_BRANCH"

services:
  - name: postgres
    env_var: DB_PORT
    default_port: 5432
    range_start: 5432
    range_end: 5531
  - name: app-server
    env_var: SERVER_PORT
    default_port: 8080
    range_start: 8080
    range_end: 8179

config_formats:
  - env              # always
  - mise.local.toml  # if detected

shared_resources:
  - name: DATABASE_URL
    value: "postgres://prod-host:5432/mydb"
    note: "Use per-worktree local database instead"
  - name: STRIPE_API_KEY
    note: "Use test keys per-worktree"

env_template: |
  # Auto-generated by create-worktree.sh — do not commit.
  {{ENV_LINES}}
  COMPOSE_PROJECT_NAME=$compose_project
```

The `env_template` section captures the `.env` file content pattern. During discovery, build this from the existing `.env` or `.env.example` file, replacing hardcoded port values with the allocated port variables.

---

### Phase 4: Generate Scripts

Read each template from `$SKILL_DIR/assets/`, replace the `{{...}}` placeholders with values derived from the configuration, and write to the scripts directory.

#### 4a. Generate `create-worktree.sh`

Read `$SKILL_DIR/assets/create-worktree.sh.tmpl`. Replace these placeholders:

| Placeholder | Replacement |
|-------------|-------------|
| `{{SERVICE_PORT_ALLOCATIONS}}` | One `allocate_port` call per service. Example for a service `{name: postgres, env_var: DB_PORT, range_start: 5432, range_end: 5531}`: `db_port="$(allocate_port DB_PORT 5432 5531)"` — use lowercase env_var as the bash variable name. |
| `{{PORT_LOG_SUMMARY}}` | Space-separated `KEY=$var` pairs. Example: `DB_PORT=$db_port SERVER_PORT=$server_port` |
| `{{COMPOSE_PREFIX}}` | The compose prefix from config (e.g., `myproject`) |
| `{{ENV_FILE_CONTENT}}` | The `.env` content lines using allocated port variables. Build from the `env_template` in config, replacing `{{ENV_LINES}}` with one line per service env var (e.g., `DB_PORT=$db_port`) plus any additional static env vars from the project's `.env.example`. |
| `{{EXTRA_CONFIG_FILES}}` | Additional config file generation blocks. For `mise.local.toml`: a heredoc writing `[env]` section with port assignments. For each format in `config_formats` (other than `env`). Include `mise trust` call if generating mise config. |
| `{{WORKTREE_INFO_PORTS}}` | One `KEY=$var` line per service for the `.worktree-info` file. Example: `DB_PORT=$db_port` |
| `{{COMPOSE_FILE}}` | The compose file path from config (e.g., `compose.yml`) |
| `{{COMPOSE_ENV_VARS}}` | Environment variable assignments for the `docker compose up` command. Example: `DB_PORT="$db_port" REDIS_PORT="$redis_port"` |
| `{{SHARED_RESOURCES}}` | A `SHARED_RESOURCES` block listing resources that can't be isolated, for operator awareness. Example: `SHARED_RESOURCES=DATABASE_URL,STRIPE_API_KEY` |

Write to `<scripts_dir>/create-worktree.sh` and make executable (`chmod +x`).

#### 4b. Generate `remove-worktree.sh`

Read `$SKILL_DIR/assets/remove-worktree.sh.tmpl`. Replace:

| Placeholder | Replacement |
|-------------|-------------|
| `{{DELETE_BRANCH_ENV_VAR}}` | The env var name from config (e.g., `MYPROJECT_WORKTREE_DELETE_BRANCH`) |

Write to `<scripts_dir>/remove-worktree.sh` and make executable.

#### 4c. Verify generated scripts

After writing each script, verify:

1. The file exists and is executable
2. Run `bash -n <script>` to check for syntax errors
3. If syntax errors are found, fix them before proceeding

---

### Phase 5: Hook Configuration

Read `$SKILL_DIR/assets/hooks-settings.json.tmpl`. Replace `{{SCRIPTS_DIR}}` with the scripts directory from config (e.g., `scripts`).

Check if `.claude/settings.json` exists:

**If it doesn't exist:** Create `.claude/` directory and write the hook config directly.

**If it exists:** Parse the existing settings. Check for existing `WorktreeCreate` and `WorktreeRemove` hooks:

- **If hooks don't exist:** Merge the new hook entries into the existing `hooks` object (or create the `hooks` key if absent).
- **If hooks already exist:** Show the user the existing hooks and the new ones. Ask: "Replace existing worktree hooks, keep existing, or abort?"

After writing, confirm the hooks are correctly configured by re-reading the file and validating it's valid JSON.

---

### Phase 6: Summary

Report to the user:

1. **Generated scripts:**
   - `<scripts_dir>/create-worktree.sh` — creates worktrees with isolated ports and compose projects
   - `<scripts_dir>/remove-worktree.sh` — tears down worktrees and their resources

2. **Hook configuration:** `.claude/settings.json` updated with WorktreeCreate and WorktreeRemove hooks

3. **Services configured:** List each service with its env var and port range

4. **Shared resource warnings:** List any shared resources that need manual attention

5. **Config saved:** `.bootstraps-worktree-config.yml` — re-run `/bootstrap-worktrees` to regenerate

6. **Next steps:**
   - Test by running: `claude` and then using the worktree feature
   - Add `mise.local.toml`, `.env`, `.worktree-info` to `.gitignore` if not already present
   - Set `<DELETE_BRANCH_ENV_VAR>=1` to auto-delete merged branches on worktree removal
   - Run `/bootstrap-worktrees audit` to verify the setup (available after installing the audit extension)

7. **Files to gitignore** (suggest additions if not already present):
   ```
   .env
   mise.local.toml
   .worktree-info
   ```
