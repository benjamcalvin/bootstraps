#!/usr/bin/env bash
# Wrapper script that auto-resolves the scripts directory and invokes
# implement-cli via uv. Callable from any working directory.
#
# Usage:
#   /path/to/implement-cli/run.sh run-reviewers --pr 45 --round 1 --cwd .
#   /path/to/implement-cli/run.sh run-agent "prompt" --phase review --cwd .
#   /path/to/implement-cli/run.sh debug sessions /tmp/implement-cli-*/run_context.json
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$PLUGIN_DIR/scripts"

exec uv run --directory "$SCRIPTS_DIR" implement-cli "$@"
