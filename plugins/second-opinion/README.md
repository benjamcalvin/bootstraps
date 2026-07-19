# second-opinion

Consult external AI CLIs for an independent, headless code review of your
current changes. Claude builds one review prompt from your diff, fans it out to
every supported CLI installed on your machine, runs them read-only in parallel,
and synthesizes the findings into a single consolidated review with per-provider
attribution.

This is the read-only **`consult` tier** of the privilege-tiered delegation
model specified in
[ADR-001](../../docs/adr/001-task-delegation-privilege-model.md). Every
provider subprocess runs inside the pinned Anthropic
[`sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime)
(`srt`) wrapper — an OS-level filesystem jail plus default-deny egress — and
`srt` is a **hard prerequisite** (fail-closed): without it, delegation is
refused with an actionable error rather than silently falling back to the
provider CLIs' own sandbox flags.

## Prerequisites

- **`srt` (required)** — pinned version, per ADR-001 Decision 5:

  ```bash
  npm install -g @anthropic-ai/sandbox-runtime@0.0.66
  ```

  Platform dependencies: macOS needs `sandbox-exec` (Seatbelt, built in);
  Linux needs `bubblewrap` and `socat` (`apt-get install bubblewrap socat`).
  If `srt` or a platform dependency is missing, `consult.sh` exits `2`; if the
  wrapper fails to start, it exits `3` — in both cases with an error that says
  what to install. Platforms other than macOS and Linux are refused with exit
  `2`. There is no silent degradation (ADR-001 Decision 6).

  > `srt --version` reports the CLI's internal version (1.0.0 for the 0.0.66
  > npm release), so the pin is enforced at install time via the exact-version
  > command above, not at runtime.

## Supported providers

| Provider | Binary | Headless invocation | Native sandbox (defense-in-depth under `srt`) |
|---|---|---|---|
| OpenAI Codex CLI | `codex` | `codex exec` | `--sandbox read-only` |
| Google Antigravity CLI | `agy` | `agy --sandbox -p` (print mode) | `--sandbox` (sandbox with terminal restrictions); `-p` only makes it non-interactive |

> Antigravity CLI replaced Gemini CLI, which stopped serving individual-tier
> requests on June 18, 2026.

Providers are detected at runtime — install one or both:

- **Codex**: `npm install -g @openai/codex`, then `codex login`
- **Antigravity**: `curl -fsSL https://antigravity.google/cli/install.sh | bash`, then run `agy` once to log in (or set `ANTIGRAVITY_API_KEY`)

## Usage

```
/second-opinion                  # review current branch vs main, all available providers
/second-opinion staged           # review staged changes
/second-opinion 123              # review PR #123
/second-opinion codex            # only ask codex
/second-opinion antigravity main..HEAD
```

## How it works

1. `scripts/consult.sh list` detects which provider CLIs are installed (and
   warns if `srt` is missing).
2. Claude builds the diff for the requested scope (PR, branch, staged, or range)
   and fills in the prompt template at `assets/prompts/review.md`.
3. Each provider runs headlessly and read-only in a parallel background task via
   `scripts/consult.sh [--tier consult] <provider> <prompt-file>` — each
   subprocess enclosed by `srt` with a per-run generated settings file: egress
   limited to that provider's API endpoints, writes confined to the run temp
   dir and the provider's own state dir, known credential paths deny-read, and
   a scrubbed environment (only `HOME`/`PATH`/`TMPDIR`/`TERM` plus the one
   provider credential var pass through).
4. Claude cross-checks the findings against the code, highlights consensus
   between providers, drops factually wrong findings, and reports — it never
   applies fixes on its own.

### Privilege tiers

`consult.sh` accepts `--tier <consult|act-sandboxed|act-full>` (ADR-001
tier ladder):

- **`consult`** (default) — read-only review. No writes. This is the tier the
  `/second-opinion` review skill uses.
- **`act-sandboxed`** (opt-in, issue #77 PR 3) — read-write, but writes are
  confined to an **isolated scope**: a dedicated detached git worktree of the
  current repo, created under the run temp dir. The `srt` jail's write-allowlist
  (worktree + run dir writable; the primary repo tree, the shared `.git`
  object/ref store, `$HOME`, and credential paths denied) is the load-bearing
  enforcement; codex additionally runs `--sandbox workspace-write` and
  antigravity `--sandbox --mode accept-edits` as defense-in-depth. The worktree
  scopes only the **writable** surface — it is not a read barrier: reads are
  default-allow and reach the provider (ADR-001 risk #7). Two intentional
  consequences: the worktree is checked out at the committed **HEAD**, so
  **uncommitted** changes in the primary tree are not part of what the delegate
  sees or acts on; and because the shared `.git` store is deliberately not
  writable, the delegate produces **working-tree edits only** and cannot
  `git commit`/index-write inside the worktree — the orchestrator reviews the
  printed worktree diff and integrates it like an external PR. After the
  delegate finishes, `consult.sh` prints that diff (the work product) and runs a
  **write-scope tripwire**: it re-checks the primary tree, any sibling
  worktrees, and the shared git dir's `hooks/`+`config` (a hook/config plant is
  a code-exec vector otherwise invisible to `git status`), surfacing any escape
  as a loud `WRITE-SCOPE-TRIPWIRE` line. The tripwire is post-hoc detection with
  known blind spots (ignored-file appends, nested ignored paths, out-of-worktree
  writes, non-hook/config `.git` internals) — the `srt` jail is the actual
  enforcement. The worktree is torn down with the run dir on every exit path.
  Requires being inside a git repository (exit 1 otherwise).
- **`act-full`** (planned: issue #77 PR 4, gated behind explicit per-invocation
  approval) — **refused with exit 1** today.

No tier is ever silently downgraded to `consult` or silently granted (ADR-001
Decision 4).

> **Provider write support (honest limits).** The `act-sandboxed` write path was
> verified end-to-end against **real `srt` + a codex-shaped delegate**: in-scope
> worktree writes land in the worktree, and an out-of-scope write into the
> source repo is blocked by the jail ("Operation not permitted"), leaving the
> primary tree clean. Antigravity's non-interactive write behaviour under
> `--sandbox --mode accept-edits` was **not** exercised against a real logged-in
> `agy` here; the flags follow ADR-001 Decision 3, and the `srt` write-allowlist
> is the enforcement regardless of provider, but if `agy` blocks or prompts on
> edits in print mode, prefer codex for `act-sandboxed`.

Exit codes: `0` success, `1` usage error or refused tier, `2` required
component not installed (provider CLI, `srt`, or an srt platform dependency),
`3` component failed (provider run, or the `srt` wrapper failed to start).

## Configuration

| Env var | Purpose |
|---|---|
| `SECOND_OPINION_CODEX_MODEL` | Override the Codex model |
| `SECOND_OPINION_ANTIGRAVITY_MODEL` | Override the Antigravity model (see `agy models`) |
| `SECOND_OPINION_ALLOWLIST_DIR` | Override the egress-allowlist extension directory (default: `${XDG_CONFIG_HOME:-~/.config}/second-opinion/allowlist.d`) |

## Security / limitations

The `srt` jail restricts **writes, egress, and terminal access**: writes are
confined to the run temp dir and the provider's own state dir; network egress
is default-deny with a per-provider domain allowlist; and known credential
paths (`~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.gnupg`, shell histories, OS
keychain stores) are deny-read. The providers' native sandbox flags
(`codex --sandbox read-only`, `agy --sandbox`) stay on underneath as
defense-in-depth. None of this stops the external model from *reading* other
files the jail exposes and transmitting their contents back to its provider
as part of the review — reads are default-allow outside the deny list.

The privilege and exposure model for this plugin is specified in
[ADR-001: Task-delegation substrate, privilege tiers, and exposure model](../../docs/adr/001-task-delegation-privilege-model.md);
its risk register is the honest statement of what these boundaries do and do
not guarantee.

### Egress allowlists

The plugin ships tight per-provider allowlists
(`assets/allowlists/<provider>.txt`) containing provider API endpoints only —
no registries, no `github.com`, no shared CDNs (broad entries reopen
exfiltration paths). To extend one, create
`${XDG_CONFIG_HOME:-~/.config}/second-opinion/allowlist.d/<provider>.txt`
(one domain per line, `#` comments) — never edit the shipped files. Every run
with a non-default allowlist reports the extra domains on stderr, so a
widened egress surface is never invisible (ADR-001 Decision 7).

### Provider-specific relaxations (antigravity)

Verified against real CLIs, `agy` needs two loud, narrowly-scoped relaxations
that codex does not get:

- **Keychain carve-out**: `agy` stores its OAuth token in the macOS login
  keychain, which the deny-read policy blocks. An `allowRead` carve-out
  re-permits exactly `~/Library/Keychains/login.keychain-db`, reported on
  stderr at invocation time (the ADR-001 Decision 5 mechanism).
- **trustd access** (`enableWeakerNetworkIsolation`): `agy` is a Go binary;
  on macOS, Go TLS verification goes through the `trustd` service, which the
  Seatbelt profile blocks by default. Re-allowing it is a documented srt
  trade-off (a potential exfiltration vector through trustd) accepted for
  this provider only, plus `allowLocalBinding` for agy's internal loopback
  language server.

Three consequences to keep in mind:

- **Your filesystem is readable.** Both providers run against your working
  directory and are told they may read surrounding files for context. If that
  directory (or its ancestors) holds secrets, credentials, or private data, a
  provider can read and transmit them. Run second-opinion from repos you are
  comfortable sharing with the external CLI's provider, and avoid it on trees
  containing unrelated secrets.
- **Diffs are attacker-controllable.** The diff is embedded verbatim into the
  prompt. A hostile diff (e.g. from an untrusted PR) can attempt prompt
  injection to steer the external agent into reading and exfiltrating files.
  Do not review untrusted diffs against a filesystem you would not hand to the
  provider directly. The jail limits writes, egress, and terminal access — not
  reads or disclosure of what is readable.
- **Antigravity prompts are visible in the process list.** `agy` has no
  stdin-prompt mode, so the full prompt — including the embedded diff — is
  passed as a command-line argument and is readable via `ps` by other local
  users for the duration of the run. On shared/multi-user machines, avoid the
  antigravity provider for diffs containing anything sensitive (codex reads
  its prompt from stdin and is not affected).

Note on Antigravity output: some `agy` versions can return sparse output in
print mode (a short planning trace instead of findings) if the prompt sends the
agent off exploring the filesystem. The prompt template treats the embedded diff
as self-contained to reduce this; if a run still comes back thin, re-run or fall
back to Codex.

## Roadmap: consult → delegate

This plugin is generalizing into a privilege-tiered **task-delegation**
primitive (issue
[#77](https://github.com/benjamcalvin/bootstraps/issues/77)). The tier
interface and the default read-only `consult` tier (issue #77 PR 2) and the
opt-in `act-sandboxed` tier — writes confined to an isolated git worktree,
enforced by the `srt` write-allowlist and verified by the write-scope tripwire
(issue #77 PR 3) — are implemented (this version). The gated `act-full` tier
(explicit per-invocation approval, issue #77 PR 4) is **not** yet — requesting
it is refused, never silently downgraded or escalated. The substrate choice,
tier ladder, enforcement mechanisms, and honest limits are recorded in
[ADR-001](../../docs/adr/001-task-delegation-privilege-model.md). The
`/second-opinion` review skill uses only the read-only `consult` tier and does
not act on your repo.

## Adding a provider

`scripts/consult.sh` isolates all per-CLI quirks. To add one: add its name to
`PROVIDERS`, map it in `binary_for()`, add a tight provider-endpoint
allowlist at `assets/allowlists/<provider>.txt`, and write a
`run_<provider>()` that reads a prompt file, invokes the CLI through
`run_srt` (never directly), and prints the delegate output to stdout. Select
the sandbox/write mode by `$TIER`: read-only at `consult` (e.g.
`codex --sandbox read-only`, `agy --sandbox`) and worktree-scoped write at
`act-sandboxed` (e.g. `codex --sandbox workspace-write`,
`agy --sandbox --mode accept-edits`, cwd = the worktree). The `srt`
write-allowlist is the actual enforcement regardless of tier. Never pair
`agy --sandbox` with `--dangerously-skip-permissions` — that combo
auto-approves the sandbox-bypass prompt (ADR-001 Decision 3, forbidden at
every tier).
