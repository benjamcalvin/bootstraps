---
name: bootstrap-docs
description: Set up a comprehensive, AI-readable documentation strategy in any project
argument-hint: "[adr|specs|plans|guides|vision|standards|all]"
---

# Bootstrap Documentation Strategy

Set up a comprehensive, AI-readable documentation strategy for this project.

## Context

- Skill source directory: !`echo "$SKILL_DIR"`
- Existing preferences: !`cat .bootstraps-preferences 2>/dev/null || echo "NO_PREFERENCES_FILE"`
- Current docs structure: !`find . -name "AGENTS.md" -not -path "./.git/*" -not -path "./node_modules/*" 2>/dev/null | head -20 || echo "NONE_FOUND"`
- Arguments: $ARGUMENTS

## Instructions

This skill runs six phases to set up project documentation. It is **re-runnable** — it checks what exists and only creates what's missing.

**Argument handling:**
- No arguments or `all`: run all phases for all enabled modules
- Specific module (e.g., `adr`, `specs`, `plans`, `guides`, `vision`, `standards`): run only Phase 0 (preferences) then the phases relevant to that module (directory, AGENTS.md, starter doc)
- Multiple modules can be comma-separated: `adr,specs`

**Template files** are in the skill's `examples/` directory (shown in Context above as `$SKILL_DIR`). Read them with the Read tool when needed — e.g., `Read $SKILL_DIR/examples/adr-template.md`.

---

### Phase 0: Preferences

Check if `.bootstraps-preferences` exists (see Context above).

**If NO_PREFERENCES_FILE:**
1. Ask the user for:
   - **Project name** (used in templates and headings)
   - **Docs location** (default: `docs/`)
   - **Which modules to enable** (default: all). Modules: `adr`, `specs` (with sub-options: `product`, `technical`, `standards`), `plans`, `guides`, `vision`
2. Create `.bootstraps-preferences` in the project root:
   ```yaml
   project_name: "{name}"
   docs:
     location: "docs/"
     strategy: { enabled: true }
     adr: { enabled: true }
     specs: { enabled: true, product: true, technical: true, standards: true }
     plans: { enabled: true }
     guides: { enabled: true }
     vision: { enabled: true }
   ```
3. Confirm the preferences with the user before proceeding.

**If preferences exist:** Parse them from the Context above. Confirm with the user: "Found existing preferences for {project_name}. Proceeding with docs at {location}." Move to Phase 1.

**If a specific module argument was provided:** Only that module matters — but preferences must still exist for project name and location.

---

### Phase 1: Directory Structure

Using the preferences, create the directory tree. **Skip anything that already exists.**

For the docs location (e.g., `docs/`), create:
- `{location}/` (root docs directory)
- `{location}/adr/` (if adr enabled)
- `{location}/specs/` (if any specs enabled)
- `{location}/specs/product/` (if product specs enabled)
- `{location}/specs/technical/` (if technical specs enabled)
- `{location}/specs/standards/` (if standards enabled)
- `{location}/plans/` (if plans enabled)
- `{location}/guides/` (if guides enabled)
- `{location}/vision/` (if vision enabled)

