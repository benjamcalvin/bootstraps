# Documentation Strategy

**Version:** 1.0

**This document defines mandatory documentation standards. All contributors — human and AI — must follow these rules when creating or modifying documentation. Consistency is not optional; it ensures documentation remains navigable, maintainable, and valuable as a shared context layer.**

## Purpose

This strategy defines how we organize and maintain documentation in {PROJECT_NAME}. These are **rules, not guidelines** — following this strategy faithfully is critical to maintaining documentation quality across a collaborative human + AI agent project.

## Core Principles

1. **Living documents over proposals** — Specs evolve during implementation rather than being written once and frozen. Update when thinking changes, not when tasks complete.
2. **Modular over monolithic** — Split documents by concern, not by phase or role
3. **Linked where useful** — Link to related docs when the link helps a reader; none are required
4. **Concise over comprehensive** — Each document has a clear scope; prefer multiple focused docs
5. **Consistent over creative** — Follow established patterns and structures. Consistency makes documentation predictable and navigable
6. **AI-readable** — Docs are frequently consumed by AI agents during development. Be succinct, specific, and clear. Prefer shorter, well-named documents. Don't overexplain, but make requirements and decisions explicit
7. **Single source of truth** — Default to keeping each piece of information in exactly one authoritative location; other documents link to it rather than repeating it. When in doubt about where something belongs, consult the Content Classification table. When you find duplication, prefer consolidating to the authoritative location and replacing duplicates with cross-references.

## Document Taxonomy

```
{DOCS_LOCATION}
├── AGENTS.md           # THIS FILE (documentation strategy)
├── CLAUDE.md           # @AGENTS.md wrapper
{TAXONOMY_ENTRIES}├── CHANGELOG.md        # Release history — what changed between versions
```

{TAXONOMY_DESCRIPTIONS}
### Changelog

**CHANGELOG.md** tracks notable changes across releases using [Keep a Changelog](https://keepachangelog.com) format. Organized by version with sections: Added, Changed, Deprecated, Removed, Fixed, Security. Updated as part of every version bump.

## Content Classification

| Content Type | Belongs In | Anti-Pattern |
|---|---|---|
{CLASSIFICATION_ROWS}| Release notes, version history | Changelog | Putting change history in specs or ADRs |

**Rule of thumb:** "Why do we build this?" → vision. "What is the shared model of the system — its concepts, vocabulary, boundaries, and invariants?" → spec. "Why did we decide?" → ADR. "How do I do X?" → guide. "When/how to build it?" → plan. "What changed?" → changelog.

## Frontmatter Requirements

Every document must have frontmatter:

```markdown
**Status:** Draft | Partial | Complete
```

**Additional fields by document type:**

| Type | Additional Fields |
|---|---|
{FRONTMATTER_ROWS}
## Writing for AI Readability

Documentation is frequently consumed by AI agents during development. Optimize for:

**Clarity:**
- State requirements explicitly, not implicitly
- Use precise technical terminology
- Avoid ambiguous pronouns (prefer specific nouns)
- Make decisions clear (not just discussed)
- When a decision is deferred, say so with the reason

**Structure:**
- Well-named sections that match their content
- Frontmatter with status and metadata
- Clear hierarchical organization
- Explicit relationships between concepts

**Brevity:**
- Shorter, focused documents over long comprehensive ones
- Remove redundancy and fluff
- Don't overexplain simple concepts
- Link to details rather than repeating them
- Keep documents focused on one concern so agents don't waste context window loading irrelevant content. If a document serves multiple audiences or covers multiple concerns, split it.

**Anti-patterns:**
- Long narrative explanations when a bulleted list suffices
- Repeating context already in linked documents
- Vague statements like "we should consider" (instead: decided yes/no, or defer with reason)
- Burying key decisions in prose

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

**Split when:**
- Document exceeds 1,000 lines
- Covers multiple distinct concerns
- Different readers need different sections
- Table of contents has >8 top-level sections

Refer to code by path or symbol name, never with a line reference, which goes stale.

## Instruction Files (AGENTS.md + CLAUDE.md)

Every directory with documentation should have an `AGENTS.md` file as the primary instruction source, with a minimal `CLAUDE.md` wrapper for Claude Code compatibility.

### Architecture

- **AGENTS.md** — Primary instruction file (universal, works with all AI tools)
- **CLAUDE.md** — Minimal wrapper containing only `@AGENTS.md` import plus Claude-specific features

This dual-file approach enables compatibility with multiple AI coding tools (Claude Code, Codex, Cursor, Copilot) while preserving tool-specific features.

### Structure

**AGENTS.md (primary):**
```markdown
[Brief description of directory purpose]

## Contents
- List of files/subdirectories with one-line descriptions

## Key Principles
- Critical rules that apply to this directory's content

## Reading Order (if applicable)
- Recommended sequence for understanding the content
```

**CLAUDE.md (wrapper):**
```markdown
@AGENTS.md
```

**Important:** The `@` import syntax is relative to the file containing the import. Since CLAUDE.md and AGENTS.md are always co-located, the import is always `@AGENTS.md`.

### When to Create

Create an `AGENTS.md` + `CLAUDE.md` pair when:
- Directory has 3+ files
- Content has a specific reading order
- Key principles need emphasis
- Directory serves a distinct purpose

## Maintenance Rules

**When code changes:**
1. Update the relevant spec in the same PR (if a concept, term, or invariant changed)
2. Fix links that the change breaks

**When documents get long:**
1. Identify distinct concerns within the document
2. Create focused docs for each concern
3. Create an overview doc that links to details
4. Archive original with redirect notice

**Living document principle:**
- Update when thinking changes, not when tasks complete
- Specs are the shared conceptual model: product specs as users see it, technical specs as builders see it, one vocabulary; they omit implementation the code already shows and change in the same PR as any change to a concept, term, or invariant
- Plans are ephemeral; archive or delete when complete

**Common violations to avoid:**
- Adding "Next Steps" or task lists to specs or ADRs
- Mixing planning (roadmaps, tasks) into specs
- Leaving broken links when moving or splitting documents

---

## Execution Tracking

For tracking implementation work (tasks, milestones, delivery), use **git issues and pull requests** rather than plan documents. Issues provide better visibility, traceability, and integration with your development workflow.

- Create issues for discrete units of work tied to specs
- Link PRs to issues for automatic progress tracking
- Use `/implement` to plan and execute work against your specs

Plan documents (`docs/plans/`) are available as an opt-in module for cases where a narrative execution plan adds value beyond issue tracking, but issues + PRs are the recommended default.
