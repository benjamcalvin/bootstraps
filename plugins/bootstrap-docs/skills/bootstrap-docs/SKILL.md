---
name: bootstrap-docs
description: >-
  Set up comprehensive AI-readable documentation strategy.
  Creates AGENTS.md, specs, ADRs, guides, plans, standards, and research templates.
  Triggers: /bootstrap-docs, set up documentation, create docs structure, bootstrap docs
argument-hint: "[adr|specs|plans|guides|vision|standards|research|all]"
context: fork
agent: general-purpose
allowed-tools: Read, Glob, Bash(cat *), Bash(find *)
license: MIT
metadata:
  version: "1.3.0"
  tags: ["docs", "documentation", "strategy", "scaffolding"]
  author: benjamcalvin
  standards-sub-types: ["testing", "code", "pr"]
---

# Bootstrap Documentation Strategy

Set up a comprehensive, AI-readable documentation strategy for this project.

## Context

- Skill source directory: $SKILL_DIR
- Arguments: $ARGUMENTS

Before starting, gather context by running these commands:
1. Check for existing preferences: `cat .bootstraps-preferences 2>/dev/null || echo "NO_PREFERENCES_FILE"`
2. Check for existing docs structure: `find . -name "AGENTS.md" -not -path "./.git/*" -not -path "./node_modules/*" 2>/dev/null | head -20 || echo "NONE_FOUND"`

## Instructions

This skill runs six phases to set up project documentation. It is **re-runnable** — it checks what exists and only creates what's missing.

**Argument handling:**
- No arguments or `all`: run all phases for all enabled modules
- Specific module (e.g., `adr`, `specs`, `plans`, `guides`, `vision`, `standards`, `research`): run only Phase 0 (preferences) then the phases relevant to that module (directory, AGENTS.md, starter doc)
- Multiple modules can be comma-separated: `adr,specs`

**Template files** are in the skill's `assets/` directory at `$SKILL_DIR/assets/`. Read them on demand with the Read tool only when that phase needs them — e.g., `Read $SKILL_DIR/assets/adr-template.md`. Do NOT read all templates upfront; load each template only when creating the corresponding document.

---

### Phase 0: Preferences & Strategy-First Setup

Check if `.bootstraps-preferences` exists (from the context-gathering step above).

**If NO_PREFERENCES_FILE (fresh repo):**

On a fresh repo, the documentation strategy must be created **before** module selection. The strategy document defines the taxonomy and classification that inform which modules the user should enable.

1. Ask the user for:
   - **Project name** (used in templates and headings)
   - **Docs location** (default: `docs/`)
2. Create a minimal `.bootstraps-preferences` in the project root with only project metadata and the strategy module:

   ```yaml
   project_name: "{name}"
   docs_location: "docs/"

   modules:
     strategy:
       status: pending
   ```

