# Testing Standards

**Status:** Draft
**Last Updated:** {DATE}

## Overview

Testing standards for {PROJECT_NAME}. Tests are first-class artifacts — they protect behavior, prevent regressions, and serve as living documentation of how the system works.

## Guardrail Policy

### Behavior-First Coverage

- Do not add tests that only restate implementation details.
- Add tests that protect behavior contracts, invariants, and expected failure modes.
- If a change is purely structural with no behavior change, existing tests may be sufficient.

### Change-Impact Requirement

For each non-trivial code change, include at least one of:

1. A test that fails without the change and passes with it (bug fix or new behavior), or
2. A focused regression test for the highest-risk behavior touched by the change.

If no test changes are needed, the PR description must explain why current tests already cover the risk.

## Test Organization

### File Placement

{Describe where unit tests, integration tests, and test helpers live relative to source files. Conventions vary by language — co-located vs. separate test directories, naming patterns, etc.}

### Separation of Unit and Integration Tests

Unit tests run fast with no external dependencies. Integration tests hit real services (databases, APIs, etc.) and run separately.

{Describe how your project separates unit from integration tests — build tags, directory conventions, test runner configuration, etc.}

## Test Naming

### Convention

Test names should communicate the function under test and the scenario being verified.

{Specify your naming pattern. Examples:}
{- `Test<Function>_<scenario>` (Go)}
{- `describe('Function', () => { it('should <behavior>', ...) })` (JS/TS)}
{- `test_<function>_<scenario>` (Python)}

### Readability

- Names should read as documentation — a failing test name should tell you what broke.
- Use descriptive scenarios, not implementation details: `handles_empty_input` not `checks_length_zero`.

## Assertions

{Specify your assertion library and conventions. Remove or adapt the example below.}

### When to Use Hard vs. Soft Assertions

- **Hard assertions** (fail immediately) — Use for setup steps and preconditions. If setup is broken, remaining checks are meaningless.
- **Soft assertions** (continue on failure) — Use for the actual checks under test. Seeing all failures at once is more useful than stopping at the first one.

## Integration Tests

### External Dependencies

{Describe how integration tests manage external dependencies — test containers, in-memory substitutes, shared test environments, etc.}

### Test Isolation

Tests must not depend on execution order or shared mutable state. Each test sets up its own preconditions and cleans up after itself (or uses isolated namespaces).

## Mock and Stub Strategy

### When to Mock

- **Mock:** Cross-module dependencies (e.g., a handler test mocks the data layer).
- **Don't mock:** Same-module collaborators, pure functions, value objects.
- **Never mock:** The thing you're testing.

### Mock Tooling

{Specify your mocking tool/approach and where generated mocks live.}

## Test Data

### Synthetic Data Only

All test data must be obviously synthetic. Never use real names, emails, phone numbers, or personal data in tests.

### Factory Functions / Fixtures

{Describe your approach to test data — factory functions, fixture files, builders, etc. Specify where shared test utilities live.}

## Coverage

### Policy

Test coverage must not decrease. New code ships with new tests.

### Priority

Critical paths carry the highest coverage expectations:

{List your project's critical paths in priority order, e.g.:}
{1. Data layer — data correctness is paramount}
{2. Domain logic — business rules and validation}
{3. API layer — contract correctness}

## Running Tests

```bash
{command to run unit tests}
{command to run integration tests}
{command to run with coverage}
```

---

## Related Documents

### Standards
- [Code Conventions](code-conventions.md) — Coding standards these tests enforce
- [PR Standards](pr-standards.md) — PR conventions and sizing guidelines

### Operational
- {Link to development setup guide}
