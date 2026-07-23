#!/bin/bash
# autotest — self-contained, non-destructive cross-client lifecycle acceptance harness
set -euo pipefail

PLUGIN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ORCHESTRATOR="$PLUGIN_DIR/skills/implement/SKILL.md"
FAILURES=0
DISPATCH_LOG=""
DISPATCH_RESULT=""

fail() {
  echo "FAIL: $*" >&2
  FAILURES=$((FAILURES + 1))
}

assert_contains() {
  file=$1
  expected=$2
  label=$3
  if ! grep -Fq -- "$expected" "$file"; then
    fail "$label: missing '$expected' in ${file#"$PLUGIN_DIR"/}"
  fi
}

assert_logged() {
  expected=$1
  label=$2
  if ! printf '%s\n' "$DISPATCH_LOG" | grep -Fxq -- "$expected"; then
    fail "$label: dispatch '$expected' was not observed"
  fi
}

assert_worker_contract() {
  worker=$1
  hint=$2
  file="$PLUGIN_DIR/skills/$worker/SKILL.md"
  assert_contains "$file" "context: fork" "$worker Claude fork context"
  assert_contains "$file" "agent: general-purpose" "$worker Claude worker agent"
  assert_contains "$file" "argument-hint: $hint" "$worker argument contract"
  if [ ! -f "$PLUGIN_DIR/skills/$worker/agents/openai.yaml" ]; then
    fail "$worker Codex discovery metadata is missing"
  fi
}

record_dispatch() {
  client=$1
  target=$2
  payload=$3
  if [ -n "$DISPATCH_LOG" ]; then
    DISPATCH_LOG="$DISPATCH_LOG
$client|$target|$payload"
  else
    DISPATCH_LOG="$client|$target|$payload"
  fi
}

target_for() {
  client=$1
  phase=$2
  if [ "$client" = "claude" ]; then
    case "$phase" in
      implement) echo "implement-code" ;;
      correctness) echo "review-correctness" ;;
      testing) echo "review-testing" ;;
      address) echo "implement-address" ;;
      docs) echo "review-docs" ;;
      verify) echo "verify" ;;
      merge) echo "merge-pr" ;;
    esac
  else
    case "$phase" in
      implement) echo '$implement-lifecycle:implement-code' ;;
      correctness) echo '$implement-lifecycle:review-correctness' ;;
      testing) echo '$implement-lifecycle:review-testing' ;;
      address) echo '$implement-lifecycle:implement-address' ;;
      docs) echo '$implement-lifecycle:review-docs' ;;
      verify) echo '$implement-lifecycle:verify' ;;
      merge) echo '$implement-lifecycle:merge-pr' ;;
    esac
  fi
}

mock_dispatch() {
  client=$1
  phase=$2
  payload=$3
  record_dispatch "$client" "$(target_for "$client" "$phase")" "$payload"
  case "$phase|$payload" in
    implement*) DISPATCH_RESULT="PR_NUMBER=731" ;;
    correctness*"round 1") DISPATCH_RESULT="FINDINGS=2" ;;
    testing*"round 1") DISPATCH_RESULT="FINDINGS=1" ;;
    correctness*"round 2") DISPATCH_RESULT="FINDINGS=0" ;;
    address*" docs-1 "*) DISPATCH_RESULT="ADDRESSED=docs-1" ;;
    address*) DISPATCH_RESULT="ADDRESSED=1" ;;
    docs*"round 1") DISPATCH_RESULT="FINDINGS=1" ;;
    docs*"round 2") DISPATCH_RESULT="FINDINGS=0" ;;
    verify*) DISPATCH_RESULT="VERDICT=PASS" ;;
    merge*) DISPATCH_RESULT="MERGE_GATE=READY" ;;
  esac
}

