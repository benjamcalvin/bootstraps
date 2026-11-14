#!/bin/bash
# Validates all plugins in the marketplace
set -euo pipefail

# Always run from the repository root (where this script lives)
cd "$(dirname "${BASH_SOURCE[0]}")"

ERRORS=0
WARNINGS=0
CODEX_MARKETPLACE_VALID=false

echo "=== Bootstraps Plugin Validation ==="
echo ""

# Check .claude-plugin/marketplace.json exists and is valid JSON
if [ ! -f ".claude-plugin/marketplace.json" ]; then
  echo "ERROR: .claude-plugin/marketplace.json not found"
  ERRORS=$((ERRORS + 1))
else
  if ! jq . .claude-plugin/marketplace.json > /dev/null 2>&1; then
    echo "ERROR: .claude-plugin/marketplace.json is not valid JSON"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK: .claude-plugin/marketplace.json is valid JSON"
  fi
fi

echo ""

# Check .agents/plugins/marketplace.json exists and is valid JSON
if [ ! -f ".agents/plugins/marketplace.json" ]; then
  echo "ERROR: .agents/plugins/marketplace.json not found"
  ERRORS=$((ERRORS + 1))
else
  if ! jq . .agents/plugins/marketplace.json > /dev/null 2>&1; then
    echo "ERROR: .agents/plugins/marketplace.json is not valid JSON"
    ERRORS=$((ERRORS + 1))
  else
    if ! jq -e '
      type == "object" and
      (.plugins | type == "array") and
      all(.plugins[];
        type == "object" and
        (.name | type == "string" and length > 0) and
        (.source | type == "object") and
        (.source.source == "local") and
        (.source.path | type == "string" and startswith("./plugins/"))
      )
    ' .agents/plugins/marketplace.json > /dev/null 2>&1; then
      echo "ERROR: .agents/plugins/marketplace.json has an invalid marketplace shape or non-local plugin source"
      ERRORS=$((ERRORS + 1))
    else
      CODEX_MARKETPLACE_VALID=true
      echo "OK: .agents/plugins/marketplace.json is valid JSON with local plugin sources"

      while IFS= read -r codex_plugin_name; do
        if [ ! -d "plugins/$codex_plugin_name" ]; then
          echo "ERROR: Codex marketplace references missing plugin: $codex_plugin_name"
          ERRORS=$((ERRORS + 1))
        fi
      done < <(jq -r '.plugins[].name' .agents/plugins/marketplace.json)
    fi
  fi
fi

echo ""

if [ ! -f ".agents/plugins.json" ]; then
  echo "ERROR: .agents/plugins.json not found"
  ERRORS=$((ERRORS + 1))
else
  if ! jq . .agents/plugins.json > /dev/null 2>&1; then
    echo "ERROR: .agents/plugins.json is not valid JSON"
    ERRORS=$((ERRORS + 1))
  else
    if ! jq -e '
      type == "object" and
      (.entries | type == "array") and
      any(.entries[]; type == "object" and .path == "plugins")
    ' .agents/plugins.json > /dev/null 2>&1; then
      echo "ERROR: .agents/plugins.json missing required entries array pointing to plugins"
      ERRORS=$((ERRORS + 1))
    else
      echo "OK: .agents/plugins.json is valid JSON with plugins path"
    fi
  fi
fi

echo ""

target_plugins=()
if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    cleaned_arg="${arg#./}"
    cleaned_arg="${cleaned_arg#plugins/}"
    cleaned_arg="${cleaned_arg%/}"
    plugin_path="plugins/$cleaned_arg"
    if [ ! -d "$plugin_path" ]; then
      echo "ERROR: Plugin directory not found: $arg"
      ERRORS=$((ERRORS + 1))
    else
      target_plugins+=("$plugin_path/")
    fi
  done
