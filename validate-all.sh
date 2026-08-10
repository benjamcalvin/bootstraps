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

# Validate each plugin
for plugin_dir in plugins/*/; do
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

  # Check skills
  for skill_dir in "$plugin_dir"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    if [ -f "$skill_dir/SKILL.md" ]; then
      if head -1 "$skill_dir/SKILL.md" | grep -q "^---$"; then
        echo "  OK: skills/$skill_name/SKILL.md has frontmatter"
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

    lifecycle_metadata_missing=false
    lifecycle_interface_section_missing=false
    lifecycle_explicit_invocation_missing=false
    lifecycle_skills=(
      implement-code implement-address review-general review-correctness review-security
      review-architecture review-testing review-docs verify
      implement merge-pr pr-check
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
    lifecycle_mapping=$(awk '/^\| Phase \| Canonical skill \|$/,/^$/' "$lifecycle_implement_skill")
    lifecycle_mapping_invalid=false
    for lifecycle_worker in implement-code implement-address review-general review-correctness review-security review-architecture review-testing review-docs verify; do
      mapping_count=$(printf '%s\n' "$lifecycle_mapping" | rg -Fc "\`$lifecycle_worker\`")
      if [ "$mapping_count" -ne 1 ]; then
        echo "  ERROR: Canonical lifecycle mapping must contain $lifecycle_worker exactly once (found $mapping_count)"
        ERRORS=$((ERRORS + 1))
        lifecycle_mapping_invalid=true
      fi
    done
    mapping_rows=$(printf '%s\n' "$lifecycle_mapping" | rg -c '^\| (Implement|Address|Review (general|correctness|security|architecture|testing|docs)|Verify) \|')
    if [ "$mapping_rows" -ne 9 ]; then
      echo "  ERROR: Canonical lifecycle mapping must contain exactly nine worker rows (found $mapping_rows)"
      ERRORS=$((ERRORS + 1))
      lifecycle_mapping_invalid=true
    fi
    for adapter_syntax in \
      'Use the implement-lifecycle:<skill> plugin skill' \
      'Use $implement-lifecycle:<skill>' \
      'generic `delegate` child with `skill: <skill>`' \
      'fresh isolated child, load the mapped Agent Skill explicitly'; do
      adapter_count=$(rg -Fc "$adapter_syntax" "$lifecycle_implement_skill")
      if [ "$adapter_count" -ne 1 ]; then
        echo "  ERROR: Lifecycle adapter syntax must be centralized exactly once: $adapter_syntax (found $adapter_count)"
        ERRORS=$((ERRORS + 1))
        lifecycle_mapping_invalid=true
      fi
    done
    if [ "$lifecycle_mapping_invalid" = false ]; then
      echo "  OK: Canonical lifecycle mapping contains each worker once and adapter syntax is centralized"
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
    for lifecycle_reviewer in review-general review-correctness review-security review-architecture review-testing review-docs; do
      if ! rg -Fq 'Do not modify the reviewed codebase.' "$plugin_dir/skills/$lifecycle_reviewer/SKILL.md" || \
        ! rg -Fq 'Do not post to GitHub.' "$plugin_dir/skills/$lifecycle_reviewer/SKILL.md"; then
        echo "  ERROR: $lifecycle_reviewer must prohibit modifying reviewed code and posting to GitHub"
        ERRORS=$((ERRORS + 1))
        lifecycle_reviewer_contract_missing=true
      fi
    done
    if [ "$lifecycle_reviewer_contract_missing" = false ]; then
      echo "  OK: Lifecycle reviewer skills prohibit modifying reviewed code and posting to GitHub"
    fi

    lifecycle_focused_contract='**Suite capability: `focused-only`. Run focused acceptance commands only. Do not run `./validate-all.sh`, an explicit shell invocation of that alias, or any full, complete, entire, repository-wide, or lifecycle-wide test suite. Final verification owns the authoritative suite.**'
    lifecycle_owner_contract='**Suite capability: `full-suite-owner`. Verification is the sole phase authorized to run the authoritative lifecycle-wide repository suite, at most once for the exact PR head.**'
    lifecycle_focused_skills=(
      implement implement-code implement-address review-general review-correctness
      review-security review-architecture review-testing review-docs merge-pr pr-check
    )
    lifecycle_suite_contract_invalid=false
    for lifecycle_skill in "${lifecycle_focused_skills[@]}"; do
      lifecycle_skill_file="$plugin_dir/skills/$lifecycle_skill/SKILL.md"
      if [ "$(rg -Fc '<!-- lifecycle-suite-capability: focused-only -->' "$lifecycle_skill_file")" -ne 1 ] || \
        [ "$(rg -Fc "$lifecycle_focused_contract" "$lifecycle_skill_file")" -ne 1 ]; then
        echo "  ERROR: $lifecycle_skill must declare focused-only exactly once with the canonical contract"
        ERRORS=$((ERRORS + 1))
        lifecycle_suite_contract_invalid=true
      fi

      while IFS= read -r suite_reference; do
        [ "$suite_reference" = "$lifecycle_focused_contract" ] && continue
        echo "  ERROR: $lifecycle_skill contains a non-canonical authoritative-suite reference: $suite_reference"
        ERRORS=$((ERRORS + 1))
        lifecycle_suite_contract_invalid=true
      done < <(rg -i -N '(\./validate-all\.sh|(^|[[:space:]])((ba|z|k)?sh)[[:space:]]+(\./)?validate-all\.sh|(^|[^[:alnum:]_])(full|complete|entire|repository-wide|lifecycle-wide)(-suite|[[:space:]]+(test[- ]?)?suite|[[:space:]]+tests?)([^[:alnum:]_]|$))' "$lifecycle_skill_file" || true)
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

    lifecycle_docs_graph=$(sed -n '/^<!-- lifecycle-docs-gate:v1$/,/^-->$/p' "$lifecycle_implement_skill")
    lifecycle_expected_docs_graph='<!-- lifecycle-docs-gate:v1
pending + review-docs -> reviewed
reviewed + zero-actionable -> clean
reviewed + actionable -> addressing
addressing + address-complete -> addressed
addressed + review-docs -> reviewed
reviewed + convergence-escalation -> escalated
addressed + convergence-escalation -> escalated
clean + enter-verification -> verification
-->'
    if [ "$lifecycle_docs_graph" != "$lifecycle_expected_docs_graph" ]; then
      echo "  ERROR: Lifecycle docs gate must match the authoritative review/address/re-review state graph"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Lifecycle docs gate requires a clean re-review before verification"
    fi

    lifecycle_recovery_graph=$(sed -n '/^<!-- lifecycle-reviewer-recovery:v1$/,/^-->$/p' "$lifecycle_implement_skill")
    lifecycle_expected_recovery_graph='<!-- lifecycle-reviewer-recovery:v1
delegated + nonempty-canonical-result -> complete
delegated + empty-or-incomplete-result -> incomplete
incomplete + transcript-recovery-complete -> complete
incomplete + transcript-recovery-incomplete -> fresh-retry
incomplete + transcript-recovery-unavailable -> fresh-retry
fresh-retry + nonempty-canonical-result -> complete
fresh-retry + empty-or-incomplete-result -> stop
complete + referee -> refereeing
-->'
    if [ "$lifecycle_recovery_graph" != "$lifecycle_expected_recovery_graph" ]; then
      echo "  ERROR: Lifecycle reviewer recovery must match the authoritative non-empty-result state graph"
      ERRORS=$((ERRORS + 1))
    elif [ "$(rg -Fc 'context: "fresh"' "$lifecycle_implement_skill")" -lt 3 ]; then
      echo '  ERROR: Pi delegation and recovery must set context: "fresh" explicitly'
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Pi reviewers use explicit fresh context and recover incomplete canonical results"
    fi

    lifecycle_reviewer_output_invalid=false
    for lifecycle_reviewer in review-general review-correctness review-security review-architecture review-testing review-docs; do
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

    if ! rg -Fq 'gh pr merge <pr-number> --squash --delete-branch --match-head-commit "$VERIFIED_SHA"' \
      "$plugin_dir/skills/merge-pr/SKILL.md" || \
      ! rg -Fq 'verification-head: <full-head-sha>' "$lifecycle_verify_file" || \
      ! rg -Fq 'suite-executions: 0 | 1' "$lifecycle_verify_file" || \
      ! rg -Fq 'suite-exit-status: <integer> | n/a' "$lifecycle_verify_file"; then
      echo "  ERROR: Verification evidence and merge must remain bound to the exact PR head"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: Verification evidence is exact-head and merge uses an atomic head guard"
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