run_disposable_lifecycle() {
  client=$1
  task="0 synthetic acceptance task"
  round=1

  mock_dispatch "$client" implement "$task"
  pr_number=${DISPATCH_RESULT#PR_NUMBER=}
  if [ "$pr_number" != "731" ]; then
    fail "$client implementation result did not propagate a PR number"
  fi

  # Round one returns findings; both selected reviewers are dispatched before addressing.
  mock_dispatch "$client" correctness "Review PR #$pr_number, round $round"
  correctness_findings=${DISPATCH_RESULT#FINDINGS=}
  mock_dispatch "$client" testing "Review PR #$pr_number, round $round"
  testing_findings=${DISPATCH_RESULT#FINDINGS=}
  accepted_findings=$((correctness_findings + testing_findings))
  if [ "$accepted_findings" -le 0 ]; then
    fail "$client reviewer findings did not reach the address loop"
  fi
  findings_file="/tmp/implement-findings-pr-$pr_number-round-$round.md"
  mock_dispatch "$client" address "$pr_number $round $findings_file"

  # The addresser result continues the loop. Round two is clean and enters docs review.
  if [ "$DISPATCH_RESULT" != "ADDRESSED=1" ]; then
    fail "$client addresser result did not continue the review loop"
  fi
  round=2
  mock_dispatch "$client" correctness "Review PR #$pr_number, round $round"
  docs_round=1
  mock_dispatch "$client" docs "Review PR #$pr_number for documentation compliance, round $docs_round"
  docs_file="/tmp/implement-docs-findings-pr-$pr_number-round-$docs_round.md"
  mock_dispatch "$client" address "$pr_number docs-$docs_round $docs_file"
  docs_round=2
  mock_dispatch "$client" docs "Review PR #$pr_number for documentation compliance, round $docs_round"

  # A passing verifier propagates the same PR number into the merge gate.
  mock_dispatch "$client" verify "$pr_number"
  if [ "$DISPATCH_RESULT" != "VERDICT=PASS" ]; then
    fail "$client verification result did not open the merge gate"
  fi
  mock_dispatch "$client" merge "$pr_number"
  if [ "$DISPATCH_RESULT" != "MERGE_GATE=READY" ]; then
    fail "$client merge-gate dispatch did not complete"
  fi
}

assert_worker_contract "implement-code" "<issue-number-or-0> <task description, acceptance criteria, and optional instructions>"
assert_worker_contract "implement-address" "<pr-number> <round-identifier> <findings-file-path>"
assert_worker_contract "verify" "<pr-number>"

# Bind the simulation to the advertised orchestration contract rather than testing a copy alone.
assert_contains "$ORCHESTRATOR" "Always delegate implementation, addressing, verification, and specialist review work." "delegation invariant"
assert_contains "$ORCHESTRATOR" 'explicitly tell the subagent to use `$implement-lifecycle:implement-code`' "Codex implementation dispatch"
assert_contains "$ORCHESTRATOR" "Always invoke selected reviewers in parallel." "parallel review dispatch"
assert_contains "$ORCHESTRATOR" '<pr-number> <round-number> /tmp/implement-findings-pr-<PR>-round-<N>.md' "address payload"
assert_contains "$ORCHESTRATOR" '<pr-number> docs-<round-number> /tmp/implement-docs-findings-pr-<PR>-round-<N>.md' "docs address payload"
assert_contains "$ORCHESTRATOR" 'using `verify` in Claude Code or `$implement-lifecycle:verify` in Codex' "verification dispatch"
assert_contains "$ORCHESTRATOR" 'Use `merge-pr` in Claude Code or `$implement-lifecycle:merge-pr` in Codex' "merge dispatch"

for client in claude codex; do
  run_disposable_lifecycle "$client"
  prefix=""
  if [ "$client" = "codex" ]; then
    prefix='$implement-lifecycle:'
  fi
  assert_logged "$client|${prefix}implement-code|0 synthetic acceptance task" "$client implementation arguments"
  assert_logged "$client|${prefix}implement-address|731 1 /tmp/implement-findings-pr-731-round-1.md" "$client review address handoff"
  assert_logged "$client|${prefix}implement-address|731 docs-1 /tmp/implement-docs-findings-pr-731-round-1.md" "$client docs address handoff"
  assert_logged "$client|${prefix}verify|731" "$client verification PR propagation"
  assert_logged "$client|${prefix}merge-pr|731" "$client merge-gate PR propagation"
done

if [ "$FAILURES" -ne 0 ]; then
  echo "$FAILURES cross-client lifecycle acceptance assertion(s) failed" >&2
  exit 1
fi

echo "PASS: Claude Code and Codex lifecycle dispatch contracts preserve worker isolation, arguments, review/address continuation, docs review, verification, and merge-gate propagation."
