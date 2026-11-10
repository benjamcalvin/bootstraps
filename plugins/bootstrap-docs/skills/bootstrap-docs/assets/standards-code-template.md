# Code Conventions

**Status:** Draft

## Overview

Prescriptive coding conventions for {PROJECT_NAME}. These are rules, not suggestions. Code review should enforce them.

## Project Layout

```
{Describe your project's directory structure and the purpose of each top-level directory.}
```

**Rules:**

- {Entry point / main directories contain only wiring and startup, no business logic.}
- {Define your module boundary — what is internal vs. public.}
- {Generated code policy — regenerate, never hand-edit. Commit or gitignore.}
- Package/module organization: group by concern, not by layer.

## Naming Conventions

| Context | Convention | Example |
|---------|-----------|---------|
| Files | {your convention} | {example} |
| Functions/Methods | {your convention} | {example} |
| Variables | {your convention} | {example} |
| Constants | {your convention} | {example} |
| Types/Classes | {your convention} | {example} |

### General Rules

- Prefer descriptive names over terse abbreviations — clarity matters more than brevity.
- Boolean variables: use positive names (`enabled`, `valid`), not negative (`disabled`, `invalid`).
- No stuttering — if the module/package name provides context, don't repeat it in the symbol name.

## Error Handling

### Principles

- **Wrap errors with context.** Every error that crosses a function boundary should gain context about what operation failed.
- **Fail fast on unrecoverable errors.** Startup/initialization failures should halt the process with a clear message.
- **Return errors, don't panic/throw from library code.** Exceptions/panics are reserved for truly unrecoverable programmer errors.

### Patterns

{Specify your error handling patterns with code examples. Topics to cover:}
{- How to wrap/chain errors}
{- Sentinel/known errors vs. typed errors}
{- How callers should check error types}

## Logging

### Structured Logging

Use structured logging (key-value pairs), not string interpolation.

```
{Example of a good structured log call in your language/framework}
```

### Log Levels

| Level | Use For | Example |
|-------|---------|---------|
| Debug | Developer troubleshooting, flow tracing | "resolver called", "cache miss" |
| Info | Operational events operators want to see | "server started", "batch complete" |
| Warn | Recoverable problems that may need attention | "retry attempt 3", "deprecated API" |
| Error | Failures needing investigation | "database connection lost" |

### Privacy

- Never log secrets (tokens, keys, passwords).
- Never log personal data (names, emails, phone numbers) unless the project explicitly requires it and has appropriate protections.
- Log entity IDs, counts, and durations — not content.

## Import / Dependency Ordering

{Specify your import ordering convention. Common pattern:}

1. Standard library / built-in modules
2. Third-party dependencies
3. Internal / project modules

{Separated by blank lines. Enforced by formatter/linter.}

## Dependency Injection

- Explicit constructor injection. No service locators, no global state, no hidden registrations.
- Interfaces defined by the consumer, not the implementer (where the language supports this).
- All wiring visible in one place (entry point / composition root).

## Configuration

- Environment variables (or config files) as primary source.
- Validate all required config at startup — fail fast with clear messages.
- No global config variables. Pass config through constructors.
- Secrets from env vars or secret managers, never from files in the repo.

## Formatting and Linting

- Automated formatter enforced in CI. No exceptions.
- Linter runs in CI. No lint warnings in committed code.

{Specify your formatter and linter tools:}
```bash
{format command}
{lint command}
```

## Comments

> Add no comments. Exceptions: a constraint imposed from outside the codebase (link its source), a guarantee that cannot be tested, `TODO(#N)`, tool directives, and comments a tool turns into output. If code must stay a certain way, write a test named after that guarantee instead of a comment. Put the reason for a change in the commit body and the PR. Leave existing comments alone unless your change makes them false.

| Allowed | Banned |
| --- | --- |
| A constraint imposed from outside the codebase: a hardware quirk, an upstream bug (with its URL), a protocol or vendor rule | Restating the code, including a doc comment that paraphrases a name or signature |
| A guarantee that cannot be tested, stated beside the code it binds | References to your own tracker or milestones ("for #131", "M7:", "see the PR") |
| `TODO(#N)` pointing at an open issue | History: "previously", "changed from", "no longer" |
| Comments a tool turns into output: CLI help, OpenAPI annotations, doctests, API docs of an externally published package | Step narration: "Step 3:", "Now we..." |
| Tool directives and license headers | Commented-out code; a TODO without an issue |

Exported symbols need no doc comment unless a tool turns it into output.

### Enforcement

{Adapt to your stack; remove tools you do not use.}

- Python: ruff `ERA` (commented-out code) and `TD003` (TODO must link an issue).
- Go: turn the revive `exported` rule off in applications; keep it on only for externally published packages.
- Any language: `docs-check` scans the comment lines a change adds for tracker references (`#123`), step labels (`Step 3:`) and history words (`previously`, `no longer`), and fails on a match. Install it with `/bootstrap-docs docs-check`; do not write a second scan.

## Function Signatures

{Specify conventions for function signatures. Common topics:}
{- Parameter ordering (context first? options last?)}
{- Return value conventions (error last? result objects?)}
{- When to use options/builder patterns vs. explicit parameters}

---