For each directory created, also create the `AGENTS.md` + `CLAUDE.md` pair (these are populated in later phases — create empty files as placeholders if the content phase hasn't run yet).

Report what was created and what was skipped.

---

### Phase 2: Master Strategy (AGENTS.md)

Create `{location}/AGENTS.md` using the strategy template from `$SKILL_DIR/examples/strategy-template.md`.

Read the template, then customize it:

1. Replace `{PROJECT_NAME}` with the project name from preferences
2. Replace `{DATE}` with today's date
3. Replace `{DOCS_LOCATION}` with the configured docs location
4. Build the `{TAXONOMY_ENTRIES}` block — include only enabled modules:
   - If vision enabled: `├── vision/             # WHY — project vision, philosophy, strategy`
   - If specs enabled: `├── specs/` with sub-entries for product/, technical/, standards/ as enabled
   - If adr enabled: `├── adr/                # WHY (decisions) — immutable architecture decision records`
   - If guides enabled: `├── guides/             # HOW (do) — step-by-step operational instructions`
   - If plans enabled: `└── plans/              # WHEN — active execution work, ephemeral`
5. Build `{TAXONOMY_DESCRIPTIONS}` — include the description section for each enabled module (vision, specs, adr, guides, plans). Use the descriptions from the strategy template but generalized for {PROJECT_NAME}.
6. Build `{CLASSIFICATION_ROWS}` — include only rows for enabled modules
7. Build `{FRONTMATTER_ROWS}` — include only rows for enabled document types:
   - ADR: `**Decision:** Accepted | Superseded | Deprecated` and `**Superseded By:** ADR-NNN`
   - Product Spec: `**Owner:** name`
   - Technical Spec: `**Owner:** name`
   - Guide: `**Audience:** contributor | operator | consumer`
   - Plan: `**Target Date:** YYYY-MM-DD`

**Ask the user:** "Use defaults for the master strategy, or customize interactively?" Defaults fill in all the template fields with sensible generic values. Interactive walks through each major section for the user's input.

Also create `{location}/CLAUDE.md` containing only:
```
@AGENTS.md
```

---

### Phase 3: Sub-Directory AGENTS.md Files

For each enabled module, create the AGENTS.md in its directory. Each follows this pattern:

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

**plans/AGENTS.md:**
- Purpose: "Plans — active execution work, how and when to build what the specs describe."
- Principles: Plans are ephemeral — they become git history when complete. Answer "how to get from current state to spec?" Never put planning content in specs or ADRs. Every plan needs: Status, Last Updated, Target Date.

**guides/AGENTS.md:**
- Purpose: "Guides — step-by-step operational instructions for specific tasks."
- Principles: Guides are instructional — tell you how to do something, not why it's designed that way. Every guide needs: Status, Last Updated, Audience.

**vision/AGENTS.md:**
- Purpose: "Vision documents — the WHY behind {PROJECT_NAME}."
- Principles: Capture project philosophy, strategic direction, foundational principles. Mostly stable, update infrequently. Provides context that frames every design decision. Every vision doc needs: Status, Last Updated.

For each directory, also create a `CLAUDE.md` containing only `@AGENTS.md`.

**Adjust relative links** based on directory depth. For sub-directories under specs/, the link to the strategy doc is `../../AGENTS.md`.

---

### Phase 4: Starter Documents

For each enabled module, **ask the user** if they want to create a starter document.

Present two options:
- **Defaults**: Create from the template with minimal placeholders filled in (project name, today's date, sequential number for ADRs). Fast path.
- **Interactive**: Walk through each section of the template, asking what content to fill in. Slower but tailored.
- **Skip**: Don't create a starter doc for this module.

**Templates to use** (read from `$SKILL_DIR/examples/`):

| Module | Template | Default filename |
|--------|----------|-----------------|
| adr | `adr-template.md` | `{location}/adr/001-first-decision.md` |
| specs/product | `product-spec-template.md` | `{location}/specs/product/overview.md` |
| specs/technical | `technical-spec-template.md` | `{location}/specs/technical/architecture.md` |
| specs/standards | `standards-template.md` | `{location}/specs/standards/conventions.md` |
| plans | `plan-template.md` | `{location}/plans/initial-plan.md` |
| guides | `guide-template.md` | `{location}/guides/development-setup.md` |
| vision | `vision-template.md` | `{location}/vision/philosophy.md` |

For **defaults**: replace `{PROJECT_NAME}` with project name, `{DATE}` with today's date, `{NUMBER}` with `001` for ADRs, `{TITLE}` with a sensible generic title, `{OWNER}` with "TBD", `{TARGET_DATE}` with "TBD". Leave section body content as template placeholders.

For **interactive**: present each section header and ask the user what to fill in. Build the document incrementally.

After creating each starter doc, update the corresponding directory's `AGENTS.md` Contents section to list the new file.

---

### Phase 5: Root Integration

Check if the project has a root `AGENTS.md` (in the project root, not the docs directory).

**If it exists:** Offer to add a Documentation section with a link to the docs strategy:
```markdown
## Documentation
- [Documentation Strategy]({location}/AGENTS.md) — How we organize and maintain documentation
```

**If it doesn't exist:** Offer to create a minimal root `AGENTS.md`:
```markdown
# {PROJECT_NAME}

## Documentation
- [Documentation Strategy]({location}/AGENTS.md) — How we organize and maintain documentation
```

Also ensure a root `CLAUDE.md` exists. If creating one, content is `@AGENTS.md`. If one exists, offer to add `@AGENTS.md` if it's not already referenced.

---

### Phase 6: Summary

Report to the user:

1. **Created** — list all files and directories that were created
2. **Skipped** — list anything that already existed and was left untouched
3. **Next steps** — suggest:
   - Fill in starter document placeholders
   - Create additional ADRs for key architectural decisions
   - Add content to spec templates as the project design evolves
   - Run `/bootstrap-docs {module}` to add individual modules later
