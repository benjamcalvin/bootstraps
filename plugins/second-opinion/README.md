# second-opinion

Consult external AI CLIs for an independent, headless code review of your
current changes. Claude builds one review prompt from your diff, fans it out to
every supported CLI installed on your machine, runs them read-only in parallel,
and synthesizes the findings into a single consolidated review with per-provider
attribution.

## Supported providers

| Provider | Binary | Headless invocation | Read-only mechanism |
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

1. `scripts/consult.sh list` detects which provider CLIs are installed.
2. Claude builds the diff for the requested scope (PR, branch, staged, or range)
   and fills in the prompt template at `assets/prompts/review.md`.
3. Each provider runs headlessly and read-only in a parallel background task via
   `scripts/consult.sh <provider> <prompt-file>`.
4. Claude cross-checks the findings against the code, highlights consensus
   between providers, drops factually wrong findings, and reports — it never
   applies fixes on its own.

## Configuration

| Env var | Purpose |
|---|---|
| `SECOND_OPINION_CODEX_MODEL` | Override the Codex model |
| `SECOND_OPINION_ANTIGRAVITY_MODEL` | Override the Antigravity model (see `agy models`) |

## Security / limitations

The sandbox mechanisms (`codex --sandbox read-only`, `agy --sandbox`) restrict
**writes and terminal access** — they stop a provider from modifying your repo
or running commands. They do **not** stop the external model from *reading*
files it has access to and transmitting their contents back to its provider as
part of the review.

The privilege and exposure model for this plugin — and for its planned
generalization (below) — is specified in
[ADR 0001: Task-delegation substrate, privilege tiers, and exposure model](../../docs/adr/0001-task-delegation-privilege-model.md).

Two consequences to keep in mind:

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
  provider directly. `--sandbox` limits writes/terminal, not reads or disclosure.

Note on Antigravity output: some `agy` versions can return sparse output in
print mode (a short planning trace instead of findings) if the prompt sends the
agent off exploring the filesystem. The prompt template treats the embedded diff
as self-contained to reduce this; if a run still comes back thin, re-run or fall
back to Codex.

## Roadmap: consult → delegate

This plugin's read-only consultation is planned to generalize into a
privilege-tiered **task-delegation** primitive (issue
[#77](https://github.com/benjamcalvin/bootstraps/issues/77)): the current
behavior becomes the default `consult` tier, with an opt-in `act-sandboxed`
tier (writes confined to an isolated git worktree) and a gated `act-full` tier
requiring explicit per-invocation approval — no code path silently escalates
privilege. The substrate choice, tier ladder, enforcement mechanisms, and
honest limits are recorded in
[ADR 0001](../../docs/adr/0001-task-delegation-privilege-model.md). Nothing in
the current version acts on your repo; today's plugin is the `consult` tier
only.

## Adding a provider

`scripts/consult.sh` isolates all per-CLI quirks. To add one: add its name to
`PROVIDERS`, map it in `binary_for()`, and write a `run_<provider>()` that reads
a prompt file and prints the review text to stdout. Keep it read-only.
