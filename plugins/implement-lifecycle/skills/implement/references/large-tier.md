# Large-Tier Specialist Triggers & Convergence Audit

Read this reference when orchestrating a PR classified as **Large** tier.

## Specialist Path Triggers (Step A)

For Large tier, invoke `review-general` plus `review-docs` and each specialist whose trigger fires:
- `review-security` — auth, secrets, crypto, sandbox, or permission paths change
- `review-correctness` — migrations, concurrency primitives, or CI/deploy configuration change
- `review-architecture` — a new top-level module/package or public interface is added
- `review-testing` — production code changes without corresponding test changes

## Convergence Audit after Round 2 (Step E)

After round 2 on Large tier:
Map remaining findings and review-added changes to acceptance criteria, with finding DENSITY per sub-problem across rounds. If findings mainly concern review-introduced architecture, stop before round 3, request human direction, and recommend bounded simplification or removal.
