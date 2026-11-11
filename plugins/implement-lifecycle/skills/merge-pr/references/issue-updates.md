# Issue Updates on Merge

Read this reference when the PR references `#N` (closing or partial references).

From the PR title and description, find closing references (`Closes`/`Fixes`/`Resolves #N`, case-insensitive) and partial references (`Relates to`/`Part of #N`). For each, `gh issue view <N> --json state,title` and comment:

## Closing References (`Closes #N`, `Fixes #N`, `Resolves #N`)

```markdown
## Delivered

**PR:** #<pr-number> — <PR title>

### Changes delivered
- <bullet summary>

This PR fully addresses this issue.
```

## Partial References (`Part of #N`, `Relates to #N`)

```markdown
## Progress Update

**PR:** #<pr-number> — <PR title>

### Changes delivered
- <bullet summary>

### Remaining work
<Remaining items, or "See issue description for remaining scope.">
```
