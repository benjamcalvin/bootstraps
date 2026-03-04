#!/bin/bash
# Validates all plugins in the marketplace
set -euo pipefail

ERRORS=0
WARNINGS=0

echo "=== Bootstraps Plugin Validation ==="
echo ""

# Check marketplace.json exists and is valid JSON
if [ ! -f "marketplace.json" ]; then
  echo "ERROR: marketplace.json not found"
  ERRORS=$((ERRORS + 1))
else
  if ! jq . marketplace.json > /dev/null 2>&1; then
    echo "ERROR: marketplace.json is not valid JSON"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK: marketplace.json is valid JSON"
  fi
fi

echo ""

# Validate each plugin
for plugin_dir in plugins/*/; do
  plugin_name=$(basename "$plugin_dir")
  echo "--- Plugin: $plugin_name ---"

  # Check plugin.json
  if [ ! -f "$plugin_dir/plugin.json" ]; then
    echo "  ERROR: Missing plugin.json"
    ERRORS=$((ERRORS + 1))
  else
    if ! jq . "$plugin_dir/plugin.json" > /dev/null 2>&1; then
      echo "  ERROR: plugin.json is not valid JSON"
      ERRORS=$((ERRORS + 1))
    else
      # Check required fields
      name=$(jq -r '.name // empty' "$plugin_dir/plugin.json")
      desc=$(jq -r '.description // empty' "$plugin_dir/plugin.json")
      version=$(jq -r '.version // empty' "$plugin_dir/plugin.json")

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

  # Check SKILL.md
  if [ -f "$plugin_dir/SKILL.md" ]; then
    if head -1 "$plugin_dir/SKILL.md" | grep -q "^---$"; then
      echo "  OK: SKILL.md has frontmatter"
    else
      echo "  WARN: SKILL.md missing frontmatter delimiter"
      WARNINGS=$((WARNINGS + 1))
    fi

    # Check line count
    lines=$(wc -l < "$plugin_dir/SKILL.md")
    if [ "$lines" -gt 500 ]; then
      echo "  WARN: SKILL.md is $lines lines (recommended: < 500)"
      WARNINGS=$((WARNINGS + 1))
    else
      echo "  OK: SKILL.md is $lines lines"
    fi
  fi

  # Check hooks.json if present
  if [ -f "$plugin_dir/hooks/hooks.json" ]; then
    if ! jq . "$plugin_dir/hooks/hooks.json" > /dev/null 2>&1; then
      echo "  ERROR: hooks/hooks.json is not valid JSON"
      ERRORS=$((ERRORS + 1))
    else
      echo "  OK: hooks/hooks.json is valid JSON"
    fi
  fi

  # Check marketplace.json references this plugin
  if [ -f "marketplace.json" ]; then
    if jq -e ".plugins[] | select(.name == \"$plugin_name\")" marketplace.json > /dev/null 2>&1; then
      echo "  OK: Listed in marketplace.json"
    else
      echo "  WARN: Not listed in marketplace.json"
      WARNINGS=$((WARNINGS + 1))
    fi
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