else
  for plugin_path in plugins/*/; do
    target_plugins+=("$plugin_path")
  done
fi

# Validate each plugin
for plugin_dir in "${target_plugins[@]+"${target_plugins[@]}"}"; do
  [ -d "$plugin_dir" ] || continue
  plugin_name=$(basename "$plugin_dir")
  echo "--- Plugin: $plugin_name ---"

  # Reset per-plugin variables
  name=""
  desc=""
  version=""
  codex_version=""

  # Check plugin.json
  if [ ! -f "$plugin_dir/.claude-plugin/plugin.json" ]; then
    echo "  ERROR: Missing plugin.json"
    ERRORS=$((ERRORS + 1))
  else
    if ! jq . "$plugin_dir/.claude-plugin/plugin.json" > /dev/null 2>&1; then
      echo "  ERROR: plugin.json is not valid JSON"
      ERRORS=$((ERRORS + 1))
    else
      # Check required fields
      name=$(jq -r '.name // empty' "$plugin_dir/.claude-plugin/plugin.json")
      desc=$(jq -r '.description // empty' "$plugin_dir/.claude-plugin/plugin.json")
      version=$(jq -r '.version // empty' "$plugin_dir/.claude-plugin/plugin.json")

      if [ -z "$name" ]; then
        echo "  ERROR: plugin.json missing 'name'"
        ERRORS=$((ERRORS + 1))
      fi
      if [ -z "$desc" ]; then
        echo "  ERROR: plugin.json missing 'description'"
        ERRORS=$((ERRORS + 1))
      fi
      if [ -z "$version" ]; then
        echo "  ERROR: plugin.json missing 'version'"
        ERRORS=$((ERRORS + 1))
      fi

      if [ -n "$name" ] && [ -n "$desc" ] && [ -n "$version" ]; then
        echo "  OK: plugin.json has required fields (name=$name, version=$version)"
      fi
    fi
  fi

  if [ ! -f "$plugin_dir/.antigravity-plugin/plugin.json" ]; then
    echo "  ERROR: Missing .antigravity-plugin/plugin.json"
    ERRORS=$((ERRORS + 1))
  else
    if ! jq . "$plugin_dir/.antigravity-plugin/plugin.json" > /dev/null 2>&1; then
      echo "  ERROR: .antigravity-plugin/plugin.json is not valid JSON"
      ERRORS=$((ERRORS + 1))
    else
      agy_name=$(jq -r '.name // empty' "$plugin_dir/.antigravity-plugin/plugin.json")
      agy_version=$(jq -r '.version // empty' "$plugin_dir/.antigravity-plugin/plugin.json")
      agy_desc=$(jq -r '.description // empty' "$plugin_dir/.antigravity-plugin/plugin.json")
      agy_author=$(jq -r '.author.name // empty' "$plugin_dir/.antigravity-plugin/plugin.json")
      agy_license=$(jq -r '.license // empty' "$plugin_dir/.antigravity-plugin/plugin.json")

      if [ "$agy_name" != "$plugin_name" ]; then
        echo "  ERROR: Antigravity plugin name must match directory ($agy_name != $plugin_name)"
        ERRORS=$((ERRORS + 1))
      fi
      if [ -z "$agy_version" ] || [ -z "$agy_desc" ] || [ -z "$agy_author" ] || [ -z "$agy_license" ]; then
        echo "  ERROR: Antigravity plugin manifest is missing required metadata"
        ERRORS=$((ERRORS + 1))
      else
        echo "  OK: .antigravity-plugin/plugin.json has required metadata"
      fi
      if [ -n "$version" ] && [ "$agy_version" != "$version" ]; then
        echo "  ERROR: Version mismatch — Claude=$version, Antigravity=$agy_version"
        ERRORS=$((ERRORS + 1))
      elif [ -n "$version" ]; then
        echo "  OK: Claude and Antigravity versions in sync ($version)"
      fi
    fi
  fi

  # Check skills
  for skill_dir in "$plugin_dir"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    if [ -f "$skill_dir/SKILL.md" ]; then
      if head -1 "$skill_dir/SKILL.md" | grep -q "^---$"; then
        echo "  OK: skills/$skill_name/SKILL.md has frontmatter"
        if ! python3 - "$skill_dir/SKILL.md" <<'PYEOF'
import re, sys

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
if not lines or lines[0].strip() != "---":
    raise SystemExit("missing opening ---")
end_idx = None
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        end_idx = i
        break
if end_idx is None:
    raise SystemExit("missing closing ---")
fm_lines = lines[1:end_idx]
fm_text = "\n".join(fm_lines)
if not fm_text.strip():
    raise SystemExit("empty frontmatter")

try:
    import yaml  # type: ignore
    parsed = yaml.safe_load(fm_text)
    if not isinstance(parsed, dict) or not parsed.get("name"):
        raise SystemExit("frontmatter missing name")
except ModuleNotFoundError:
    pass

block_indent = None
has_name = False
for lineno, raw in enumerate(fm_lines, 2):
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    indent = len(raw) - len(raw.lstrip(" "))
    if block_indent is not None:
        if indent > block_indent:
            continue
        block_indent = None
    stripped = raw.lstrip()
    if stripped.startswith("- "):
        continue
    m = re.match(r'^([A-Za-z0-9_.-]+):(.*)$', stripped)
    if not m:
        raise SystemExit(f"line {lineno}: invalid YAML line: {raw}")
    key, val = m.group(1), m.group(2).strip()
    if key == "name" and indent == 0:
        has_name = True
    if val in (">", ">-", ">+", "|", "|-", "|+"):
        block_indent = indent
        continue
    if val == "" or (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")) or (val.startswith("[") and val.endswith("]")):
        continue
    if ": " in val or val.endswith(":"):
        raise SystemExit(f"line {lineno}: unquoted colon in YAML scalar value for '{key}'")
if not has_name:
    raise SystemExit("frontmatter missing top-level 'name'")
PYEOF
        then
          echo "  ERROR: skills/$skill_name/SKILL.md has invalid YAML frontmatter"
          ERRORS=$((ERRORS + 1))
        fi
      else
        echo "  WARN: skills/$skill_name/SKILL.md missing frontmatter delimiter"
        WARNINGS=$((WARNINGS + 1))
      fi

      # Check SKILL.md version sync for eponymous skill (skill name == plugin name)
      if [ "$skill_name" = "$plugin_name" ] && [ -n "$version" ]; then
        skill_version=$(sed -n '/^---$/,/^---$/p' "$skill_dir/SKILL.md" | grep 'version:' | head -1 | sed 's/.*version:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
        if [ -n "$skill_version" ] && [ "$skill_version" != "$version" ]; then
          echo "  ERROR: Version mismatch — plugin.json=$version, SKILL.md=$skill_version"
          ERRORS=$((ERRORS + 1))
        elif [ -n "$skill_version" ]; then
          echo "  OK: SKILL.md version in sync ($skill_version)"
        fi
      fi

      # Check line count
      lines=$(wc -l < "$skill_dir/SKILL.md")
      if [ "$lines" -gt 500 ]; then
        echo "  WARN: skills/$skill_name/SKILL.md is $lines lines (recommended: < 500)"
        WARNINGS=$((WARNINGS + 1))
      else
        echo "  OK: skills/$skill_name/SKILL.md is $lines lines"
      fi
    else
      echo "  WARN: skills/$skill_name/ exists but has no SKILL.md"
      WARNINGS=$((WARNINGS + 1))
    fi
  done

  # Check hooks.json if present
  if [ -f "$plugin_dir/hooks/hooks.json" ]; then
    if ! jq . "$plugin_dir/hooks/hooks.json" > /dev/null 2>&1; then
      echo "  ERROR: hooks/hooks.json is not valid JSON"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: hooks/hooks.json is valid JSON"
    fi
  fi

  # implement-lifecycle distributes canonical worker skills, not harness-specific
  # agent templates. Its explicit required skill inventory must retain non-empty
  # optional OpenAI metadata with explicit invocation policy.
  if [ "$plugin_name" = "implement-lifecycle" ]; then
    lifecycle_templates=""
    if [ -d "$plugin_dir/agents" ]; then
      lifecycle_templates=$(find "$plugin_dir/agents" -mindepth 1 -print -quit)
    fi
    if [ -n "$lifecycle_templates" ]; then
      echo "  ERROR: implement-lifecycle must not distribute named agent templates"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: No implement-lifecycle named agent templates distributed"
    fi

    # Instruction byte budget: every child re-reads these files, so growth is a cost regression.
    lifecycle_budget_total=46000
    lifecycle_budget_implement=12500
    lifecycle_bytes_total=$(cat "$plugin_dir"/skills/*/SKILL.md | wc -c | tr -d ' ')
    lifecycle_bytes_implement=$(wc -c < "$plugin_dir/skills/implement/SKILL.md" | tr -d ' ')
    if [ "$lifecycle_bytes_total" -gt "$lifecycle_budget_total" ] || [ "$lifecycle_bytes_implement" -gt "$lifecycle_budget_implement" ]; then
      echo "  ERROR: implement-lifecycle instructions exceed the byte budget (skills $lifecycle_bytes_total/$lifecycle_budget_total, implement $lifecycle_bytes_implement/$lifecycle_budget_implement)"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: implement-lifecycle instructions within byte budget (skills $lifecycle_bytes_total/$lifecycle_budget_total, implement $lifecycle_bytes_implement/$lifecycle_budget_implement)"
    fi

    if [ -e "$plugin_dir/skills/review-architecture" ] || [ -e "$plugin_dir/skills/review-testing" ] || [ -e "$plugin_dir/skills/implement/references/large-tier.md" ]; then
      echo "  ERROR: Retired v3 skills or references (review-architecture, review-testing, large-tier.md) must remain removed"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Retired review-architecture, review-testing, and large-tier.md are removed"
    fi

    # On-demand references are skill-local; every one a SKILL.md names must ship with that skill.
    lifecycle_refs_missing=false
    for lifecycle_ref_skill in "$plugin_dir"/skills/*/; do
      while IFS= read -r lifecycle_ref; do
        if [ ! -s "$lifecycle_ref_skill$lifecycle_ref" ]; then
          echo "  ERROR: $(basename "$lifecycle_ref_skill") references missing file: $lifecycle_ref"
          ERRORS=$((ERRORS + 1))
          lifecycle_refs_missing=true
        fi
      done < <(rg -o --no-filename 'references/[A-Za-z0-9._-]+\.md' "$lifecycle_ref_skill/SKILL.md" "$lifecycle_ref_skill"/references/*.md 2>/dev/null | sort -u)
    done
    if [ "$lifecycle_refs_missing" = false ]; then
      echo "  OK: Every skill-local reference named by an implement-lifecycle SKILL.md or reference exists"
    fi

    lifecycle_metadata_missing=false
    lifecycle_interface_section_missing=false
    lifecycle_explicit_invocation_missing=false
    lifecycle_skills=(
      implement-code implement-address review-general review-correctness
      review-security review-docs verify implement merge-pr pr-check
    )
    for lifecycle_skill in "${lifecycle_skills[@]}"; do
      lifecycle_skill_dir="$plugin_dir/skills/$lifecycle_skill"
      lifecycle_metadata="$lifecycle_skill_dir/agents/openai.yaml"
      if [ ! -d "$lifecycle_skill_dir" ]; then
        echo "  ERROR: implement-lifecycle is missing canonical skill directory: $lifecycle_skill"
        ERRORS=$((ERRORS + 1))
        lifecycle_metadata_missing=true
      elif [ ! -s "$lifecycle_metadata" ]; then
        echo "  ERROR: $lifecycle_skill is missing a non-empty agents/openai.yaml"
        ERRORS=$((ERRORS + 1))
        lifecycle_metadata_missing=true
      elif ! awk '
        /^interface:[[:space:]]*(#.*)?$/ { interface_line = NR; next }
        interface_line && /^[^[:space:]#]/ { exit !interface_content }
        interface_line && /^[[:space:]]+[^[:space:]#]/ { interface_content = 1 }
        END { exit !(interface_line && interface_content) }
      ' "$lifecycle_metadata"; then
        echo "  ERROR: $lifecycle_skill has no non-empty interface section in agents/openai.yaml"
        ERRORS=$((ERRORS + 1))
        lifecycle_interface_section_missing=true
      elif ! rg -Fq 'allow_implicit_invocation: false' "$lifecycle_metadata"; then
        echo "  ERROR: $lifecycle_skill must retain explicit-invocation policy in agents/openai.yaml"
        ERRORS=$((ERRORS + 1))
        lifecycle_explicit_invocation_missing=true
      fi
    done
    if [ "$lifecycle_metadata_missing" = false ] && [ "$lifecycle_interface_section_missing" = false ] && [ "$lifecycle_explicit_invocation_missing" = false ]; then
      echo "  OK: Every inventoried implement-lifecycle skill retains non-empty optional OpenAI metadata and explicit invocation policy"
    fi

    if rg -q 'named (subagent|worker)|preloaded (worker )?skill|reviewer agent adapter' \
      "$plugin_dir/skills/implement/SKILL.md" README.md; then
      echo "  ERROR: Lifecycle instructions still reference Claude Code named worker adapters"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Lifecycle instructions use generic skill-directed subagents"
    fi

    lifecycle_implement_skill="$plugin_dir/skills/implement/SKILL.md"
    lifecycle_mapping=$(awk '/^\| Phase \| Canonical skill \| Model tier \|$/,/^$/' "$lifecycle_implement_skill")
    lifecycle_mapping_invalid=false
    for lifecycle_worker in implement-code implement-address review-general review-correctness review-security review-docs verify; do
      mapping_count=$(printf '%s\n' "$lifecycle_mapping" | rg -Fc "\`$lifecycle_worker\`")
      if [ "$mapping_count" -ne 1 ]; then
        echo "  ERROR: Canonical lifecycle mapping must contain $lifecycle_worker exactly once (found $mapping_count)"
        ERRORS=$((ERRORS + 1))
        lifecycle_mapping_invalid=true
      fi
    done
    mapping_rows=$(printf '%s\n' "$lifecycle_mapping" | rg -c '^\| (Implement|Address|Review (general|correctness|security|docs)|Verify) \|')
    if [ "$mapping_rows" -ne 7 ]; then
      echo "  ERROR: Canonical lifecycle mapping must contain exactly seven worker rows (found $mapping_rows)"
      ERRORS=$((ERRORS + 1))
      lifecycle_mapping_invalid=true
    fi
    untiered_rows=$(printf '%s\n' "$lifecycle_mapping" | rg '^\| (Implement|Address|Review|Verify)' | rg -vc '\| `(balanced|frontier)`[^|]*\|$' || echo 0)
    if [ "$untiered_rows" -ne 0 ]; then
      echo "  ERROR: Every canonical lifecycle mapping row must carry a balanced or frontier tier (found $untiered_rows without)"
      ERRORS=$((ERRORS + 1))
      lifecycle_mapping_invalid=true
    fi
    for adapter_ref in \
      'references/adapter-claude.md' \
      'references/adapter-codex.md' \
      'references/adapter-agy.md' \
      'references/adapter-pi.md' \
      'references/adapter-generic.md'; do
      if ! rg -Fq "$adapter_ref" "$lifecycle_implement_skill"; then
        echo "  ERROR: implement must dispatch to adapter reference: $adapter_ref"
        ERRORS=$((ERRORS + 1))
        lifecycle_mapping_invalid=true
      fi
      if [ ! -s "$plugin_dir/skills/implement/$adapter_ref" ]; then
        echo "  ERROR: Missing adapter reference file: $adapter_ref"
        ERRORS=$((ERRORS + 1))
        lifecycle_mapping_invalid=true
      fi
    done
    claude_adapter_file="$plugin_dir/skills/implement/references/adapter-claude.md"
    if ! rg -Fq 'Use the implement-lifecycle:<skill> plugin skill' "$claude_adapter_file" || \
      ! rg -Fq '`model`' "$claude_adapter_file" || \
      ! rg -Fq '`"sonnet"` for `balanced`' "$claude_adapter_file" || \
      ! rg -q 'omit it \(inherit\) for `frontier`' "$claude_adapter_file" || \
      ! rg -Fq 'Never omit `model` on any `review-*`' "$claude_adapter_file"; then
      echo "  ERROR: Claude Code adapter must map tiers explicitly (sonnet for balanced, omit/inherit for frontier, forbid omitting model on reviewers/verify)"
      ERRORS=$((ERRORS + 1))
      lifecycle_mapping_invalid=true
    fi
    codex_adapter_file="$plugin_dir/skills/implement/references/adapter-codex.md"
    if ! rg -Fq 'Use $implement-lifecycle:<skill>' "$codex_adapter_file" || \
      ! rg -Fq 'spawn_agent' "$codex_adapter_file" || \
      ! rg -Fq 'send_message' "$codex_adapter_file" || \
      ! rg -Fq 'followup_task' "$codex_adapter_file" || \
      ! rg -Fq 'wait_agent' "$codex_adapter_file" || \
      ! rg -Fq 'reasoning_effort: "medium"' "$codex_adapter_file" || \
      rg -Fq 'send_input' "$codex_adapter_file"; then
      echo "  ERROR: Codex adapter must use spawn_agent/send_message/followup_task/wait_agent (no send_input) and pin balanced to reasoning_effort medium"
      ERRORS=$((ERRORS + 1))
      lifecycle_mapping_invalid=true
    fi
    agy_adapter_file="$plugin_dir/skills/implement/references/adapter-agy.md"
    if ! rg -Fq '`invoke_subagent`' "$agy_adapter_file" || \
      ! rg -Fq '`TypeName: "self"`' "$agy_adapter_file" || \
      ! rg -Fq '`Model: "flash"`' "$agy_adapter_file" || \
      ! rg -Fq '`Model: "inherit"`' "$agy_adapter_file"; then
      echo "  ERROR: Antigravity adapter must specify invoke_subagent with flash and inherit tiers"
      ERRORS=$((ERRORS + 1))
      lifecycle_mapping_invalid=true
    fi
    pi_adapter_file="$plugin_dir/skills/implement/references/adapter-pi.md"
    if ! rg -Fq 'generic `delegate` child with `skill: <skill>`' "$pi_adapter_file" || \
      ! rg -Fq 'context: "fresh"' "$pi_adapter_file"; then
      echo "  ERROR: Pi adapter must specify delegate child with fresh context"
      ERRORS=$((ERRORS + 1))
      lifecycle_mapping_invalid=true
    fi
    generic_adapter_file="$plugin_dir/skills/implement/references/adapter-generic.md"
    if ! rg -Fq 'fresh isolated child, load the mapped Agent Skill explicitly' "$generic_adapter_file"; then
      echo "  ERROR: Generic adapter must specify fresh isolated child and explicit skill load"
      ERRORS=$((ERRORS + 1))
      lifecycle_mapping_invalid=true
    fi
    if ! rg -Fq 'state.json' "$lifecycle_implement_skill" || \
      ! rg -Fq 'Continuation Mode' "$plugin_dir/skills/implement-code/SKILL.md"; then
      echo "  ERROR: implement must persist state.json and implement-code must document Continuation Mode"
      ERRORS=$((ERRORS + 1))
      lifecycle_mapping_invalid=true
    fi
    if [ "$lifecycle_mapping_invalid" = false ]; then
      echo "  OK: Canonical lifecycle mapping (7 workers), state.json persistence, and progressive-disclosure adapters are valid"
    fi

    lifecycle_continuation_invalid=false
    lifecycle_convergence_ref="$plugin_dir/skills/implement/references/convergence-recovery.md"
    if ! rg -Fq 'Spawn a fresh isolated child (never inheriting orchestrator history)' "$lifecycle_implement_skill" || \
      ! rg -Fq 'reuse that same subagent rather than spawning a new one' "$lifecycle_implement_skill"; then
      echo "  ERROR: implement must specify fresh child isolation for new tasks and continuation reuse for follow-ups"
      ERRORS=$((ERRORS + 1))
      lifecycle_continuation_invalid=true
    fi
    if ! rg -Fq 'resume' "$claude_adapter_file" || \
      ! rg -Fq 'send_message' "$codex_adapter_file" || \
      ! rg -Fq 'send_message' "$agy_adapter_file"; then
      echo "  ERROR: Progressive-disclosure adapters must specify continuation mechanisms (resume, send_message/followup_task)"
      ERRORS=$((ERRORS + 1))
      lifecycle_continuation_invalid=true
    fi
    if ! rg -Fq 'spawn fresh children' "$lifecycle_convergence_ref"; then
      echo "  ERROR: convergence-recovery must specify spawning fresh children on a clean reset"
      ERRORS=$((ERRORS + 1))
      lifecycle_continuation_invalid=true
    fi
    if [ "$lifecycle_continuation_invalid" = false ]; then
      echo "  OK: Subagent continuation and fresh reset rules verified across orchestrator and adapters"
    fi

    lifecycle_pi_manifest="$plugin_dir/package.json"
    if ! jq -e '
      .name == "implement-lifecycle" and
      (.version | type == "string" and length > 0) and
      (.keywords | type == "array" and index("pi-package")) and
      (.pi.skills == ["./skills"]) and
      (has("dependencies") | not) and
      (has("devDependencies") | not) and
      (has("scripts") | not)
    ' "$lifecycle_pi_manifest" > /dev/null 2>&1; then
      echo "  ERROR: implement-lifecycle package.json must be dependency-free Pi metadata that exposes ./skills"
      ERRORS=$((ERRORS + 1))
    elif [ "$version" != "$(jq -r '.version' "$lifecycle_pi_manifest")" ]; then
      echo "  ERROR: Version mismatch — plugin.json=$version, Pi package=$(jq -r '.version' "$lifecycle_pi_manifest")"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Pi package metadata exposes skills without runtime dependencies and version is in sync ($version)"
    fi

    lifecycle_reviewer_contract_missing=false
    for lifecycle_reviewer in review-general review-correctness review-security review-docs; do
      if ! rg -Fq 'Do not modify the reviewed codebase.' "$plugin_dir/skills/$lifecycle_reviewer/SKILL.md" || \
        ! rg -Fq 'Do not post to GitHub.' "$plugin_dir/skills/$lifecycle_reviewer/SKILL.md" || \
        rg -Fq "Run the PR's focused acceptance commands" "$plugin_dir/skills/$lifecycle_reviewer/SKILL.md"; then
        echo "  ERROR: $lifecycle_reviewer must be read-only (no code edits, no GitHub posts, no duplicate suite runs)"
        ERRORS=$((ERRORS + 1))
        lifecycle_reviewer_contract_missing=true
      fi
    done
    if [ "$lifecycle_reviewer_contract_missing" = false ]; then
      echo "  OK: Lifecycle reviewer skills are strictly read-only and do not post to GitHub or duplicate test runs"
    fi

    lifecycle_focused_contract="**Suite capability: \`focused-only\`. Prefer fast package- or target-scoped checks during iteration; Phase 5 (\`verify\` or inline fast gate) owns authoritative exact-head suite signoff.**"
    lifecycle_orchestrator_contract="**Suite capability: \`orchestrator\`. Use fast package- or target-scoped checks when refereeing in Phases 1–4; execute the authoritative suite at most once per head in Phase 5 when running the inline fast gate, otherwise delegate Phase 5 to \`verify\`.**"
    lifecycle_owner_contract="**Suite capability: \`full-suite-owner\`. Sole phase authorized to produce authoritative exact-head suite signoff (at most one full execution per PR head).**"
    lifecycle_focused_skills=(
      implement-code implement-address review-general review-correctness
      review-security review-docs merge-pr pr-check
    )
    lifecycle_prohibited_runtime_pattern='((^|[^[:alnum:]_.-])(\./)?validate-all\.sh([^[:alnum:]_.-]|$)|(^|[^[:alnum:]_])(go\.mod|go\.work|mise|golangci-lint|pinned[[:space:]]+go|go[[:space:]-]+toolchain|go[[:space:]]+1\.[0-9]+)([^[:alnum:]_]|$)|(^|[^[:alnum:]_])go[[:space:]]+test([^[:alnum:]_-]|$)|(^|[^[:alnum:]_])/tmp(/|[^[:alnum:]_]|$))'
    lifecycle_suite_contract_invalid=false
    for lifecycle_skill in "${lifecycle_focused_skills[@]}"; do
      lifecycle_skill_file="$plugin_dir/skills/$lifecycle_skill/SKILL.md"
      if [ "$(rg -Fc '<!-- lifecycle-suite-capability: focused-only -->' "$lifecycle_skill_file")" -ne 1 ] || \
        [ "$(rg -Fc "$lifecycle_focused_contract" "$lifecycle_skill_file")" -ne 1 ]; then
        echo "  ERROR: $lifecycle_skill must declare focused-only exactly once with the canonical contract"
        ERRORS=$((ERRORS + 1))
        lifecycle_suite_contract_invalid=true
      fi
    done

    if [ "$(rg -Fc '<!-- lifecycle-suite-capability: orchestrator -->' "$lifecycle_implement_skill")" -ne 1 ] || \
      [ "$(rg -Fc "$lifecycle_orchestrator_contract" "$lifecycle_implement_skill")" -ne 1 ] || \
      [ "$(rg -l '<!-- lifecycle-suite-capability: orchestrator -->' "$plugin_dir/skills"/*/SKILL.md | wc -l | tr -d ' ')" -ne 1 ]; then
      echo "  ERROR: implement must be the sole orchestrator with the canonical contract"
      ERRORS=$((ERRORS + 1))
      lifecycle_suite_contract_invalid=true
    fi

    while IFS= read -r lifecycle_v1_reference; do
      echo "  ERROR: implement-lifecycle skill or reference retains retired v1 evidence contract: $lifecycle_v1_reference"
      ERRORS=$((ERRORS + 1))
      lifecycle_suite_contract_invalid=true
    done < <(rg -n 'verification-record: v1|suite-evidence|\brecord=' "$plugin_dir/skills" -g 'SKILL.md' -g '**/references/*.md' || true)

    while IFS= read -r lifecycle_prohibited_reference; do
      echo "  ERROR: Distributed lifecycle skill contains a source-repository or language-specific runtime assumption: $lifecycle_prohibited_reference"
      ERRORS=$((ERRORS + 1))
      lifecycle_suite_contract_invalid=true
    done < <(rg -i -N "$lifecycle_prohibited_runtime_pattern" "$plugin_dir/skills" -g 'SKILL.md' -g '**/references/*.md' || true)

    lifecycle_prohibited_positive_fixtures=(
      'Run go test ./...'
      'Run go test.'
      'Run go test,'
      'Run `go test`.'
      'Use the Go toolchain selected by this repository'
      'golangci-lint run'
      'Create a go.work file'
    )
    lifecycle_prohibited_negative_fixtures=(
      'Run the target repository authoritative command'
      'Use its pinned runtime, compiler, package manager, or toolchain'
      'Document ongoing testing work'
      'Reference go.workshop as an ordinary dotted name'
      'Discuss golangci-linting without naming a command'
      'Describe go test-driven examples'
      'Describe a go test-related workflow'
      'Use a system-provided temporary directory'
    )
    for lifecycle_fixture in "${lifecycle_prohibited_positive_fixtures[@]}"; do
      if ! printf '%s\n' "$lifecycle_fixture" | rg -iq "$lifecycle_prohibited_runtime_pattern"; then
        echo "  ERROR: Prohibited-assumption classifier missed positive fixture: $lifecycle_fixture"
        ERRORS=$((ERRORS + 1))
        lifecycle_suite_contract_invalid=true
      fi
    done
    for lifecycle_fixture in "${lifecycle_prohibited_negative_fixtures[@]}"; do
      if printf '%s\n' "$lifecycle_fixture" | rg -iq "$lifecycle_prohibited_runtime_pattern"; then
        echo "  ERROR: Prohibited-assumption classifier rejected negative fixture: $lifecycle_fixture"
        ERRORS=$((ERRORS + 1))
        lifecycle_suite_contract_invalid=true
      fi
    done

    lifecycle_capability_allows_command() {
      local capability="$1"
      local candidate_plan="$2"
      local authoritative_plan="$3"
      if [ "$capability" = full-suite-owner ]; then
        return 0
      fi
      ! jq -e -n --argjson candidate "$candidate_plan" --argjson authoritative "$authoritative_plan" \
        '$candidate == $authoritative' > /dev/null 2>&1
    }
    lifecycle_capability_fixtures=(
      'focused-authoritative-plan|focused-only|["npm run lint","npm test"]|["npm run lint","npm test"]|reject'
      'focused-equivalent-json-plan|focused-only|["npm run lint", "npm test"]|["npm run lint","npm test"]|reject'
      'focused-nonauthoritative-command|focused-only|["npm run lint -- --changed"]|["npm run lint","npm test"]|accept'
      'owner-authoritative-plan|full-suite-owner|["npm run lint","npm test"]|["npm run lint","npm test"]|accept'
    )
    for lifecycle_fixture in "${lifecycle_capability_fixtures[@]}"; do
      IFS='|' read -r lifecycle_fixture_name lifecycle_capability lifecycle_candidate_plan lifecycle_authoritative_plan lifecycle_expected_outcome <<< "$lifecycle_fixture"
      lifecycle_actual_outcome='reject'
      if lifecycle_capability_allows_command "$lifecycle_capability" "$lifecycle_candidate_plan" "$lifecycle_authoritative_plan"; then
        lifecycle_actual_outcome='accept'
      fi
      if [ "$lifecycle_actual_outcome" != "$lifecycle_expected_outcome" ]; then
        echo "  ERROR: Suite capability fixture $lifecycle_fixture_name expected $lifecycle_expected_outcome, got $lifecycle_actual_outcome"
        ERRORS=$((ERRORS + 1))
        lifecycle_suite_contract_invalid=true
      fi
    done

    lifecycle_evidence_is_mergeable() {
      local expected_sha="$1"
      local expected_plan_json="$2"
      local change_scope="$3"
      local serialized_record="$4"
      local observed_ci_run_json="${5:-null}"
      jq -e --arg expected_sha "$expected_sha" --argjson expected_plan "$expected_plan_json" --arg change_scope "$change_scope" --argjson ci_run "$observed_ci_run_json" --arg target_repo "$lifecycle_expected_repo" '
        def absent($key): (has($key) | not) or .[$key] == null;
        def run_url: "^https://github\\.com/(?<repo>[^/]+/[^/]+)/actions/runs/(?<id>[0-9]+)$";
        . as $record |
        $record["verification-record"] == "v2" and
        $record["verification-head"] == $expected_sha and
        if $change_scope == "documentation-only" then
          $record["suite-result"] == "not-required" and
          $record["suite-source"] == "none" and
          ($record | absent("suite-ci-run")) and
          ($record | absent("suite-ci-attempt")) and
          $record["suite-command"] == null and
          $record["suite-exit-status"] == null and
          $record["live-check"] == "skipped"
        else
          ((($expected_plan | type) == "string" and ($expected_plan | test("\\S"))) or
            (($expected_plan | type) == "array" and ($expected_plan | length) > 0 and
              all($expected_plan[]; type == "string" and test("\\S")))) and
          (if ($expected_plan | type) == "array" then $expected_plan else [$expected_plan] end) as $expected_commands |
          $record["suite-result"] == "pass" and
          $record["suite-command"] == $expected_plan and
          $record["suite-exit-status"] == 0 and
          ($record["live-check"] == "pass" or $record["live-check"] == "skipped") and
          (if $record["suite-source"] == "executed" then
            ($record | absent("suite-ci-run")) and
            ($record | absent("suite-ci-attempt"))
          elif $record["suite-source"] == "ci" then
            ($ci_run | type) == "object" and
            ($record["suite-ci-run"] | type == "string" and test(run_url)) and
            (($record["suite-ci-run"] | capture(run_url)) as $url |
              $url.repo == $target_repo and
              $ci_run["repository"] == $target_repo and
              ($ci_run["id"] | tostring) == $url.id) and
            ($record["suite-ci-attempt"] | type == "number" and . >= 1 and . == floor) and
            ($ci_run["attempt"] | type == "number") and
            $ci_run["attempt"] == $record["suite-ci-attempt"] and
            $ci_run["headSha"] == $expected_sha and
            $ci_run["conclusion"] == "success" and
            ([$ci_run["jobs"][]? | select(any(.steps[]?; .command as $command | any($expected_commands[]; . == $command)))] as $plan_jobs |
              ($plan_jobs | length) > 0 and
              all($plan_jobs[];
                ([.steps[]? | select(.command as $command | any($expected_commands[]; . == $command))] as $plan_steps |
                  ($plan_steps | map(.command)) == $expected_commands and
                  all($plan_steps[]; .conclusion == "success" and .conditional == false and .continueOnError == false))))
          else false end)
        end
      ' <<< "$serialized_record" > /dev/null 2>&1
    }

    lifecycle_expected_sha='0123456789abcdef0123456789abcdef01234567'
    lifecycle_expected_repo='example/repo'
    lifecycle_evidence_fixtures=(
      'exact|["npm run lint","npm test"]|executable|accept|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-ci-run":null,"suite-ci-attempt":null,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"pass"}'
      'equivalent-array-json|["npm run lint", "npm test"]|executable|accept|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'scalar-command|"npm test"|executable|accept|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":"npm test","suite-exit-status":0,"live-check":"pass"}'
      'null-plan|null|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":null,"suite-exit-status":0,"live-check":"skipped"}'
      'empty-scalar|""|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":"","suite-exit-status":0,"live-check":"skipped"}'
      'whitespace-scalar|"   "|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":"   ","suite-exit-status":0,"live-check":"skipped"}'
      'empty-array|[]|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":[],"suite-exit-status":0,"live-check":"skipped"}'
      'empty-array-element|["npm test",""]|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":["npm test",""],"suite-exit-status":0,"live-check":"skipped"}'
      'whitespace-array-element|["npm test","   "]|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":["npm test","   "],"suite-exit-status":0,"live-check":"skipped"}'
      'nonstring-array-element|["npm test",1]|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":["npm test",1],"suite-exit-status":0,"live-check":"skipped"}'
      'documentation-only-with-plan|"npm test"|documentation-only|accept|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"not-required","suite-source":"none","suite-ci-run":null,"suite-ci-attempt":null,"suite-command":null,"suite-exit-status":null,"live-check":"skipped"}'
      'executable-not-required|"npm test"|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"not-required","suite-source":"none","suite-command":null,"suite-exit-status":null,"live-check":"skipped"}'
      'missing-contract|["npm run lint","npm test"]|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"missing-contract","suite-source":"none","suite-command":null,"suite-exit-status":null,"live-check":"skipped"}'
      'reordered|["npm run lint","npm test"]|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":["npm test","npm run lint"],"suite-exit-status":0,"live-check":"pass"}'
      'altered-arguments|["npm run lint","npm test"]|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":["npm run lint","npm test -- --quick"],"suite-exit-status":0,"live-check":"pass"}'
      'wrong-sha|["npm run lint","npm test"]|executable|reject|{"verification-record":"v2","verification-head":"ffffffffffffffffffffffffffffffffffffffff","suite-result":"pass","suite-source":"executed","suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"pass"}'
      'wrong-status|["npm run lint","npm test"]|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"fail","suite-source":"executed","suite-command":["npm run lint","npm test"],"suite-exit-status":1,"live-check":"pass"}'
      'live-check-fail|"npm test"|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":"npm test","suite-exit-status":0,"live-check":"fail"}'
      'live-check-partial|"npm test"|executable|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":"npm test","suite-exit-status":0,"live-check":"partial"}'
      'v1-rejected|"npm test"|executable|reject|{"verification-record":"v1","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":"npm test","suite-exit-status":0,"live-check":"pass"}'
      'docs-only-live-fail|"npm test"|documentation-only|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"not-required","suite-source":"none","suite-command":null,"suite-exit-status":null,"live-check":"fail"}'
    )
    for lifecycle_fixture in "${lifecycle_evidence_fixtures[@]}"; do
      IFS='|' read -r lifecycle_fixture_name lifecycle_fixture_plan lifecycle_change_scope lifecycle_expected_outcome lifecycle_serialized_record <<< "$lifecycle_fixture"
      lifecycle_actual_outcome='reject'
      if lifecycle_evidence_is_mergeable "$lifecycle_expected_sha" "$lifecycle_fixture_plan" "$lifecycle_change_scope" "$lifecycle_serialized_record"; then
        lifecycle_actual_outcome='accept'
      fi
      if [ "$lifecycle_actual_outcome" != "$lifecycle_expected_outcome" ]; then
        echo "  ERROR: Verification record v2 fixture $lifecycle_fixture_name expected $lifecycle_expected_outcome, got $lifecycle_actual_outcome"
        ERRORS=$((ERRORS + 1))
        lifecycle_suite_contract_invalid=true
      fi
    done
    lifecycle_ci_baseline_fixtures=(
      'ci-exact|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|accept|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-live-check-pass|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|accept|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"pass"}'
      'ci-live-check-fail|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"fail"}'
      'ci-run-other-sha|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"ffffffffffffffffffffffffffffffffffffffff","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-record-other-sha|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"ffffffffffffffffffffffffffffffffffffffff","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"ffffffffffffffffffffffffffffffffffffffff","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-run-failed|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"failure","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-run-other-repo|["npm run lint","npm test"]|executable|{"repository":"fork/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-run-url-other-repo|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/fork/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-run-id-mismatch|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":102,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-attempt-mismatch|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":2,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-missing-attempt|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-run-unconfirmed|["npm run lint","npm test"]|executable|null|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-missing-run-url|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-step-skipped|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"skipped","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-step-conditional|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":true,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-step-continue-on-error|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":true},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-matrix-leg-missing-plan|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-steps-reordered|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-no-plan-job|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-fail-result|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"fail","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":1,"live-check":"skipped"}'
      'executed-explicit|["npm run lint","npm test"]|executable|null|accept|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"pass"}'
      'executed-with-ci-attempt|["npm run lint","npm test"]|executable|null|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"pass"}'
      'docs-only-with-ci-attempt|"npm test"|documentation-only|null|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"not-required","suite-source":"none","suite-ci-attempt":1,"suite-command":null,"suite-exit-status":null,"live-check":"skipped"}'
      'executed-with-ci-run|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"executed","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"pass"}'
      'unknown-source|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"cache","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'source-false|["npm run lint","npm test"]|executable|null|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":false,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'docs-only-ci-source|"npm test"|documentation-only|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"not-required","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-command":null,"suite-exit-status":null,"live-check":"skipped"}'
      'docs-only-executed-source|"npm test"|documentation-only|null|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"not-required","suite-source":"executed","suite-command":null,"suite-exit-status":null,"live-check":"skipped"}'
      'preexisting-only-failure|"npm test"|executable|null|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"fail","suite-source":"executed","suite-ci-run":null,"suite-ci-attempt":null,"suite-command":"npm test","suite-exit-status":1,"live-check":"pass"}'
      'ci-attempt-absent|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'ci-attempt-fractional|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1.5,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1.5,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
      'unflagged-leg|["npm run lint","npm test"]|executable|{"repository":"example/repo","id":101,"attempt":1,"url":"https://github.com/example/repo/actions/runs/101","headSha":"0123456789abcdef0123456789abcdef01234567","conclusion":"success","jobs":[{"name":"test (node-20)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"test (node-22)","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm run lint","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"docs","steps":[{"command":"npm run docs","conclusion":"success","conditional":false,"continueOnError":false}]},{"name":"integration","steps":[{"command":"actions/checkout","conclusion":"success","conditional":false,"continueOnError":false},{"command":"npm test","conclusion":"failure","conditional":false,"continueOnError":false}]}]}|reject|{"verification-record":"v2","verification-head":"0123456789abcdef0123456789abcdef01234567","suite-result":"pass","suite-source":"ci","suite-ci-run":"https://github.com/example/repo/actions/runs/101","suite-ci-attempt":1,"suite-command":["npm run lint","npm test"],"suite-exit-status":0,"live-check":"skipped"}'
    )
    for lifecycle_fixture in "${lifecycle_ci_baseline_fixtures[@]}"; do
      IFS='|' read -r lifecycle_fixture_name lifecycle_fixture_plan lifecycle_change_scope lifecycle_observed_ci_run lifecycle_expected_outcome lifecycle_serialized_record <<< "$lifecycle_fixture"
      lifecycle_actual_outcome='reject'
      if lifecycle_evidence_is_mergeable "$lifecycle_expected_sha" "$lifecycle_fixture_plan" "$lifecycle_change_scope" "$lifecycle_serialized_record" "$lifecycle_observed_ci_run"; then
        lifecycle_actual_outcome='accept'
      fi
      if [ "$lifecycle_actual_outcome" != "$lifecycle_expected_outcome" ]; then
        echo "  ERROR: CI/source verification fixture $lifecycle_fixture_name expected $lifecycle_expected_outcome, got $lifecycle_actual_outcome"
        ERRORS=$((ERRORS + 1))
        lifecycle_suite_contract_invalid=true
      fi
    done
    lifecycle_verify_file="$plugin_dir/skills/verify/SKILL.md"
    if [ "$(rg -Fc '<!-- lifecycle-suite-capability: full-suite-owner -->' "$lifecycle_verify_file")" -ne 1 ] || \
      [ "$(rg -Fc "$lifecycle_owner_contract" "$lifecycle_verify_file")" -ne 1 ] || \
      [ "$(rg -l '<!-- lifecycle-suite-capability: full-suite-owner -->' "$plugin_dir/skills"/*/SKILL.md | wc -l | tr -d ' ')" -ne 1 ]; then
      echo "  ERROR: verify must be the sole full-suite-owner with the canonical contract"
      ERRORS=$((ERRORS + 1))
      lifecycle_suite_contract_invalid=true
    fi
    if [ "$lifecycle_suite_contract_invalid" = false ]; then
      echo "  OK: Lifecycle suite capabilities reserve the authoritative suite for verify"
    fi

    if rg -q 'Phase 4\.5|Docs Compliance Gate|lifecycle-docs-gate' "$lifecycle_implement_skill"; then
      echo "  ERROR: implement must not retain the standalone docs gate (Phase 4.5)"
      ERRORS=$((ERRORS + 1))
    elif ! sed -n '/^#### Step A/,/^#### Step B/p' "$lifecycle_implement_skill" | rg -Fq -- '- `review-docs`: docs, specs, READMEs, or public interfaces'; then
      echo "  ERROR: Step A must list review-docs with its docs-change trigger"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Docs review is a triggered round-1 reviewer; no standalone docs gate"
    fi

    # The recovery graph lives in a skill-local reference read on the incomplete-result path.
    lifecycle_recovery_ref="$plugin_dir/skills/implement/references/reviewer-recovery.md"
    if ! rg -q 'context: "fresh"' "$plugin_dir/skills/implement/references/adapter-pi.md" || \
      [ "$(rg -Fc 'context: "fresh"' "$lifecycle_recovery_ref")" -lt 2 ]; then
      echo '  ERROR: Pi delegation and recovery must set context: "fresh" explicitly'
      ERRORS=$((ERRORS + 1))
    elif ! rg -Fq 'read `references/reviewer-recovery.md` before refereeing' "$lifecycle_implement_skill"; then
      echo "  ERROR: implement must point to references/reviewer-recovery.md on the incomplete-reviewer-result path"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Pi reviewers use explicit fresh context and recover incomplete canonical results"
    fi

    lifecycle_reviewer_output_invalid=false
    for lifecycle_reviewer in review-general review-correctness review-security review-docs; do
      lifecycle_reviewer_file="$plugin_dir/skills/$lifecycle_reviewer/SKILL.md"
      for lifecycle_heading in '### Action Required' '### Recommended' '### Minor' '### Summary'; do
        if [ "$(rg -Fc "$lifecycle_heading" "$lifecycle_reviewer_file")" -ne 1 ]; then
          echo "  ERROR: $lifecycle_reviewer must return canonical heading $lifecycle_heading exactly once"
          ERRORS=$((ERRORS + 1))
          lifecycle_reviewer_output_invalid=true
        fi
      done
      if ! rg -Fq 'Return all four headings. Write `None.` beneath every empty category.' "$lifecycle_reviewer_file"; then
        echo "  ERROR: $lifecycle_reviewer must require all canonical result headings"
        ERRORS=$((ERRORS + 1))
        lifecycle_reviewer_output_invalid=true
      fi
    done
    if [ "$lifecycle_reviewer_output_invalid" = false ]; then
      echo "  OK: Every reviewer requires a non-empty four-heading canonical result"
    fi

    # Comment rule: bootstrap-docs' code template is authoritative; the lifecycle skills paraphrase it.
    comment_code_template="plugins/bootstrap-docs/skills/bootstrap-docs/assets/standards-code-template.md"
    comment_test_template="plugins/bootstrap-docs/skills/bootstrap-docs/assets/standards-testing-template.md"
    comment_rule_invalid=false
    if ! rg -Fq 'Add no comments. Exceptions: a constraint imposed from outside the codebase (link its source), a guarantee that cannot be tested, `TODO(#N)`, tool directives, and comments a tool turns into output. If code must stay a certain way, write a test named after that guarantee instead of a comment. Put the reason for a change in the commit body and the PR. Leave existing comments alone unless your change makes them false.' "$comment_code_template" || \
      rg -Fq 'must have documentation comments' "$comment_code_template"; then
      echo "  ERROR: standards-code-template.md must carry the canonical comment rule and not require doc comments on exported symbols"
      ERRORS=$((ERRORS + 1))
      comment_rule_invalid=true
    fi
    if rg -Fq 'Test<Function>_<scenario>' "$comment_test_template" || \
      ! rg -Fq 'Name each test after the guarantee it pins' "$comment_test_template"; then
      echo "  ERROR: standards-testing-template.md must name tests after the guarantee they pin"
      ERRORS=$((ERRORS + 1))
      comment_rule_invalid=true
    fi
    if ! rg -Fq 'Add no comments except a constraint imposed from outside the codebase' "$plugin_dir/skills/implement-code/SKILL.md" || \
      ! rg -Fq 'write a test named after that guarantee' "$plugin_dir/skills/implement-code/SKILL.md" || \
      ! rg -Fq 'Leave existing comments alone unless your change makes them false.' "$plugin_dir/skills/implement-code/SKILL.md" || \
      ! rg -Fq 'Add no comments outside the allow-list' "$plugin_dir/skills/implement-address/SKILL.md" || \
      ! rg -Fq 'delete none unless your change makes it false' "$plugin_dir/skills/implement-address/SKILL.md"; then
      echo "  ERROR: implement-code and implement-address must forbid comments outside the allow-list and deleting existing comments"
      ERRORS=$((ERRORS + 1))
      comment_rule_invalid=true
    fi
    if ! rg -Fq -- '- **Comments** —' "$plugin_dir/skills/review-general/SKILL.md" || \
      ! rg -Fq 'never blocking unless the target repository declares the comment policy' "$plugin_dir/skills/review-general/SKILL.md"; then
      echo "  ERROR: review-general must carry a Comments checklist item that is non-blocking unless repository policy declares it"
      ERRORS=$((ERRORS + 1))
      comment_rule_invalid=true
    fi
    if [ "$comment_rule_invalid" = false ]; then
      echo "  OK: Comment rule pinned in the code template, testing template, implementer, addresser, and general reviewer"
    fi

    lifecycle_merge_file="$plugin_dir/skills/merge-pr/SKILL.md"
    # CI-evidence acceptance rules live in a verify-local reference read before recording suite-source: ci.
    lifecycle_verify_ci_ref="$plugin_dir/skills/verify/references/ci-evidence.md"
    lifecycle_special_verdicts_ref="$plugin_dir/skills/verify/references/special-verdicts.md"
    lifecycle_merge_ci_ref="$plugin_dir/skills/merge-pr/references/ci-source.md"
    lifecycle_verify_baseline_ref="$plugin_dir/skills/verify/references/baseline-on-failure.md"
    lifecycle_verify_loop_ref="$plugin_dir/skills/implement/references/verify-fail-loop.md"
    if ! rg -Fq 'Read `references/ci-evidence.md`' "$lifecycle_verify_file" && ! rg -Fq 'references/ci-evidence.md' "$lifecycle_verify_file" || \
      ! rg -Fq "apply repository instructions first, then CI configuration, documented dev commands, and build/test config." "$lifecycle_verify_file" || \
      ! rg -Fq 'Preserve multiple required commands in order as one plan; never subset or reorder them.' "$lifecycle_verify_file" || \
      ! rg -Fq 'references/special-verdicts.md' "$lifecycle_verify_file" || \
      ! rg -Fq 'gh pr merge <pr-number> <merge-method-flag> <optional-delete-branch-flag> --match-head-commit "$VERIFIED_SHA"' "$lifecycle_merge_file" || \
      ! rg -Fq 'verification-head: <full-head-sha>' "$lifecycle_verify_file" || \
      ! rg -Fq 'verification-record: v2' "$lifecycle_verify_file" || \
      ! rg -Fq 'suite-exit-status: <integer> | n/a' "$lifecycle_verify_file" || \
      ! rg -Fq 'suite-result: pass | fail | missing-contract | not-required' "$lifecycle_verify_file" || \
      ! rg -Fq 'suite-command: <exact-command-or-ordered-JSON-command-array> | none' "$lifecycle_verify_file" || \
      ! rg -Fq 'live-check: pass | fail | skipped | partial' "$lifecycle_verify_file" || \
      ! rg -Fq 'suite-result: missing-contract' "$lifecycle_special_verdicts_ref" || \
      ! rg -Fq 'suite-result: not-required' "$lifecycle_special_verdicts_ref" || \
      ! rg -Fq 'verification-record: v2' "$lifecycle_merge_file" || \
      ! rg -Fq 'Accept `suite-result: not-required`' "$lifecycle_merge_file" || \
      ! rg -Fq 'Evaluate and execute the canonical `merge-pr` skill inline against `<pr-number>`; do not spawn a child for it.' "$lifecycle_implement_skill" || \
      ! rg -Fq 'suite-source: executed | ci | none' "$lifecycle_verify_file" || \
      ! rg -Fq 'a failing, other-SHA, other-repository, or unconfirmable run is not evidence, so execute instead' "$lifecycle_verify_file" || \
      ! rg -Fq 'Suite runs must pass' "$lifecycle_verify_ci_ref" && ! rg -Fq '`conclusion` is `success`' "$lifecycle_verify_ci_ref" || \
      ! rg -Fq 'no conditional or `continue-on-error` plan steps' "$lifecycle_verify_ci_ref" || \
      ! rg -Fq 'suite-ci-attempt: <n> | none' "$lifecycle_verify_file" || \
      ! rg -Fq 'Reject a record whose `suite-ci-attempt` is none or not an integer ≥ 1' "$lifecycle_merge_ci_ref" || \
      ! rg -Fq -- '--attempt <suite-ci-attempt>' "$lifecycle_merge_ci_ref" || \
      ! rg -Fq 'Reject a run for any other SHA, repository, or attempt.' "$lifecycle_merge_ci_ref"; then
      echo "  ERROR: Verification evidence (v2) and merge must remain bound to the exact PR head"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Verification evidence (v2) is exact-head and merge uses an atomic head guard"
    fi

    lifecycle_verify_scope_ok=true
    for lifecycle_scope_check in \
      "$lifecycle_verify_loop_ref|Allow at most 2 FAIL → address → re-verify cycles; on a third FAIL, do not address again" \
      "$lifecycle_implement_skill|Payload: <pr-number> tier=<Small|Medium|Large> [failed-scenarios=<names>] bundle=<resolved-context-bundle-path>" \
      "$lifecycle_verify_file|**Small** — suite evidence, plus one live check only when runtime behavior changed" \
      "$lifecycle_verify_file|re-run only those scenarios plus suite evidence for the new head" \
      "$lifecycle_verify_baseline_ref|When the head's suite fails, run each failing command once on the PR's merge-base" \
      "$lifecycle_verify_baseline_ref|a failure present at both SHAs is pre-existing" \
      "$lifecycle_verify_baseline_ref|A \`PARTIAL\` / \`suite-result: fail\` record is never mergeable." \
      "$lifecycle_merge_file|pre-existing merge-base failures" \
      "$lifecycle_implement_skill|never re-classify" \
      "$lifecycle_verify_loop_ref|without \`failed-scenarios\` when only the suite failed" \
      "$lifecycle_verify_file|\`live check skipped (Small, no runtime change)\`" \
      "$lifecycle_verify_file|without \`failed-scenarios\`, re-run suite evidence only" \
      "$lifecycle_verify_ci_ref|at most the suite's own typical runtime, and never more than 30 minutes"; do
      if ! rg -Fq -- "${lifecycle_scope_check#*|}" "${lifecycle_scope_check%%|*}"; then
        echo "  ERROR: Verification scope invariant missing from $(basename "$(dirname "${lifecycle_scope_check%%|*}")"): ${lifecycle_scope_check#*|}"
        ERRORS=$((ERRORS + 1))
        lifecycle_verify_scope_ok=false
      fi
    done
    if rg -Fq 'repeat until **PASS** or **N/A**' "$lifecycle_implement_skill" || \
      rg -qi 'last line of defense|almost always something to verify' "$lifecycle_verify_file"; then
      echo "  ERROR: Verification must stay tier-scaled and capped (no uncapped re-verify loop or blanket thoroughness mandate)"
      ERRORS=$((ERRORS + 1))
      lifecycle_verify_scope_ok=false
    fi
    if [ "$lifecycle_verify_scope_ok" = true ]; then
      echo "  OK: Verification is tier-scaled, capped at 2 cycles, and baselines failures on the merge-base"
    fi

    lifecycle_policy_decision() {
      local checks_pass="$1"
      local approvals_required="$2"
      local approvals_met="$3"
      local billing_failure="$4"
      local repository_billing="$5"
      local user_billing="$6"
      local repository_methods="$7"
      local user_method="$8"
      local repository_retention="$9"
      local user_retention="${10}"
      local selected_method
      local delete_branch=false

      if [ "$checks_pass" != true ] || \
        { [ "$approvals_required" = true ] && [ "$approvals_met" != true ]; }; then
        printf '%s\n' '{"outcome":"reject"}'
        return
      fi
      if [ "$billing_failure" = true ]; then
        if [ "$repository_billing" = deny ] || \
          { [ "$repository_billing" = silent ] && [ "$user_billing" != allow ]; }; then
          printf '%s\n' '{"outcome":"reject"}'
          return
        fi
      fi

      selected_method="$user_method"
      if [ "$selected_method" = silent ]; then
        selected_method="${repository_methods%%,*}"
      elif [[ ",$repository_methods," != *",$selected_method,"* ]]; then
        printf '%s\n' '{"outcome":"reject"}'
        return
      fi

      if [ "$repository_retention" != silent ] && \
        [ "$user_retention" != silent ] && \
        [ "$repository_retention" != "$user_retention" ]; then
        printf '%s\n' '{"outcome":"reject"}'
        return
      fi
      if [ "$repository_retention" = delete ] || \
        { [ "$repository_retention" = silent ] && [ "$user_retention" = delete ]; }; then
        delete_branch=true
      fi
      jq -cn --arg method "$selected_method" --argjson delete_branch "$delete_branch" \
        '{outcome:"accept",merge_method:$method,delete_branch:$delete_branch}'
    }

    lifecycle_policy_fixtures=(
      'no-review-required|true|false|false|false|silent|silent|merge,squash|merge|silent|silent|{"outcome":"accept","merge_method":"merge","delete_branch":false}'
      'required-check-failure|false|false|false|false|silent|silent|merge|merge|silent|silent|{"outcome":"reject"}'
      'approval-required-missing|true|true|false|false|silent|silent|merge|merge|silent|silent|{"outcome":"reject"}'
      'approval-required-met|true|true|true|false|silent|silent|merge|merge|silent|silent|{"outcome":"accept","merge_method":"merge","delete_branch":false}'
      'billing-exception-allowed|true|false|false|true|allow|silent|squash|squash|silent|silent|{"outcome":"accept","merge_method":"squash","delete_branch":false}'
      'billing-exception-policy-denied|true|false|false|true|deny|allow|squash|squash|silent|silent|{"outcome":"reject"}'
      'repository-method-selected|true|false|false|false|silent|silent|merge,rebase|rebase|silent|silent|{"outcome":"accept","merge_method":"rebase","delete_branch":false}'
      'disallowed-method|true|false|false|false|silent|silent|merge,squash|rebase|silent|silent|{"outcome":"reject"}'
      'retained-branch|true|false|false|false|silent|silent|merge|merge|retain|silent|{"outcome":"accept","merge_method":"merge","delete_branch":false}'
      'retention-conflict|true|false|false|false|silent|silent|merge|merge|retain|delete|{"outcome":"reject"}'
    )
    for lifecycle_fixture in "${lifecycle_policy_fixtures[@]}"; do
      IFS='|' read -r lifecycle_fixture_name lifecycle_checks_pass lifecycle_approvals_required lifecycle_approvals_met lifecycle_billing_failure lifecycle_repository_billing lifecycle_user_billing lifecycle_repository_methods lifecycle_user_method lifecycle_repository_retention lifecycle_user_retention lifecycle_expected_decision <<< "$lifecycle_fixture"
      lifecycle_actual_decision=$(lifecycle_policy_decision \
        "$lifecycle_checks_pass" "$lifecycle_approvals_required" "$lifecycle_approvals_met" \
        "$lifecycle_billing_failure" "$lifecycle_repository_billing" "$lifecycle_user_billing" \
        "$lifecycle_repository_methods" "$lifecycle_user_method" \
        "$lifecycle_repository_retention" "$lifecycle_user_retention")
      if [ "$lifecycle_actual_decision" != "$lifecycle_expected_decision" ]; then
        echo "  ERROR: Merge policy fixture $lifecycle_fixture_name expected $lifecycle_expected_decision, got $lifecycle_actual_decision"
        ERRORS=$((ERRORS + 1))
        lifecycle_suite_contract_invalid=true
      fi
    done

    if ! rg -Fq 'Enforced repository constraints are binding.' "$lifecycle_merge_file" || \
      ! rg -Fq 'Explicit user direction may select only among choices those constraints permit; it cannot waive or contradict them.' "$lifecycle_merge_file" || \
      ! rg -Fq 'Apply this precedence consistently to required checks, approvals, billing exceptions, merge method, and branch retention.' "$lifecycle_merge_file" || \
      ! rg -Fq 'If the established policy does not require approval, do not invent a requirement from the base branch name.' "$lifecycle_merge_file" || \
      ! rg -Fq 'Use the corresponding supported GitHub CLI method flag (`--merge`, `--squash`, or `--rebase`).' "$lifecycle_merge_file" || \
      ! rg -Fq 'omit it when the branch must be retained' "$lifecycle_merge_file"; then
      echo "  ERROR: Merge readiness must defer checks, approvals, billing exceptions, merge method, and branch retention to target policy"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Merge policy fixtures cover approvals, billing, non-squash methods, and retained branches"
    fi

    lifecycle_loop_ok=true
    for loop_text in \
      '| Small | ≤ 400 changed lines |' \
      '| Medium | 401–1,500 changed lines |' \
      '| Large | > 1,500 changed lines |' \
      'Size tier is determined strictly by net changed lines; risk paths select specialist lenses without escalating the size tier.' \
      'the addresser fixes the final round'"'"'s accepted findings and runs focused tests' \
      '| Small | 1 |' '| Medium | 2 |' '| Large | 2 |' \
      'Round 2 runs only if Round 1 accepted ≥ 1 Action Required finding' \
      'only accepted Minor' \
      'out of delta' \
      'Follow-up reviewers judge only that range' \
      'Attach up to **2 specialist lenses** by path/change trigger (**max 3 reviewers total**)' \
      'excluding whole-file deletions, lockfiles, generated files' \
      'inspect all changed paths (including deletions)' \
      'when Round 1 accepted `Action Required` solely from `review-docs` and the delta touches docs only, continue `review-docs` only; otherwise continue `review-general`' \
      'do not poll, sleep, or schedule wake-ups'; do
      if ! rg -Fiq -- "$loop_text" "$lifecycle_implement_skill"; then
        echo "  ERROR: implement Phase 4 must keep tier/loop invariant: $loop_text"
        ERRORS=$((ERRORS + 1))
        lifecycle_loop_ok=false
      fi
    done
    if rg -qi 'round 3|round-3|round 5|round-5|mandatory loop|large-tier\.md' "$lifecycle_implement_skill"; then
      echo "  ERROR: implement Phase 4 must not reference retired round-3/round-5 ceilings, mandatory loop, or large-tier.md"
      ERRORS=$((ERRORS + 1))
      lifecycle_loop_ok=false
    fi
    if [ "$lifecycle_loop_ok" = true ]; then
      echo "  OK: Phase 4 enforces orthogonal LOC tiers, 2-round cap, Action-Required R2 gating, and max 2 risk lenses"
    fi
    lifecycle_details_lines() {
      awk -v mode="$1" '
        /^<details>$/ { inside = 1; state = 1; rendered = 0; next }
        /^<\/details>$/ { inside = 0; next }
        inside && state == 1 && /^<summary>.*<\/summary>$/ { state = 2; next }
        inside && state == 2 { rendered = ($0 == ""); state = 3; next }
        mode == "outside" && !inside { print }
        mode == "inside" && inside { print }
        mode == "rendered" && inside && rendered { print }
      ' "$2"
    }

    ledger_section=$(sed -n '/^## Run ledger$/,/^## Escalation$/p' "$lifecycle_implement_skill")
    ledger_ref="$plugin_dir/skills/implement/references/run-ledger.md"
    ledger_collapsed=$(lifecycle_details_lines rendered "$ledger_ref" 2>/dev/null || true)
    ledger_ok=true
    if [ -z "$ledger_section" ] || ! rg -q '^## Escalation$' "$lifecycle_implement_skill"; then
      echo "  ERROR: implement must have '## Run ledger' followed by '## Escalation' headings"
      ERRORS=$((ERRORS + 1))
      ledger_ok=false
    fi
    if ! rg -q '^</details>$' "$ledger_ref" 2>/dev/null; then
      echo "  ERROR: run-ledger.md must close its <details> block with a closing </details> line"
      ERRORS=$((ERRORS + 1))
      ledger_ok=false
    fi
    for ledger_field in 'every terminal path' 'references/run-ledger.md'; do
      if ! printf '%s' "$ledger_section" | rg -Fq -- "$ledger_field"; then
        echo "  ERROR: implement run ledger must include: $ledger_field"
        ERRORS=$((ERRORS + 1))
        ledger_ok=false
      fi
    done
    for ledger_field in '## Run Ledger' '- Tier:' '- Children:' '- Rounds: review' '- Fix commits:' '- Wall-clock:' '- Follow-up items:' '- Outcome:'; do
      if ! printf '%s' "$ledger_collapsed" | rg -Fq -- "$ledger_field"; then
        echo "  ERROR: implement run ledger template must collapse under <details> (blank line after </summary>) and include: $ledger_field"
        ERRORS=$((ERRORS + 1))
        ledger_ok=false
      fi
    done
    if [ "$ledger_ok" = true ]; then
      echo "  OK: implement prints a collapsed run ledger with tier, children, rounds, fix commits, wall-clock, and follow-ups"
    fi

    description_shape_ok=true
    for shape_file in "plugins/bootstrap-docs/skills/bootstrap-docs/assets/standards-pr-template.md" "$plugin_dir/skills/implement-code/references/pr-description.md"; do
      shape_visible=$(lifecycle_details_lines outside "$shape_file")
      shape_collapsed=$(lifecycle_details_lines rendered "$shape_file")
      if ! printf '%s' "$shape_visible" | rg -Fq '*(agent-drafted lead)*' || \
        ! printf '%s' "$shape_visible" | rg -q '· Author ran: ' || \
        ! printf '%s' "$shape_visible" | rg -Fq '**Review focus:** ' || \
        ! printf '%s' "$shape_collapsed" | rg -q '^## Design$' || \
        rg -q 'Verified' "$shape_file" || \
        printf '%s\n' "$shape_visible" | rg -q '^#{1,6} (TL;DR|Summary|Review focus|Test evidence|Progress|Live status|Status)'; then
        echo "  ERROR: $shape_file must specify the description shape: lead with *(agent-drafted lead)*, '· Author ran:', '**Review focus:**', the rest under <details> with a blank line after </summary>, and no Verified or living sections"
        ERRORS=$((ERRORS + 1))
        description_shape_ok=false
      fi
    done
    if [ "$description_shape_ok" = true ]; then
      echo "  OK: PR standards template and implement-code fallback specify the collapsed description shape"
    fi

    # Specs are the shared conceptual model: bootstrap-docs templates are authoritative; review-docs checks them.
    spec_dir="plugins/bootstrap-docs/skills/bootstrap-docs"
    spec_ok=true
    for spec_template in "$spec_dir/assets/product-spec-template.md" "$spec_dir/assets/technical-spec-template.md"; do
      if [ "$(rg -m1 '^## ' "$spec_template")" != '## Glossary' ] || \
        ! rg -q '^## Invariants$' "$spec_template" || \
        ! rg -q '^\*\*Covers:\*\*' "$spec_template" || \
        rg -qi 'target lines|[0-9]+.[0-9]+ lines|Last Updated' "$spec_template"; then
        echo "  ERROR: $spec_template must open with a Glossary, include an Invariants section and a Covers: field, with no line-count target and no Last Updated"
        ERRORS=$((ERRORS + 1))
        spec_ok=false
      fi
    done
    if rg -qi 'Last Updated:|\*\*Last Updated|Target Lines|(must|should|require[sd]?) [^.]*bidirectional' "$spec_dir/SKILL.md" "$spec_dir"/assets/*.md || \
      rg -q '^## Related Documents' "$spec_dir"/assets/*.md || \
      ! rg -Uq '^ +adr:\n +status: declined$' "$spec_dir/SKILL.md" || \
      [ "$(wc -l < "$spec_dir/assets/adr-template.md")" -gt 40 ]; then
      echo "  ERROR: bootstrap-docs must not require Last Updated, a Related Documents section, two-way links, line-number references or line-count targets, and the ADR module must default to declined with a one-page template"
      ERRORS=$((ERRORS + 1))
      spec_ok=false
    fi
    if rg -qi 'schema, indexes' "$spec_dir/SKILL.md" "$spec_dir/assets/strategy-template.md"; then
      echo "  ERROR: bootstrap-docs must not define technical specs as 'schema, indexes'"
      ERRORS=$((ERRORS + 1))
      spec_ok=false
    fi
    if ! rg -Fq 'Glossary terms that no longer appear in the covered code' "$plugin_dir/skills/review-docs/SKILL.md" || \
      rg -qi 'Last Updated|bidirectional|reciprocated' "$plugin_dir/skills/review-docs/SKILL.md"; then
      echo "  ERROR: review-docs must check spec glossary terms against covered code and must not check Last Updated or two-way links"
      ERRORS=$((ERRORS + 1))
      spec_ok=false
    fi
    if [ "$spec_ok" = true ]; then
      echo "  OK: spec templates carry the shared-model sections and review-docs checks spec vocabulary"
    fi

    # Instruction files stay small: bootstrap-docs creates no per-folder index pairs, imports AGENTS.md everywhere, and migrates without unconfirmed deletes.
    instr_skill="$spec_dir/SKILL.md"
    instr_strategy="$spec_dir/assets/strategy-template.md"
    instr_ok=true
    if [ "$(wc -l < "$instr_strategy")" -gt 130 ] || \
      ! rg -Fq 'The generated strategy doc stays under 200 lines' "$instr_skill" || \
      ! rg -Fq '**Each `AGENTS.md` stays under 200 lines**' "$instr_strategy" || \
      ! rg -Fq '**Line budgets only ever decrease, and they apply to instruction files only.**' "$instr_strategy" || \
      ! rg -Fq 'Maximums, not goals.' "$instr_strategy" || \
      ! rg -Fq '| Product Spec | 1,000 |' "$instr_strategy" || \
      ! rg -Fq '**Every `CLAUDE.md` imports `@AGENTS.md`.**' "$instr_strategy"; then
      echo "  ERROR: the bootstrap-docs strategy template must stay within 130 lines (leaving room for module sections so the generated doc stays under 200) and state the instruction-file rules, and Phase 2 must keep the generated strategy doc under 200 lines"
      ERRORS=$((ERRORS + 1))
      instr_ok=false
    fi
    if rg -qi '\bcreat\w*\b[^.\n]*(AGENTS|CLAUDE)\.md[^.\n]*\b(pair|its directory|each (directory|folder|subfolder)|every (directory|folder|subfolder))\b' "$instr_skill" || \
      rg -qi '\b(each|every) (directory|folder|subfolder)\b[^.\n]*\bcreat\w*[^.\n]*(AGENTS|CLAUDE)\.md' "$instr_skill" || \
      rg -q '(docs|\{docs_location\})/[^/\s`)]+/(AGENTS|CLAUDE)\.md' "$instr_skill" || \
      rg -q '^## Contents' "$instr_skill" "$instr_strategy" || \
      rg -qi '\bupdate\b[^.\n]*\bContents\b' "$instr_skill"; then
      echo "  ERROR: bootstrap-docs must not create AGENTS.md/CLAUDE.md pairs in docs subfolders or maintain Contents lists"
      ERRORS=$((ERRORS + 1))
      instr_ok=false
    fi
    instr_phase5=$(sed -n '/^### Phase 5: Root Integration$/,/^### Phase 6: Summary$/p' "$instr_skill")
    if ! printf '%s\n' "$instr_phase5" | rg -Fq '**Every `CLAUDE.md` imports `@AGENTS.md`.**' || \
      ! printf '%s\n' "$instr_phase5" | rg -Fq 'When one lacks an `@AGENTS.md` line, add `@AGENTS.md` after any YAML frontmatter' || \
      ! printf '%s\n' "$instr_phase5" | rg -Fq 'Never add the import where the sibling `AGENTS.md` neither exists nor is being created' || \
      ! printf '%s\n' "$instr_phase5" | rg -Fq '`.claude/`' || \
      printf '%s\n' "$instr_phase5" | rg -qi 'offer to add `@AGENTS\.md`'; then
      echo "  ERROR: bootstrap-docs Phase 5 must add @AGENTS.md to every CLAUDE.md that lacks it"
      ERRORS=$((ERRORS + 1))
      instr_ok=false
    fi
    instr_migrate=$(sed -n '/^### Migrate Mode/,$p' "$instr_skill")
    if ! rg -q '^argument-hint: .*\bmigrate\b' "$instr_skill" || \
      ! printf '%s\n' "$instr_migrate" | rg -Fq '**Never delete a file without explicit confirmation.**' || \
      ! printf '%s\n' "$instr_migrate" | rg -Fq '**Apply** only the confirmed items' || \
      ! printf '%s\n' "$instr_migrate" | rg -Fq 'every rebuild or overwrite of an existing file (such as the strategy doc) as **REWRITE**' || \
      ! printf '%s\n' "$instr_migrate" | rg -Fq 'Confirm each **DELETE** and each **REWRITE** separately, naming the file' || \
      ! printf '%s\n' "$instr_migrate" | rg -Fq 'a blanket "all" never applies a **DELETE** or **REWRITE** item' || \
      ! printf '%s\n' "$instr_migrate" | rg -Fq 'show the project-specific rules that will carry over'; then
      echo "  ERROR: bootstrap-docs must offer a migrate mode that applies only confirmed changes, never deletes a file without explicit confirmation, and confirms each DELETE and REWRITE item by file name"
      ERRORS=$((ERRORS + 1))
      instr_ok=false
    fi
    if [ "$instr_ok" = true ]; then
      echo "  OK: bootstrap-docs keeps instruction files small, imports @AGENTS.md everywhere, and migrates only confirmed changes"
    fi

    if ! sed -n '/^### Step 4: Verify and Self-Review$/,/^### Step 5: /p' "$plugin_dir/skills/implement-code/SKILL.md" | rg -Fq 'Run `docs-check` with lint when the project has a `docs-check.toml`.' || \
      ! rg -Fq 'Run `docs-check` on docs changes when the project has a `docs-check.toml`.' "$plugin_dir/skills/review-docs/SKILL.md"; then
      echo "  ERROR: implement-code Step 4 must run docs-check with lint, and review-docs must run it on docs changes, when the project has a docs-check.toml"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: implement-code and review-docs run docs-check when the project has a docs-check.toml"
    fi

    review_comment_ref="$plugin_dir/skills/implement/references/consolidated-review.md"
    if ! rg -Fq 'references/consolidated-review.md' "$lifecycle_implement_skill" || \
      ! lifecycle_details_lines outside "$review_comment_ref" | rg -q '^### Reviewer Findings$' || \
      ! lifecycle_details_lines outside "$review_comment_ref" | rg -q '^\| # \| Finding \| Reviewer \| Reviewer Severity \| Decision \|$' || \
      lifecycle_details_lines outside "$review_comment_ref" | rg -Fq 'Reasoning' || \
      ! lifecycle_details_lines rendered "$review_comment_ref" | rg -Fq '| Reasoning / smallest remedy |'; then
      echo "  ERROR: The consolidated review comment must show findings and decisions visibly and collapse referee reasoning under <details>"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: The consolidated review comment shows findings and decisions and collapses referee reasoning"
    fi

    verify_step3=$(sed -n '/^### Step 3: Report Findings$/,$p' "$lifecycle_verify_file")
    verify_record_keys='^(verification-record|verification-head|suite-result|suite-source|suite-ci-run|suite-ci-attempt|suite-command|suite-exit-status|live-check):'
    verify_record_ok=true
    if [ -z "$(printf '%s\n' "$verify_step3" | lifecycle_details_lines rendered -)" ] || \
      printf '%s\n' "$verify_step3" | lifecycle_details_lines inside - | rg -q "$verify_record_keys" || \
      [ "$(printf '%s\n' "$verify_step3" | lifecycle_details_lines outside - | rg -c "$verify_record_keys" || echo 0)" -lt 9 ] || \
      ! rg -Fq 'since `merge-pr` parses them' "$lifecycle_verify_file"; then
      echo "  ERROR: verify must keep all 9 verification-record: v2 lines outside <details> and collapse only evidence"
      ERRORS=$((ERRORS + 1))
      verify_record_ok=false
    fi
    if ! rg -Fq 'Compare each change the PR description claims with `gh pr diff <number>`' "$lifecycle_verify_file" || \
      ! rg -q '^### Claim Mismatches$' "$lifecycle_verify_file" || \
      ! rg -Fq 'fix any `Claim Mismatches` via `gh pr edit --body-file`' "$lifecycle_implement_skill"; then
      echo "  ERROR: verify must report PR-description claims absent from the diff, and implement must correct them before merge"
      ERRORS=$((ERRORS + 1))
      verify_record_ok=false
    fi
    if [ "$verify_record_ok" = true ]; then
      echo "  OK: verify keeps record lines outside <details> and checks description claims against the diff"
    fi

    issue_collapse_ok=true
    for issue_skill in draft-issue refine-issue; do
      issue_skill_file="plugins/issue-management/skills/$issue_skill/SKILL.md"
      if rg -q '^## (Technical Context|Proposed PRs)$' "$issue_skill_file" || \
        ! rg -q '^<summary>Technical Context</summary>$' "$issue_skill_file" || \
        ! rg -q '^<summary>Proposed PRs</summary>$' "$issue_skill_file" || \
        ! lifecycle_details_lines rendered "$issue_skill_file" | rg -Fq -- '- **Key files:**' || \
        ! lifecycle_details_lines rendered "$issue_skill_file" | rg -q '^### PR 1: '; then
        echo "  ERROR: $issue_skill must collapse Technical Context and Proposed PRs under <details> with a blank line after </summary>"
        ERRORS=$((ERRORS + 1))
        issue_collapse_ok=false
      fi
    done
    if ! rg -Fq 'Preserve existing `<details>` blocks and their summaries: restructure inside them, never unwrap them.' plugins/issue-management/skills/cleanup-issue/SKILL.md; then
      echo "  ERROR: cleanup-issue must preserve existing <details> blocks"
      ERRORS=$((ERRORS + 1))
      issue_collapse_ok=false
    fi
    if [ "$issue_collapse_ok" = true ]; then
      echo "  OK: draft-issue and refine-issue collapse Technical Context and Proposed PRs; cleanup-issue preserves <details>"
    fi
    lifecycle_prcheck_file="$plugin_dir/skills/pr-check/SKILL.md"
    if ! rg -Fq 'Evaluate and execute the canonical `merge-pr` skill inline' "$lifecycle_implement_skill" || \
      ! rg -Fq 'do not spawn a child for it' "$lifecycle_implement_skill" || \
      ! rg -Fq 'Evaluate the canonical `pr-check` checklist inline' "$lifecycle_merge_file" || \
      ! rg -Fq 'do not spawn a child for it' "$lifecycle_merge_file" || \
      ! rg -Fq 'Block only on failures of those rules' "$lifecycle_merge_file" || \
      ! rg -Fq 'non-blocking, and are reported as WARN' "$lifecycle_merge_file" || \
      ! rg -Fq 'A fallback check never blocks' "$lifecycle_prcheck_file" || \
      rg -q 'spawn a fresh subagent|pi-subagents|Task/subagent|isolated delegation' "$lifecycle_merge_file"; then
      echo "  ERROR: merge-pr must evaluate pr-check inline (no child) and treat fallback-only failures as non-blocking WARNs"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: merge-pr evaluates pr-check inline; fallback-only failures are non-blocking"
    fi

    lifecycle_bundle_missing=false
    for lifecycle_reviewer in review-general review-correctness review-security review-docs; do
      if ! rg -Fq 'Read the supplied context-bundle file when provided; fetch `gh pr view <pr-number>`, its changed-file summary (`--json files`), and `--comments` only when invoked standalone without a bundle.' "$plugin_dir/skills/$lifecycle_reviewer/SKILL.md"; then
        echo "  ERROR: $lifecycle_reviewer must support file-backed context bundle and skip fetch when bundle is provided"
        ERRORS=$((ERRORS + 1))
        lifecycle_bundle_missing=true
      fi
    done
    if ! rg -Fq 'Read the findings file and supplied context-bundle file when provided; fetch PR metadata and comments only when invoked without a bundle.' "$plugin_dir/skills/implement-address/SKILL.md"; then
      echo "  ERROR: implement-address must support file-backed context bundle and skip fetch when bundle is provided"
      ERRORS=$((ERRORS + 1))
      lifecycle_bundle_missing=true
    fi
    if ! rg -Fq 'read the supplied context-bundle file when provided, fetching PR metadata, comments, and `--json files` only when absent' "$plugin_dir/skills/verify/SKILL.md"; then
      echo "  ERROR: verify must support file-backed context bundle and skip fetch when bundle is provided"
      ERRORS=$((ERRORS + 1))
      lifecycle_bundle_missing=true
    fi
    if [ "$lifecycle_bundle_missing" = false ]; then
      echo "  OK: File-backed context bundle skip-fetch rule enforced across reviewers, addresser, and verifier"
    fi
  fi

  if [ "$plugin_name" = "bootstrap-docs" ]; then
    docs_check_skill="$plugin_dir/skills/bootstrap-docs/SKILL.md"
    docs_check_install=$(sed -n '/^### docs-check Install (`docs-check` argument)$/,/^### /p' "$docs_check_skill")
    if [ ! -s "$plugin_dir/skills/bootstrap-docs/assets/docs-check.py" ] || \
      ! rg -q '^argument-hint: .*\bdocs-check\b' "$docs_check_skill" || \
      ! rg -Fq -- '- `docs-check`: run only docs-check Install (below)' "$docs_check_skill" || \
      ! rg -Fq 'When the project has no `docs-check.toml`, offer docs-check Install (below).' "$docs_check_skill" || \
      ! printf '%s\n' "$docs_check_install" | rg -Fq '**Copy `$SKILL_DIR/assets/docs-check.py` into the project**' || \
      ! printf '%s\n' "$docs_check_install" | rg -Fq '**Create `docs-check.toml` with the current baseline:** run `python3 scripts/docs-check.py --write-baseline`' || \
      ! printf '%s\n' "$docs_check_install" | rg -Fq 'The baseline only shrinks' || \
      ! printf '%s\n' "$docs_check_install" | rg -Fq '**Print the CI and pre-commit snippets**' || \
      ! printf '%s\n' "$docs_check_install" | rg -Fq 'id: docs-check' || \
      ! printf '%s\n' "$docs_check_install" | rg -Fq 'fetch-depth: 0'; then
      echo "  ERROR: bootstrap-docs must ship docs-check.py with an install step that copies the script, creates docs-check.toml with the current baseline, and prints CI and pre-commit snippets, offered from migrate"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: bootstrap-docs ships docs-check with an install step"
    fi

    docs_check_test="$plugin_dir/skills/bootstrap-docs/assets/docs-check/self_test.py"
    if ! command -v python3 > /dev/null 2>&1; then
      echo "  ERROR: python3 (3.11+) is required to run the docs-check self-test"
      ERRORS=$((ERRORS + 1))
    elif docs_check_output=$(python3 "$docs_check_test" 2>&1); then
      echo "  OK: docs-check self-test passed"
    else
      echo "  ERROR: docs-check self-test failed:"
      printf '%s\n' "$docs_check_output" | sed 's/^/    /'
      ERRORS=$((ERRORS + 1))
    fi
  fi

  # Run self-contained hook tests (test files that contain "# autotest" marker)
  for test_file in "$plugin_dir"/hooks/test-*.sh; do
    [ -f "$test_file" ] || continue
    test_name=$(basename "$test_file")
    if head -5 "$test_file" | grep -q '# autotest'; then
      if bash "$test_file" > /dev/null 2>&1; then
        echo "  OK: $test_name passed"
      else
        echo "  ERROR: $test_name failed"
        ERRORS=$((ERRORS + 1))
      fi
    fi
  done

  # Check .claude-plugin/marketplace.json references this plugin
  if [ -f ".claude-plugin/marketplace.json" ]; then
    if jq -e ".plugins[] | select(.name == \"$plugin_name\")" .claude-plugin/marketplace.json > /dev/null 2>&1; then
      echo "  OK: Listed in .claude-plugin/marketplace.json"

      # Check version sync between plugin.json and marketplace.json
      if [ -n "$version" ]; then
        marketplace_version=$(jq -r ".plugins[] | select(.name == \"$plugin_name\") | .version" .claude-plugin/marketplace.json)
        if [ "$version" != "$marketplace_version" ]; then
          echo "  ERROR: Version mismatch — plugin.json=$version, marketplace.json=$marketplace_version"
          ERRORS=$((ERRORS + 1))
        else
          echo "  OK: Version in sync ($version)"
        fi
      fi
    else
      echo "  WARN: Not listed in .claude-plugin/marketplace.json"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Validate every native Codex manifest, independent of marketplace membership.
  codex_listed=false
  if [ "$CODEX_MARKETPLACE_VALID" = true ] && jq -e --arg name "$plugin_name" '.plugins[] | select(.name == $name)' .agents/plugins/marketplace.json > /dev/null 2>&1; then
    codex_listed=true
  fi

  if [ -f "$plugin_dir/.codex-plugin/plugin.json" ]; then
    if ! jq . "$plugin_dir/.codex-plugin/plugin.json" > /dev/null 2>&1; then
      echo "  ERROR: .codex-plugin/plugin.json is not valid JSON"
      ERRORS=$((ERRORS + 1))
    else
      codex_name=$(jq -r '.name // empty' "$plugin_dir/.codex-plugin/plugin.json")
      codex_version=$(jq -r '.version // empty' "$plugin_dir/.codex-plugin/plugin.json")
      codex_desc=$(jq -r '.description // empty' "$plugin_dir/.codex-plugin/plugin.json")
      codex_author=$(jq -r '.author.name // empty' "$plugin_dir/.codex-plugin/plugin.json")
      codex_display_name=$(jq -r '.interface.displayName // empty' "$plugin_dir/.codex-plugin/plugin.json")

      if [ "$codex_name" != "$plugin_name" ]; then
        echo "  ERROR: Codex plugin name must match directory ($codex_name != $plugin_name)"
        ERRORS=$((ERRORS + 1))
      fi
      if [ -z "$codex_version" ] || [ -z "$codex_desc" ] || [ -z "$codex_author" ] || [ -z "$codex_display_name" ]; then
        echo "  ERROR: Codex plugin manifest is missing required metadata"
        ERRORS=$((ERRORS + 1))
      else
        echo "  OK: .codex-plugin/plugin.json has required metadata"
      fi
      if [ -n "$version" ] && [ "$codex_version" != "$version" ]; then
        echo "  ERROR: Version mismatch — Claude=$version, Codex=$codex_version"
        ERRORS=$((ERRORS + 1))
      elif [ -n "$version" ]; then
        echo "  OK: Claude and Codex versions in sync ($version)"
      fi
    fi
  elif [ "$codex_listed" = true ]; then
    echo "  ERROR: Listed in Codex marketplace but missing .codex-plugin/plugin.json"
    ERRORS=$((ERRORS + 1))
  fi

  # Marketplace membership and entry policy are separate from manifest validity.
  if [ "$codex_listed" = true ]; then
    expected_source="./plugins/$plugin_name"
    codex_source=$(jq -r --arg name "$plugin_name" '.plugins[] | select(.name == $name) | .source.path // empty' .agents/plugins/marketplace.json)
    codex_installation=$(jq -r --arg name "$plugin_name" '.plugins[] | select(.name == $name) | .policy.installation // empty' .agents/plugins/marketplace.json)
    codex_authentication=$(jq -r --arg name "$plugin_name" '.plugins[] | select(.name == $name) | .policy.authentication // empty' .agents/plugins/marketplace.json)
    codex_category=$(jq -r --arg name "$plugin_name" '.plugins[] | select(.name == $name) | .category // empty' .agents/plugins/marketplace.json)

    if [ "$codex_source" != "$expected_source" ]; then
      echo "  ERROR: Codex marketplace source must be $expected_source"
      ERRORS=$((ERRORS + 1))
    elif [ -z "$codex_installation" ] || [ -z "$codex_authentication" ] || [ -z "$codex_category" ]; then
      echo "  ERROR: Codex marketplace entry is missing policy or category"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Listed in .agents/plugins/marketplace.json"
    fi
  elif [ -f "$plugin_dir/.codex-plugin/plugin.json" ] && [ "$CODEX_MARKETPLACE_VALID" = true ]; then
    echo "  WARN: Has a Codex manifest but is not listed in the Codex marketplace"
    WARNINGS=$((WARNINGS + 1))
  fi

  echo ""
done

# Summary
echo "=== Validation Summary ==="
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "FAILED: Fix errors above before publishing"
  exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
  echo ""
  echo "PASSED with warnings"
  exit 0
fi

echo ""
echo "PASSED"
