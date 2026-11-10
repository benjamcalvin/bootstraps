# Documentation Strategy

**Version:** 1.0

How we organize and maintain documentation in {PROJECT_NAME}. These are rules, not guidelines: every contributor, human or AI, follows them when creating or changing docs.

## Core Principles

1. **Living documents over proposals** — Specs evolve during implementation. Update when thinking changes, not when tasks complete.
2. **Modular over monolithic** — Split documents by concern, not by phase or role.
3. **Linked where useful** — Link to related docs when the link helps a reader; none are required.
4. **Concise over comprehensive** — Each document has one clear scope; prefer several focused docs.
5. **Consistent over creative** — Follow the established patterns so docs stay predictable.
6. **AI-readable** — Agents read these docs constantly. Be succinct and specific, and make requirements and decisions explicit.
7. **Single source of truth** — Keep each fact in one authoritative place and link to it instead of repeating it. When in doubt, consult Content Classification.

## Document Taxonomy

```
{DOCS_LOCATION}
├── AGENTS.md           # THIS FILE (documentation strategy)
├── CLAUDE.md           # @AGENTS.md
{TAXONOMY_ENTRIES}├── CHANGELOG.md        # Release history — what changed between versions
```

{TAXONOMY_DESCRIPTIONS}
### CHANGELOG.md

Notable changes per release in [Keep a Changelog](https://keepachangelog.com) format (Added, Changed, Deprecated, Removed, Fixed, Security). Updated with every version bump.

## Content Classification

| Content Type | Belongs In | Anti-Pattern |
|---|---|---|
{CLASSIFICATION_ROWS}| Release notes, version history | Changelog | Putting change history in specs or ADRs |

**Rule of thumb:** "Why do we build this?" → vision. "What is the shared model of the system — its concepts, vocabulary, boundaries, and invariants?" → spec. "Why did we decide?" → ADR. "How do I do X?" → guide. "When/how to build it?" → plan. "What changed?" → changelog.

## Frontmatter Requirements

Every document starts with:

```markdown
**Status:** Draft | Partial | Complete
```

| Type | Additional Fields |
|---|---|
{FRONTMATTER_ROWS}
## Writing for AI Readability

- State requirements and decisions explicitly; when a decision is deferred, say so and why.
- Use precise terms and specific nouns, not ambiguous pronouns.
- Name sections for their content.
- Prefer a bulleted list to narrative prose.
- Link to details rather than repeating them.
- Never write "we should consider": decide, or defer with a reason.
- Refer to code by path or symbol name, never by line number, which goes stale.

## Length Guidelines

Maximums, not goals. Write as little as the content needs.

| Document Type | Max Lines |
|---|---|
| ADR | one page (about 40) |
| Product Spec | 1,000 |
| Technical Spec | 1,000 |
| Standards | 700 |
| Vision | 800 |
| Guide | 800 |
| Plan | — |
| Changelog | — |

**Line budgets only ever decrease, and they apply to instruction files only.** The maximums above are ceilings for other docs, not enforced limits.

**Split when** a document exceeds 1,000 lines, covers more than one concern, serves readers who need different sections, or has more than eight top-level sections.

## Instruction Files

`AGENTS.md` is the instruction file every agent reads. `CLAUDE.md` exists for Claude Code and imports it.

- **Every `CLAUDE.md` imports `@AGENTS.md`.** Claude-specific lines go below the import, which is relative to the importing file.
- **Each `AGENTS.md` stays under 200 lines**, including this one and the project root's.
- **Only what an agent cannot infer from the code:** commands, gotchas, conventions that differ from defaults, and pointers to docs. Leave out anything a directory listing or the code already shows.
- **No per-folder index files.** Docs subfolders get no `AGENTS.md`, `CLAUDE.md`, or Contents list; the folder names and this file's taxonomy are the index.

## Maintenance Rules

**When code changes:**
1. Update the relevant spec in the same PR when a concept, term, or invariant changes.
2. Fix links that the change breaks.

**When a document gets long:** split it by concern, link the parts from a short overview, and leave a redirect where the original lived.

**Living documents:**
- Specs are the shared conceptual model: product specs as users see it, technical specs as builders see it, in one vocabulary. They omit implementation the code already shows.
- Plans are ephemeral; archive or delete them when complete.

**Common violations:**
- "Next Steps" or task lists in specs or ADRs
- Roadmaps or tasks mixed into specs
- Broken links after moving or splitting documents
- An instruction file growing past its line budget

## Execution Tracking

Track implementation work (tasks, milestones, delivery) in git issues and pull requests, not plan documents. Create issues tied to specs, link PRs to them, and use `/implement` to plan and execute the work. Plan documents are an opt-in module for when a narrative execution plan adds value beyond issue tracking.
