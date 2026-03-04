# Code Conventions

**Status:** Draft
**Last Updated:** {DATE}

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

## Documentation

- All public/exported symbols must have documentation comments.
- Internal code: document when the purpose isn't obvious from the name and context.
- Prefer self-documenting code over comments that restate what the code does.

## Function Signatures

{Specify conventions for function signatures. Common topics:}
{- Parameter ordering (context first? options last?)}
{- Return value conventions (error last? result objects?)}
{- When to use options/builder patterns vs. explicit parameters}

---

## Related Documents

### Standards
- [Testing Standards](testing-standards.md) — Testing patterns and conventions
- [PR Standards](pr-standards.md) — PR conventions enforced in review

### Operational
- {Link to development setup guide}