3. Create the `{docs_location}/` root directory.
4. **Create the strategy document now** — execute the full Phase 2 logic (see below) to create `{docs_location}/AGENTS.md` and `{docs_location}/CLAUDE.md`. Since no modules have been selected or declined yet, include all modules in the taxonomy. Update strategy status to `enabled` in preferences.
5. **Present module selection informed by the strategy.** Now that the strategy document exists, present the user with module choices and reference the taxonomy it defines:

   > "Your documentation strategy has been created at `{docs_location}/AGENTS.md`. It defines these documentation categories:
   >
   > - **vision/** — WHY: project vision, philosophy, strategy
   > - **specs/** — WHAT: design documents (product, technical, standards)
   > - **adr/** — WHY (decisions): immutable architecture decision records
   > - **guides/** — HOW: step-by-step operational instructions
   > - **research/** — WHAT (learned): compiled LLM research for future reference
   > - **plans/** — WHEN: active execution work, ephemeral
   >
   > Which modules would you like to enable? (default: all except `plans`, which is opt-in)"

   Ask which modules to enable (default: all except `plans`). Modules: `adr`, `specs` (with sub-options: `product`, `technical`, `standards`), `plans`, `guides`, `vision`, `research`.
   If standards enabled, ask which standard types to include (default: all): `testing`, `code`, `pr`.

6. Update `.bootstraps-preferences` with the user's module selections. Modules the user selects start as `pending`. Modules the user declines are `declined`.

   The full preferences file now looks like:
   ```yaml
   project_name: "{name}"
   docs_location: "docs/"

   modules:
     strategy:
       status: enabled
       files:
         - docs/AGENTS.md
         - docs/CLAUDE.md
     adr:
       status: pending
     specs:
       status: pending
       product:
         status: pending
       technical:
         status: pending
     standards:
       status: pending
       testing:
         status: pending
       code:
         status: pending
       pr:
         status: pending
     plans:
       status: declined
     guides:
       status: pending
     vision:
       status: pending
     research:
       status: pending
   ```

   **Status values:**
   - `pending` — user wants this module, not yet created
   - `enabled` — module is active, files have been created (listed in `files`)
   - `declined` — user explicitly declined this module (don't ask again on re-runs)

   **After files are created** (in Phases 1–5), update each module's entry:
   ```yaml
   adr:
     status: enabled
     files:
       - docs/adr/AGENTS.md
       - docs/adr/CLAUDE.md
       - docs/adr/001-first-decision.md
   ```

7. Confirm the preferences with the user before proceeding to Phase 1.

**If preferences exist:** Parse them from the Context above. Confirm with the user: "Found existing preferences for {project_name}. Proceeding with docs at {docs_location}." Check for any `pending` modules — these are work the user previously requested but hasn't completed yet. Check for any `declined` modules — don't offer these again unless the user explicitly asks. If strategy status is `pending` (interrupted previous run), create the strategy document (Phase 2 logic, including all modules in the taxonomy) before proceeding. If preferences contain no module entries besides `strategy` (indicating the previous run was interrupted before module selection), present module selection as in step 5 of the fresh-repo flow above. Move to Phase 1.

**If a specific module argument was provided:** Only that module matters — but preferences must still exist for project name and docs_location. If the module was previously `declined`, reset it to `pending` (the user is explicitly requesting it now).

---

### Phase 1: Directory Structure

Using the preferences, create the directory tree. **Only process modules with status `pending`** — skip `enabled` (already done) and `declined` (user said no). Also skip anything that already exists on disk.

For the docs location (e.g., `docs/`), create:
- `{docs_location}/` (root docs directory)
- `{docs_location}/adr/` (if adr is pending)
- `{docs_location}/specs/` (if any specs sub-module is pending)
- `{docs_location}/specs/product/` (if product is pending)
- `{docs_location}/specs/technical/` (if technical is pending)
- `{docs_location}/specs/standards/` (if any standards type is pending)
- `{docs_location}/plans/` (if plans is pending)
- `{docs_location}/guides/` (if guides is pending)
- `{docs_location}/vision/` (if vision is pending)
- `{docs_location}/research/` (if research is pending)

For each directory created, also create the `AGENTS.md` + `CLAUDE.md` pair (these are populated in later phases — create empty files as placeholders if the content phase hasn't run yet).

**Update `.bootstraps-preferences`** after this phase: for each module that got directories created, add the directory and placeholder files to its `files` list (but keep status as `pending` — it becomes `enabled` once the content phases fill them in).

Report what was created and what was skipped.

---

### Phase 2: Master Strategy (AGENTS.md)

**Skip guard:** If strategy status is already `enabled` in preferences (e.g., it was created during Phase 0 on a fresh repo), skip this phase entirely.

Create `{docs_location}/AGENTS.md` using the strategy template from `$SKILL_DIR/assets/strategy-template.md`.

Read the template, then customize it:

1. Replace `{PROJECT_NAME}` with the project name from preferences
2. Replace `{DATE}` with today's date
3. Replace `{DOCS_LOCATION}` with the configured docs location
4. Build the `{TAXONOMY_ENTRIES}` block — include modules with status `pending` or `enabled` (not `declined`):
   - If vision not declined: `├── vision/             # WHY — project vision, philosophy, strategy`
   - If specs not declined: `├── specs/` with sub-entries for product/, technical/, standards/ as applicable
   - If adr not declined: `├── adr/                # WHY (decisions) — immutable architecture decision records`
   - If guides not declined: `├── guides/             # HOW (do) — step-by-step operational instructions`
   - If research not declined: `├── research/           # WHAT (learned) — compiled LLM research for future reference`
   - If plans not declined: `└── plans/              # WHEN — active execution work, ephemeral`
5. Build `{TAXONOMY_DESCRIPTIONS}` — include the description section for each non-declined module (vision, specs, adr, guides, research, plans). Use the descriptions from the strategy template but generalized for {PROJECT_NAME}.
6. Build `{CLASSIFICATION_ROWS}` — include only rows for non-declined modules
7. Build `{FRONTMATTER_ROWS}` — include only rows for non-declined document types:
   - ADR: `**Decision:** Accepted | Superseded | Deprecated` and `**Superseded By:** ADR-NNN`
   - Product Spec: `**Owner:** name`
   - Technical Spec: `**Owner:** name`
   - Guide: `**Audience:** contributor | operator | consumer`
   - Plan: `**Target Date:** YYYY-MM-DD`
   - Research: `**Topic:** area of research`

**Ask the user:** "Use defaults for the master strategy, or customize interactively?" Defaults fill in all the template fields with sensible generic values. Interactive walks through each major section for the user's input.

Also create `{docs_location}/CLAUDE.md` containing only:
```
@AGENTS.md
```

**Update `.bootstraps-preferences`:** Set `strategy` status to `enabled` and record the files created.

---

### Phase 3: Sub-Directory AGENTS.md Files

For each module with status `pending` or `enabled` (not `declined`), create the AGENTS.md in its directory if it doesn't already have content. Each follows this pattern:

```markdown
{Brief description of directory purpose}

## Contents
- (none yet — add entries as documents are created)

## Key Principles
- {principles specific to this doc type}

## Related Documents
- [Documentation Strategy](../AGENTS.md) — Rules governing all documentation
```

**Module-specific content:**

**adr/AGENTS.md:**
- Purpose: "Architecture Decision Records — immutable records of significant design decisions with context and rationale."
- Principles: ADRs are append-only (never modify accepted ADRs; create new ones to supersede). Naming: `NNN-short-title.md`. Sequential numbering, never reuse. Every ADR needs frontmatter: Status, Last Updated, Decision. Target: 200–600 lines (max 800).

**specs/AGENTS.md:**
- Purpose: "Specifications — design documents describing what the system is and should be (target state)."
- Principles: Specs describe the vision/authoritative design. "Living" means update when the design changes, not when tasks complete. Never add task lists or roadmaps to specs.

**specs/product/AGENTS.md:**
- Purpose: "Product specifications — what the system does from a consumer perspective."
- Principles: Define the what and why from the user's perspective. API contracts, data model semantics, feature definitions belong here. Every product spec needs: Status, Last Updated, Owner.

**specs/technical/AGENTS.md:**
- Purpose: "Technical specifications — how the system is built from an engineering perspective."
- Principles: Architecture, database schema, security implementation, infrastructure. Data model specs here describe structure (schema, indexes). Every technical spec needs: Status, Last Updated, Owner.

**specs/standards/AGENTS.md:**
- Purpose: "Standards — rules and conventions for how we work."
- Principles: Standards prescribe conventions. "What is the standard?" goes here. "How do I follow it?" goes in guides/. Every standards doc needs: Status, Last Updated.
- Note: Standards are organized by type. The default types are:
  - **Testing standards** — test organization, naming, assertions, coverage, mocking, CI integration
  - **Code conventions** — project layout, naming, error handling, logging, formatting, documentation
  - **PR standards** — branch naming, PR titles, descriptions, sizing, review, stacking
- Each type has its own template with opinionable defaults. Users select which types to adopt during setup and customize them for their stack.

**plans/AGENTS.md:**
- Purpose: "Plans — active execution work, how and when to build what the specs describe."
- Principles: Plans are ephemeral — they become git history when complete. Answer "how to get from current state to spec?" Never put planning content in specs or ADRs. Every plan needs: Status, Last Updated, Target Date.

**guides/AGENTS.md:**
- Purpose: "Guides — step-by-step operational instructions for specific tasks."
- Principles: Guides are instructional — tell you how to do something, not why it's designed that way. Every guide needs: Status, Last Updated, Audience.

**research/AGENTS.md:**
- Purpose: "Research — compiled findings from LLM research sessions, preserved for easy future reference."
- Principles: Research docs capture what was learned during investigation — technology evaluations, API explorations, competitive analysis, library comparisons, debugging deep-dives. They are reference material, not decisions (those go in ADRs) or design (those go in specs). Name files descriptively: `auth-library-comparison.md`, `postgres-jsonb-performance.md`. Include sources and applicability notes so future readers know when the research might be stale. Every research doc needs: Status, Last Updated, Topic.

**vision/AGENTS.md:**
- Purpose: "Vision documents — the WHY behind {PROJECT_NAME}."
- Principles: Capture project philosophy, strategic direction, foundational principles. Mostly stable, update infrequently. Provides context that frames every design decision. Every vision doc needs: Status, Last Updated.

For each directory, also create a `CLAUDE.md` containing only `@AGENTS.md`.

**Adjust relative links** based on directory depth. For sub-directories under specs/, the link to the strategy doc is `../../AGENTS.md`.

**Update `.bootstraps-preferences`:** For each module that got its AGENTS.md populated, add those files to the module's `files` list.

---

### Phase 4: Starter Documents

For each module with status `pending` (not `declined` or already `enabled`), **ask the user** if they want to create a starter document.

Present three options:
- **Defaults**: Create from the template with minimal placeholders filled in (project name, today's date, sequential number for ADRs). Fast path.
- **Interactive**: Walk through each section of the template, asking what content to fill in. Slower but tailored.
- **Skip**: Don't create a starter doc for this module. Set its status to `declined` in preferences.

**Templates to use** (read from `$SKILL_DIR/assets/`):

| Module | Template | Default filename |
|--------|----------|-----------------|
| adr | `adr-template.md` | `{docs_location}/adr/001-first-decision.md` |
| specs/product | `product-spec-template.md` | `{docs_location}/specs/product/overview.md` |
| specs/technical | `technical-spec-template.md` | `{docs_location}/specs/technical/architecture.md` |
| standards/testing | `standards-testing-template.md` | `{docs_location}/specs/standards/testing-standards.md` |
| standards/code | `standards-code-template.md` | `{docs_location}/specs/standards/code-conventions.md` |
| standards/pr | `standards-pr-template.md` | `{docs_location}/specs/standards/pr-standards.md` |
| plans | `plan-template.md` | `{docs_location}/plans/initial-plan.md` |
| guides | `guide-template.md` | `{docs_location}/guides/development-setup.md` |
| vision | `vision-template.md` | `{docs_location}/vision/philosophy.md` |
| research | `research-template.md` | `{docs_location}/research/initial-research.md` |

**Additional reference templates** (not tied to a module — available for manual use):
- `changelog-template.md` — [Keep a Changelog](https://keepachangelog.com) format. Use when setting up a project CHANGELOG.md at the repository root.

For **defaults**: replace `{PROJECT_NAME}` with project name, `{DATE}` with today's date, `{NUMBER}` with `001` for ADRs, `{TITLE}` with a sensible generic title, `{OWNER}` with "TBD", `{TARGET_DATE}` with "TBD". Leave section body content as template placeholders.

**Standards sub-types:** When creating standards starter docs, create one file per enabled standard type (testing, code, pr). Each uses its own template. Ask about all enabled types together — e.g., "Create starter standards docs? (testing, code, pr) — Defaults / Interactive / Skip". If the user picks Interactive, walk through each type separately. The `{placeholders in braces}` in standards templates mark sections the user should customize for their language/framework — during Interactive mode, ask what to fill in for each.

For **interactive**: present each section header and ask the user what to fill in. Build the document incrementally.

After creating each starter doc, update the corresponding directory's `AGENTS.md` Contents section to list the new file.

**Update `.bootstraps-preferences`:** For each module where a starter doc was created, set status to `enabled` and add the file to `files`. For modules the user skipped, set status to `declined`.

---

### Phase 5: Root Integration

Check if the project has a root `AGENTS.md` (in the project root, not the docs directory).

**If it exists:** Offer to add a Documentation section with a link to the docs strategy:
```markdown
## Documentation
- [Documentation Strategy]({docs_location}/AGENTS.md) — How we organize and maintain documentation
```

**If it doesn't exist:** Offer to create a minimal root `AGENTS.md`:
```markdown
# {PROJECT_NAME}

## Documentation
- [Documentation Strategy]({docs_location}/AGENTS.md) — How we organize and maintain documentation
```

Also ensure a root `CLAUDE.md` exists. If creating one, content is `@AGENTS.md`. If one exists, offer to add `@AGENTS.md` if it's not already referenced.

**Update `.bootstraps-preferences`:** Record any root-level files created under the `strategy` module's `files` list.

---

### Phase 6: Summary

Report to the user:

1. **Created** (`enabled`) — list all files and directories that were created this run
2. **Skipped** (`enabled`) — list anything that was already enabled from a previous run
3. **Declined** — list modules the user declined (can be re-enabled later with `/bootstrap-docs {module}`)
4. **Implementation sequence** — present this ordered workflow as actionable next steps:

   > **Recommended implementation sequence:**
   >
   > Work through your documentation in this order. Each step builds on the previous one.
   >
   > 1. **Documentation Strategy** — If strategy status is `enabled`: "✅ Complete. Establishes the rules for how all docs are organized, classified, and maintained." If `pending`: "Establish the rules for how all docs are organized, classified, and maintained. Ensure it's linked from your root `AGENTS.md`/`CLAUDE.md` so agents discover it automatically."
   > 2. **Vision** — Articulate the product vision, philosophy, and success metrics
   > 3. **Product Specs** — Detail features, user stories, and requirements from the consumer perspective
   > 4. **Tech Specs** — Design the technical architecture and implementation approach
   > 5. **Standards** — Establish coding standards and engineering practices for the team
   >
   > Skip any step whose module you declined. For execution tracking (tasks, milestones, delivery), use git issues and PRs — run `/implement` to plan and track work against your specs.
   >
   > Run `/bootstrap-docs {module}` to add individual modules later (including previously declined ones).

**Audit mode (re-run on existing project):**

When the skill detects an existing `.bootstraps-preferences` file, after reporting the Created/Skipped/Declined lists above, also report the implementation sequence progress:

> **Sequence progress:**
>
> For each step in the implementation sequence (Documentation Strategy → Vision → Product Specs → Tech Specs → Standards), check whether the corresponding module has status `enabled` with at least one non-placeholder file. Report:
> - ✅ **Documentation Strategy** — complete (files: docs/AGENTS.md)
> - ✅ **Vision** — complete (files: docs/vision/philosophy.md)
> - ⬜ **Product Specs** — not started
> - ⬜ **Tech Specs** — not started
> - ⬜ **Standards** — not started
>
> Suggest the user work on the first incomplete step next.
