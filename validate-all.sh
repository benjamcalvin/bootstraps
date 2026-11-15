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
    lifecycle_budget_total=34000
    lifecycle_budget_implement=11500
    lifecycle_bytes_total=$(cat "$plugin_dir"/skills/*/SKILL.md | wc -c | tr -d ' ')
    lifecycle_bytes_implement=$(wc -c < "$plugin_dir/skills/implement/SKILL.md" | tr -d ' ')
    if [ "$lifecycle_bytes_total" -gt "$lifecycle_budget_total" ] || [ "$lifecycle_bytes_implement" -gt "$lifecycle_budget_implement" ]; then
      echo "  ERROR: implement-lifecycle instructions exceed the byte budget (skills $lifecycle_bytes_total/$lifecycle_budget_total, implement $lifecycle_bytes_implement/$lifecycle_budget_implement)"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: implement-lifecycle instructions within byte budget (skills $lifecycle_bytes_total/$lifecycle_budget_total, implement $lifecycle_bytes_implement/$lifecycle_budget_implement)"
    fi

    if [ -e "$plugin_dir/skills/review-architecture" ] ||       [ -e "$plugin_dir/skills/review-testing" ] ||       [ -e "$plugin_dir/skills/review-security" ] ||       [ -e "$plugin_dir/skills/review-correctness" ] ||       [ -e "$plugin_dir/skills/pr-check" ] ||       [ -e "$plugin_dir/skills/implement/references/large-tier.md" ] ||       [ -e "$plugin_dir/skills/merge-pr/references/ci-source.md" ] ||       [ -e "$plugin_dir/skills/verify/references" ]; then
      echo "  ERROR: Retired skills or references (review-architecture, review-testing, review-security, review-correctness, pr-check, large-tier.md, ci-source.md, verify/references) must remain removed"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Retired skills and references remain removed"
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
      implement-code implement-address review-general
      review-docs verify implement merge-pr
    )
    lifecycle_skill_dir_count=$(find "$plugin_dir/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    if [ "$lifecycle_skill_dir_count" -ne 7 ]; then
      echo "  ERROR: implement-lifecycle must have exactly 7 canonical skills (found $lifecycle_skill_dir_count)"
      ERRORS=$((ERRORS + 1))
      lifecycle_metadata_missing=true
    fi
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
    for lifecycle_worker in implement-code implement-address review-general review-docs verify; do
      mapping_count=$(printf '%s\n' "$lifecycle_mapping" | rg -Fc "\`$lifecycle_worker\`")
      if [ "$mapping_count" -ne 1 ]; then
        echo "  ERROR: Canonical lifecycle mapping must contain $lifecycle_worker exactly once (found $mapping_count)"
        ERRORS=$((ERRORS + 1))
        lifecycle_mapping_invalid=true
      fi
    done
    mapping_rows=$(printf '%s\n' "$lifecycle_mapping" | rg -c '^\| (Implement|Address|Review|Review docs|Verify) \|')
    if [ "$mapping_rows" -ne 5 ]; then
      echo "  ERROR: Canonical lifecycle mapping must contain exactly five worker rows (found $mapping_rows)"
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
    if ! rg -Fq 'Continuation Mode' "$plugin_dir/skills/implement-code/SKILL.md"; then
      echo "  ERROR: implement-code must document Continuation Mode"
      ERRORS=$((ERRORS + 1))
      lifecycle_mapping_invalid=true
    fi
    if [ "$lifecycle_mapping_invalid" = false ]; then
      echo "  OK: Canonical lifecycle mapping (5 workers), Continuation Mode, and progressive-disclosure adapters are valid"
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
    for lifecycle_reviewer in review-general review-docs; do
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

    lifecycle_verify_file="$plugin_dir/skills/verify/SKILL.md"
    lifecycle_prohibited_runtime_pattern='((^|[^[:alnum:]_.-])(\./)?validate-all\.sh([^[:alnum:]_.-]|$)|(^|[^[:alnum:]_])(go\.mod|go\.work|mise|golangci-lint|pinned[[:space:]]+go|go[[:space:]-]+toolchain|go[[:space:]]+1\.[0-9]+)([^[:alnum:]_]|$)|(^|[^[:alnum:]_])go[[:space:]]+test([^[:alnum:]_-]|$)|(^|[^[:alnum:]_])/tmp(/|[^[:alnum:]_]|$))'
    lifecycle_suite_contract_invalid=false

    while IFS= read -r lifecycle_v1_reference; do
      echo "  ERROR: implement-lifecycle skill or reference retains retired v1 evidence, suite-capability, or sidecar scratch-file contract: $lifecycle_v1_reference"
      ERRORS=$((ERRORS + 1))
      lifecycle_suite_contract_invalid=true
    done < <(rg -n 'verification-record:|suite-evidence|\brecord=|state\.json|\bbundle=|bundle\.md|resolved-findings-path|resolved-verify-findings-path|pr-check|review-security|review-correctness|lifecycle-suite-capability|full-suite-owner|focused-only|fast-gate' "$plugin_dir/skills" -g 'SKILL.md' -g '**/references/*.md' || true)

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

    if ! sed -n '/^### Step 4: Verify and Self-Review$/,/^### Step 5: /p' "$plugin_dir/skills/implement-code/SKILL.md" | rg -Fq 'automated tests, linters, and build before opening the PR' || \
      ! rg -Fq 'Automated test suites are not your job.' "$lifecycle_verify_file"; then
      echo "  ERROR: implement-code must own automated tests/linters/build while verify focuses strictly on real-world checks"
      ERRORS=$((ERRORS + 1))
      lifecycle_suite_contract_invalid=true
    fi
    if [ "$lifecycle_suite_contract_invalid" = false ]; then
      echo "  OK: Coders own automated tests/builds, verify owns real-world checks, and retired contracts remain absent"
    fi

    if rg -q 'Phase 4\.5|Docs Compliance Gate|lifecycle-docs-gate' "$lifecycle_implement_skill" ||       sed -n '/^#### Step A/,/^#### Step B/p' "$lifecycle_implement_skill" | rg -Fq 'review-docs'; then
      echo "  ERROR: implement must not retain Phase 4.5 or place review-docs inside Phase 4 Step A"
      ERRORS=$((ERRORS + 1))
    elif ! sed -n '/^### Phase 5/,/^### Phase 6/p' "$lifecycle_implement_skill" | rg -Fq 'Run **Verification** and **Docs Review** **in parallel**' ||       ! sed -n '/^### Phase 5/,/^### Phase 6/p' "$lifecycle_implement_skill" | rg -Fq 'review-docs'; then
      echo "  ERROR: implement Phase 5 must run review-docs in parallel with verification"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Docs review runs in Phase 5 in parallel with verification; no standalone docs gate"
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
    for lifecycle_reviewer in review-general review-docs; do
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
    lifecycle_verify_loop_ref="$plugin_dir/skills/implement/references/verify-fail-loop.md"
    lifecycle_general_file="$plugin_dir/skills/review-general/SKILL.md"

    lifecycle_risk_ok=true
    for risk_check in       "$lifecycle_implement_skill|do not overthink"       "$lifecycle_implement_skill|Stay focused on the task at hand"       "$lifecycle_general_file|Stay focused on the task at hand; do not overthink."       "$lifecycle_implement_skill|\`Low\`"       "$lifecycle_implement_skill|\`Moderate\`"       "$lifecycle_implement_skill|\`High\`"       "$lifecycle_implement_skill|never by line-count thresholds"       "$lifecycle_implement_skill|Round 2 only if Round 1 accepted ≥ 1 \`Action Required\` finding"       "$lifecycle_implement_skill|only accepted Minor"       "$lifecycle_implement_skill|out of delta"       "$lifecycle_implement_skill|Follow-up reviewers judge only that range"       "$lifecycle_implement_skill|do not poll, sleep, or schedule wake-ups"       "$lifecycle_implement_skill|2–3 parallel \`review-general\`"       "$lifecycle_general_file|**Simplicity & scope**"       "$lifecycle_general_file|**Security**"       "$lifecycle_general_file|**Quality & correctness**"; do
      if ! rg -Fq -- "${risk_check#*|}" "${risk_check%%|*}"; then
        echo "  ERROR: Risk/complexity or general-review invariant missing from $(basename "$(dirname "${risk_check%%|*}")"): ${risk_check#*|}"
        ERRORS=$((ERRORS + 1))
        lifecycle_risk_ok=false
      fi
    done
    if rg -q '400 changed lines|401–1,500 changed lines|1,500 changed lines|Size Tier & Risk Lenses|round 3|round-3|round 5|round-5' "$lifecycle_implement_skill"; then
      echo "  ERROR: implement must scale by risk/complexity (no LOC line-count thresholds or round>2 ceilings)"
      ERRORS=$((ERRORS + 1))
      lifecycle_risk_ok=false
    fi
    if [ "$lifecycle_risk_ok" = true ]; then
      echo "  OK: Risk/complexity scaling, anti-overthinking posture, unified review-general (simplicity/security/quality), and 2-round cap enforced"
    fi

    lifecycle_verify_merge_ok=true
    for vm_check in       "$lifecycle_verify_loop_ref|Allow at most 2 FAIL → address → re-verify cycles; on a third FAIL, do not address again"       "$lifecycle_verify_loop_ref|failed-scenarios="       "$lifecycle_implement_skill|Payload: <pr-number> risk=<Low|Moderate|High> [failed-scenarios=<names>]"       "$lifecycle_implement_skill|never re-classify"       "$lifecycle_implement_skill|never spawn \`verify\` just to re-run unit tests"       "$lifecycle_implement_skill|verify: skipped (no live surface)"       "$lifecycle_verify_file|Automated test suites are not your job."       "$lifecycle_verify_file|**Data"       "$lifecycle_verify_file|**CLI"       "$lifecycle_verify_file|**Frontend"       "$lifecycle_verify_file|screenshots"       "$lifecycle_verify_file|Verified-Head: <full-head-sha>"       "$lifecycle_verify_file|git merge-base"       "$lifecycle_verify_file|return **PARTIAL** citing the merge-base SHA"       "$lifecycle_implement_skill|Evaluate and execute the canonical \`merge-pr\` skill inline against \`<pr-number>\`; do not spawn a child for it."       "$lifecycle_merge_file|follow the target project's rules"       "$lifecycle_merge_file|Ready for Human Merge"       "$lifecycle_merge_file|--match-head-commit"; do
      if ! rg -Fq -- "${vm_check#*|}" "${vm_check%%|*}"; then
        echo "  ERROR: Verification or inline merge invariant missing from $(basename "$(dirname "${vm_check%%|*}")"): ${vm_check#*|}"
        ERRORS=$((ERRORS + 1))
        lifecycle_verify_merge_ok=false
      fi
    done
    if rg -Fq 'repeat until **PASS** or **N/A**' "$lifecycle_implement_skill" ||       rg -qi 'last line of defense|almost always something to verify' "$lifecycle_verify_file"; then
      echo "  ERROR: Verification must stay risk-scaled and capped"
      ERRORS=$((ERRORS + 1))
      lifecycle_verify_merge_ok=false
    fi
    if [ "$lifecycle_verify_merge_ok" = true ]; then
      echo "  OK: Verification focuses on real-world checks (max 2 cycles) and merge-pr runs inline following project rules"
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
    for ledger_field in '## Run Ledger' '- Risk & complexity:' '- Children:' '- Rounds: review' '- Fix commits:' '- Wall-clock:' '- Follow-up items:' '- Outcome:'; do
      if ! printf '%s' "$ledger_collapsed" | rg -Fq -- "$ledger_field"; then
        echo "  ERROR: implement run ledger template must collapse under <details> (blank line after </summary>) and include: $ledger_field"
        ERRORS=$((ERRORS + 1))
        ledger_ok=false
      fi
    done
    if [ "$ledger_ok" = true ]; then
      echo "  OK: implement prints a collapsed run ledger with risk/complexity, children, rounds, fix commits, wall-clock, and follow-ups"
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

    verify_step2=$(sed -n '/^### Step 2: Post Concise Verification Comment$/,$p' "$lifecycle_verify_file")
    verify_record_ok=true
    if [ -z "$(printf '%s\n' "$verify_step2" | lifecycle_details_lines rendered -)" ] || \
      printf '%s\n' "$verify_step2" | lifecycle_details_lines inside - | rg -q '^(### Verdict:|Verified-Head:)' || \
      ! printf '%s\n' "$verify_step2" | lifecycle_details_lines outside - | rg -Fq '### Verdict:' || \
      ! printf '%s\n' "$verify_step2" | lifecycle_details_lines outside - | rg -Fq 'Verified-Head:' || \
      ! rg -Fq 'keeping `### Verdict:` and `Verified-Head:` **outside** `<details>`' "$lifecycle_verify_file"; then
      echo "  ERROR: verify must keep Verdict and Verified-Head lines outside <details> and collapse evidence"
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
      echo "  OK: verify keeps Verdict and Verified-Head outside <details> and checks description claims against the diff"
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
    if ! rg -Fq 'Evaluate and execute the canonical `merge-pr` skill inline' "$lifecycle_implement_skill" || \
      ! rg -Fq 'do not spawn a child for it' "$lifecycle_implement_skill" || \
      ! rg -Fq 'never spawn a subagent' "$lifecycle_merge_file" || \
      ! rg -Fq 'do not spawn a child for it' "$lifecycle_merge_file" || \
      rg -q 'spawn a fresh subagent|pi-subagents|Task/subagent|isolated delegation' "$lifecycle_merge_file"; then
      echo "  ERROR: implement and merge-pr must execute Phase 6 inline without spawning a subagent"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: merge-pr runs inline without spawning a subagent"
    fi

    lifecycle_inline_slice_invalid=false
    for lifecycle_reviewer in review-general review-docs; do
      if ! rg -Fq 'judge against **this PR'"'"'s stated slice scope**' "$plugin_dir/skills/$lifecycle_reviewer/SKILL.md"; then
        echo "  ERROR: $lifecycle_reviewer must scope Part of #N reviews to the PR's stated slice scope"
        ERRORS=$((ERRORS + 1))
        lifecycle_inline_slice_invalid=true
      fi
    done
    if ! rg -Fq 'stating this slice'"'"'s scope and deferred parent-issue items' "$plugin_dir/skills/implement-code/SKILL.md"; then
      echo "  ERROR: implement-code must state Part of #N slice scope and deferred items in the PR description"
      ERRORS=$((ERRORS + 1))
      lifecycle_inline_slice_invalid=true
    fi
    if ! rg -Fq 'Use the inline findings supplied in the prompt when orchestrated' "$plugin_dir/skills/implement-address/SKILL.md"; then
      echo "  ERROR: implement-address must consume inline findings when orchestrated"
      ERRORS=$((ERRORS + 1))
      lifecycle_inline_slice_invalid=true
    fi
    if ! rg -Fq 'verify **this slice'"'"'s stated scope and changed behavior**' "$plugin_dir/skills/verify/SKILL.md"; then
      echo "  ERROR: verify must scope Part of #N checks to the PR's stated slice scope and changed behavior"
      ERRORS=$((ERRORS + 1))
      lifecycle_inline_slice_invalid=true
    fi
    if [ "$lifecycle_inline_slice_invalid" = false ]; then
      echo "  OK: Zero-scratch inline handoffs and Part of #N slice scoping enforced across workers, reviewers, and verifier"
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
