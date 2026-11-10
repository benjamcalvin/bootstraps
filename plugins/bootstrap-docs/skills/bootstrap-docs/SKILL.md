---
name: bootstrap-docs
description: >-
  Set up comprehensive AI-readable documentation strategy.
  Creates AGENTS.md, specs, ADRs, guides, plans, standards, and research templates.
  `migrate` upgrades a docs tree made by bootstrap-docs 1.x; `docs-check` installs the drift checker.
  Triggers: /bootstrap-docs, set up documentation, create docs structure, bootstrap docs
argument-hint: "[adr|specs|plans|guides|vision|standards|research|all|migrate|docs-check]"
context: fork
agent: general-purpose
allowed-tools: Read, Glob, Bash(cat *), Bash(find *)
license: MIT
metadata:
  version: "2.1.0"
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
- Specific module (e.g., `adr`, `specs`, `plans`, `guides`, `vision`, `standards`, `research`): run only Phase 0 (preferences) then the phases relevant to that module (directory, strategy-doc section, starter doc)
- Multiple modules can be comma-separated: `adr,specs`
- `migrate`: run only Migrate Mode (below), which upgrades an existing docs tree; skip Phases 0–6
- `docs-check`: run only docs-check Install (below); skip Phases 0–6

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
   > - **specs/** — WHAT: the shared conceptual model (concepts, vocabulary, boundaries, invariants) plus standards
   > - **adr/** — WHY (decisions): immutable architecture decision records
   > - **guides/** — HOW: step-by-step operational instructions
   > - **research/** — WHAT (learned): compiled LLM research for future reference
   > - **plans/** — WHEN: active execution work, ephemeral
   >
   > Which modules would you like to enable? (default: all except `plans` and `adr`, which are opt-in)"

   Ask which modules to enable (default: all except `plans` and `adr`, which are opt-in and default to declined). Modules: `adr`, `specs` (with sub-options: `product`, `technical`, `standards`), `plans`, `guides`, `vision`, `research`.
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
       status: declined
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

Docs subfolders get no `AGENTS.md`, `CLAUDE.md`, or Contents list. The strategy doc describes every folder (Phase 3), so the folder names are the only index.

Report what was created and what was skipped.

---

### Phase 2: Master Strategy (AGENTS.md)

**Skip guard:** If strategy status is already `enabled` in preferences (e.g., it was created during Phase 0 on a fresh repo), skip this phase entirely.

Create `{docs_location}/AGENTS.md` using the strategy template from `$SKILL_DIR/assets/strategy-template.md`.

Read the template, then customize it:

1. Replace `{PROJECT_NAME}` with the project name from preferences
2. Replace `{DOCS_LOCATION}` with the configured docs location
3. Build the `{TAXONOMY_ENTRIES}` block — include modules with status `pending` or `enabled` (not `declined`):
   - If vision not declined: `├── vision/             # WHY — project vision, philosophy, strategy`
   - If specs not declined: `├── specs/` with sub-entries for product/, technical/, standards/ as applicable
   - If adr not declined: `├── adr/                # WHY (decisions) — immutable architecture decision records`
   - If guides not declined: `├── guides/             # HOW (do) — step-by-step operational instructions`
   - If research not declined: `├── research/           # WHAT (learned) — compiled LLM research for future reference`
   - If plans not declined: `└── plans/              # WHEN — active execution work, ephemeral`
4. Build `{TAXONOMY_DESCRIPTIONS}` — one module section per non-declined module, written as Phase 3 describes.
5. Build `{CLASSIFICATION_ROWS}` — include only rows for non-declined modules
6. Build `{FRONTMATTER_ROWS}` — include only rows for non-declined document types:
   - ADR: `**Decision:** Accepted | Superseded | Deprecated` and `**Superseded By:** ADR-NNN`
   - Product Spec: `**Owner:** name` and `**Covers:** code paths`
   - Technical Spec: `**Owner:** name` and `**Covers:** code paths`
   - Guide: `**Audience:** contributor | operator | consumer`
   - Plan: `**Target Date:** YYYY-MM-DD`
   - Research: `**Topic:** area of research`

**Ask the user:** "Use defaults for the master strategy, or customize interactively?" Defaults fill in all the template fields with sensible generic values. Interactive walks through each major section for the user's input.

The generated strategy doc stays under 200 lines. Tighten wording rather than exceed it.

Also create `{docs_location}/CLAUDE.md` containing only:
```
@AGENTS.md
```

**Update `.bootstraps-preferences`:** Set `strategy` status to `enabled` and record the files created.

---

### Phase 3: Module Sections

Each module's purpose and rules live in one section of `{docs_location}/AGENTS.md`, under Document Taxonomy. For each module with status `pending` or `enabled` (not `declined`), make sure the strategy doc has that section, adding it when it is missing (for example, a module enabled after the strategy doc was created). Each section is a `### {folder}/` heading and at most three lines (each a single source line), generalized for {PROJECT_NAME}. Write the entries below as three lines or fewer, shortening them as needed:

- **vision/** — The WHY behind {PROJECT_NAME}: philosophy, strategic direction, foundational principles. Mostly stable; frames every design decision. Needs: Status.
- **specs/** — The shared conceptual model of the system: concepts, vocabulary, boundaries, invariants (target state). Each spec opens with a Glossary, pins each invariant with a test named after it, names the code it describes in `Covers:`, and changes in the same PR as any change to a concept, term, or invariant.
  It omits implementation the code already shows and never holds task lists or roadmaps. Needs: Status, Owner, Covers (not for standards).
  Sub-folders: `product/` (the model as users see it), `technical/` (as builders see it: components, data model, invariants, in the product spec's vocabulary), `standards/` (one doc per type: testing, code, PR; "what is the standard?" here, "how do I follow it?" in guides/).
- **adr/** — Immutable records of significant decisions. Append-only: supersede, never edit, an accepted ADR. `NNN-short-title.md`, numbers never reused. One page; write one only when a decision is hard to reverse, spans components, or would leave a future reader asking why. The agent drafts, a human accepts. Needs: Status, Decision.
- **guides/** — Step-by-step instructions for a task: how to do it, not why it is designed that way. Needs: Status, Audience.
- **research/** — Findings from investigations (evaluations, comparisons, deep-dives) kept for reference; not decisions (ADRs) or the model (specs). Descriptive filenames; cite sources and say when the findings might go stale. Needs: Status, Topic.
- **plans/** — How and when to get from the current state to the spec. Ephemeral: they become git history when complete. Needs: Status, Target Date.

Keep the strategy doc under 200 lines after adding a section.

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

**Every `CLAUDE.md` imports `@AGENTS.md`.** When a root `AGENTS.md` exists or is being created, ensure a root `CLAUDE.md` exists; when creating one, its content is `@AGENTS.md`. Otherwise (such as when the user declined the root `AGENTS.md`), create no root `CLAUDE.md`. Then find every `CLAUDE.md` in the project, skipping `.git/`, `.claude/`, `node_modules/`, build-output directories (such as `dist/` and `build/`), and vendored dependencies. When one lacks an `@AGENTS.md` line, add `@AGENTS.md` after any YAML frontmatter (as the first line when there is none). If no `AGENTS.md` sits beside it, create one first: ask the user whether to move the file's tool-neutral content into it or start it empty. Never add the import where the sibling `AGENTS.md` neither exists nor is being created, such as when the user declined the root `AGENTS.md`; leave that `CLAUDE.md` unchanged and report it.

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
   > 3. **Product Specs** — The shared model as users see it (glossary, concepts, behaviors, invariants)
   > 4. **Tech Specs** — The shared model as builders see it (components, boundaries, data model, invariants)
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

---

### Migrate Mode (`migrate` argument)

Upgrade a docs tree created by bootstrap-docs 1.x to the current rules. Migrate proposes; the user decides. **Never delete a file without explicit confirmation.**

1. **Locate the docs.** Read `docs_location` from `.bootstraps-preferences`, or ask the user when there is no preferences file (default: `docs/`).
2. **Detect.** Collect every old-style item below. Check each one; report "none found" for a check that finds nothing.

   | Old-style item | How to detect | Proposed change |
   |---|---|---|
   | Per-folder index pair | An `AGENTS.md` or `CLAUDE.md` in any subfolder of `{docs_location}` | Move any rule the strategy doc lacks into that module's section (Phase 3), then delete the pair |
   | Contents list | A `## Contents` section in a file under `{docs_location}` | Remove the section |
   | Last Updated | A `Last Updated` line in a file under `{docs_location}` | Remove the line |
   | Related Documents | A `## Related Documents` section in a file under `{docs_location}` | Remove the section, or keep it as optional links; ask per file |
   | Length target | A target line-count table or a `Target: N lines` note under `{docs_location}` | Remove the target |
   | Missing import | A `CLAUDE.md` anywhere in the project without an `@AGENTS.md` line | Add the import as Phase 5 describes |
   | Outdated strategy doc | `{docs_location}/AGENTS.md` at 200 lines or more, or still prescribing per-folder index files, Contents lists, or length targets | **REWRITE** it from the current template and Phase 3 sections, carrying over the project's own rules |

3. **Propose.** Show one numbered list: each item's file, what was found, and the exact change. Mark every deletion as **DELETE**, and every rebuild or overwrite of an existing file (such as the strategy doc) as **REWRITE**. Fold an item into another that already covers it, such as a Contents list inside a pair being deleted or anything inside a strategy doc being rebuilt. Change nothing yet.
4. **Confirm.** Ask the user which items to apply: all, none, or a list of numbers. Confirm each **DELETE** and each **REWRITE** separately, naming the file, exactly as for a deletion; a blanket "all" never applies a **DELETE** or **REWRITE** item. Before confirming a **REWRITE**, show the project-specific rules that will carry over into the rebuilt file. Delete or overwrite only files the user confirms by name. When an answer is unclear, ask again rather than guess.
5. **Apply** only the confirmed items, leaving every other file untouched. Remove deleted files from `.bootstraps-preferences` `files` lists.
6. **Report** applied, skipped, and declined items. A re-run proposes only what is left.
7. **Offer docs-check.** When the project has no `docs-check.toml`, offer docs-check Install (below).

---

### docs-check Install (`docs-check` argument)

`docs-check` catches docs drift with lint: broken links and paths, missing tasks, instruction-file rules and line budgets, and tracker, step, or history comments a change adds. It needs Python 3.11+ and nothing else.

1. **Copy `$SKILL_DIR/assets/docs-check.py` into the project** as `scripts/docs-check.py`. Every snippet below uses that path.
2. **Create `docs-check.toml` with the current baseline:** run `python3 scripts/docs-check.py --write-baseline` from the project root. Existing errors go into the baseline and instruction files already over budget get their current length, so old debt never blocks a change. The baseline only shrinks: new violations fail, and later runs of `--write-baseline` only drop fixed entries.
3. **Print the CI and pre-commit snippets** for the user, and offer to add `python3 scripts/docs-check.py` to the project's lint task:

   ```yaml
   # .pre-commit-config.yaml
   repos:
     - repo: local
       hooks:
         - id: docs-check
           name: docs-check
           entry: python3 scripts/docs-check.py
           language: system
           pass_filenames: false
           always_run: true
   ```

   ```yaml
   # GitHub Actions job steps
   - uses: actions/checkout@v4
     with:
       fetch-depth: 0
   - run: python3 scripts/docs-check.py --base origin/${{ github.base_ref || github.event.repository.default_branch }}
   ```

4. **Report** the baseline size; each entry is existing debt to fix later.
