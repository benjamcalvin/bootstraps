#!/usr/bin/env bash
set -euo pipefail
# autotest — self-contained, no external dependencies; run by validate-all.sh

# test-bg-wait-pattern.sh — Regression tests for the background-wait fast-path regex.
#
# Runs a table-driven test against BG_WAIT_PATTERN from stop-guard.sh.
# No external dependencies (no Gemini, no transcript, no jq).
#
# Usage:
#   ./test-bg-wait-pattern.sh

# Extract the pattern from stop-guard.sh so tests stay in sync.
# NOTE: assumes BG_WAIT_PATTERN is a single-quoted assignment on one line.
# The empty-check below catches breakage if the format changes.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BG_WAIT_PATTERN=$(grep "^BG_WAIT_PATTERN=" "$SCRIPT_DIR/stop-guard.sh" | sed "s/^BG_WAIT_PATTERN='//;s/'$//")

if [ -z "$BG_WAIT_PATTERN" ]; then
  echo "FAIL: could not extract BG_WAIT_PATTERN from stop-guard.sh"
  exit 1
fi

PASS=0
FAIL=0

expect_match() {
  if echo "$1" | grep -qiE "$BG_WAIT_PATTERN"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected match):    $1"
    FAIL=$((FAIL + 1))
  fi
}

expect_nomatch() {
  if echo "$1" | grep -qiE "$BG_WAIT_PATTERN"; then
    echo "FAIL (unexpected match):  $1"
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi
}

echo "=== Background-Wait Pattern Tests ==="
echo ""

# --- True positives: messages about waiting for background agents ---
expect_match "I have launched the specialist reviewers in background and will be notified when they complete."
expect_match "Waiting for the background agents to return results."
expect_match "Waiting for parallel reviewer tasks to finish."
expect_match "I launched the review agents in the background."
expect_match "Waiting for specialist reviewers to complete their analysis."
expect_match "I will be notified when the background agents are done."
expect_match "Waiting for background task results."
expect_match "I will be notified when the reviewer tasks complete."
expect_match "Launched the background agent tasks in the background."
expect_match "Waiting for the parallel agents to return."

# --- True negatives: messages that should NOT trigger the fast-path ---
expect_nomatch "I am waiting for your feedback on the task before proceeding."
expect_nomatch "Still waiting for the test results to appear in CI."
expect_nomatch "You will be notified when the PR checks complete."
expect_nomatch "The function launched a goroutine in the background."
expect_nomatch "We launched the cleanup task runner in the background."
expect_nomatch "You will be notified when the deployment is done."
expect_nomatch "I have completed the implementation and all tests pass."
expect_nomatch "Waiting for the API to return the result."
expect_nomatch "I am waiting for user input."
expect_nomatch "The task is complete."
expect_nomatch "Launched a new feature branch."

echo ""
echo "Results: $PASS passed, $FAIL failed ($(( PASS + FAIL )) total)"

if [ "$FAIL" -gt 0 ]; then
  echo "FAILED"
  exit 1
fi

echo "PASSED"
