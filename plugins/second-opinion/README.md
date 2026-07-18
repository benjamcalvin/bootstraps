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
| Google Antigravity CLI | `agy` | `agy -p` (print mode) | print mode denies non-allowlisted tool calls |

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

## Adding a provider

`scripts/consult.sh` isolates all per-CLI quirks. To add one: add its name to
`PROVIDERS`, map it in `binary_for()`, and write a `run_<provider>()` that reads
a prompt file and prints the review text to stdout. Keep it read-only.
