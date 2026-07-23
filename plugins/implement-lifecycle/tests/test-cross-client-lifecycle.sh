#!/bin/bash
# autotest — deterministic, non-destructive acceptance of the production dispatch contract
set -euo pipefail

PLUGIN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONTRACT="$PLUGIN_DIR/skills/implement/assets/dispatch-contract.sh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/implement-lifecycle-test.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
DISPATCH_LOG="$TMP_DIR/dispatch.log"
RESULT=""

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_equal() { [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"; }
assert_logged() { grep -Fxq -- "$1" "$DISPATCH_LOG" || fail "$2: missing dispatch '$1'"; }

# External effects are stubbed here; target resolution and state transitions are production code.
dispatch_stub() {
  client=$1
  worker=$2
  payload=$3
  target=$(bash "$CONTRACT" target "$client" "$worker")
  printf '%s|%s|%s\n' "$client" "$target" "$payload" >> "$DISPATCH_LOG"
  case "$worker|$payload" in
    implement-code*) RESULT="PR_NUMBER=731" ;;
    review-correctness*"round 1") RESULT="correctness=2" ;;
    review-security*"round 1") RESULT="security=0" ;;
    review-architecture*"round 1") RESULT="architecture=1" ;;
    review-testing*"round 1") RESULT="testing=1" ;;
    review-correctness*"round 2") RESULT="correctness=0" ;;
    review-security*"round 2") RESULT="security=0" ;;
    review-architecture*"round 2") RESULT="architecture=0" ;;
    review-testing*"round 2") RESULT="testing=0" ;;
    implement-address*" docs-1 "*) RESULT="ADDRESSED=docs-1" ;;
    implement-address*) RESULT="ADDRESSED=1" ;;
    review-docs*"round 1") RESULT="docs=1" ;;
    review-docs*"round 2") RESULT="docs=0" ;;
    verify*) RESULT="VERDICT=PASS" ;;
    merge-pr*) RESULT="MERGED=731" ;;
    *) fail "unhandled controlled dispatch: $worker $payload" ;;
  esac
}

run_lifecycle() {
  client=$1
  dispatch_stub "$client" implement-code "0 synthetic acceptance task"
  state=$(bash "$CONTRACT" transition implement "$RESULT")
  assert_equal "$state" review "$client implementation result propagation"
  pr_number=${RESULT#PR_NUMBER=}

  # Resolve the complete reviewer set as one production batch before launching workers.
  reviewer_targets=$(bash "$CONTRACT" targets "$client" \
    review-correctness review-security review-architecture review-testing)
  reviewer_target_count=$(printf '%s\n' "$reviewer_targets" | wc -l | tr -d ' ')
  assert_equal "$reviewer_target_count" 4 "$client parallel reviewer batch"

  round=1
  reviewer_results=()
  reviewer_pids=()
  for reviewer in correctness security architecture testing; do
    result_file="$TMP_DIR/$client-$reviewer-$round.result"
    (
      DISPATCH_LOG="$TMP_DIR/$client-$reviewer-$round.log"
      dispatch_stub "$client" "review-$reviewer" "Review PR #$pr_number, round $round"
      printf '%s\n' "$RESULT" > "$result_file"
    ) &
    reviewer_pids+=("$!")
  done
  for pid in "${reviewer_pids[@]}"; do wait "$pid"; done
  for reviewer in correctness security architecture testing; do
    cat "$TMP_DIR/$client-$reviewer-$round.log" >> "$DISPATCH_LOG"
    reviewer_results+=("$(cat "$TMP_DIR/$client-$reviewer-$round.result")")
  done
  state=$(bash "$CONTRACT" transition review "${reviewer_results[@]}")
  assert_equal "$state" address "$client findings drive address transition"
  findings_file="/tmp/implement-findings-pr-$pr_number-round-$round.md"
  dispatch_stub "$client" implement-address "$pr_number $round $findings_file"
  state=$(bash "$CONTRACT" transition address "$RESULT")
  assert_equal "$state" review "$client addresser result continues review"

  round=2
  reviewer_results=()
  reviewer_pids=()
  for reviewer in correctness security architecture testing; do
    result_file="$TMP_DIR/$client-$reviewer-$round.result"
    (
      DISPATCH_LOG="$TMP_DIR/$client-$reviewer-$round.log"
      dispatch_stub "$client" "review-$reviewer" "Review PR #$pr_number, round $round"
      printf '%s\n' "$RESULT" > "$result_file"
    ) &
    reviewer_pids+=("$!")
  done
  for pid in "${reviewer_pids[@]}"; do wait "$pid"; done
  for reviewer in correctness security architecture testing; do
    cat "$TMP_DIR/$client-$reviewer-$round.log" >> "$DISPATCH_LOG"
    reviewer_results+=("$(cat "$TMP_DIR/$client-$reviewer-$round.result")")
  done
  state=$(bash "$CONTRACT" transition review "${reviewer_results[@]}")
  assert_equal "$state" docs "$client clean reviewer results open docs gate"

  docs_round=1
  dispatch_stub "$client" review-docs "Review PR #$pr_number for documentation compliance, round $docs_round"
  state=$(bash "$CONTRACT" transition docs "$RESULT")
  assert_equal "$state" docs-address "$client docs findings drive address transition"
  docs_file="/tmp/implement-docs-findings-pr-$pr_number-round-$docs_round.md"
  dispatch_stub "$client" implement-address "$pr_number docs-$docs_round $docs_file"
  state=$(bash "$CONTRACT" transition docs-address "$RESULT")
  assert_equal "$state" docs "$client docs addresser result continues docs review"

  docs_round=2
  dispatch_stub "$client" review-docs "Review PR #$pr_number for documentation compliance, round $docs_round"
  state=$(bash "$CONTRACT" transition docs "$RESULT")
  assert_equal "$state" verify "$client clean docs result opens verification"
  dispatch_stub "$client" verify "$pr_number"
  state=$(bash "$CONTRACT" transition verify "$RESULT")
  assert_equal "$state" merge "$client PASS verdict opens merge gate"
  dispatch_stub "$client" merge-pr "$pr_number"
  state=$(bash "$CONTRACT" transition merge "$RESULT")
  assert_equal "$state" complete "$client merge result completes lifecycle"
}

for client in claude codex; do
  run_lifecycle "$client"
  prefix=""
  [ "$client" = codex ] && prefix='$implement-lifecycle:'
  assert_logged "$client|${prefix}implement-code|0 synthetic acceptance task" "$client implementation payload"
  for reviewer in correctness security architecture testing; do
    assert_logged "$client|${prefix}review-$reviewer|Review PR #731, round 1" "$client $reviewer round-one payload"
    assert_logged "$client|${prefix}review-$reviewer|Review PR #731, round 2" "$client $reviewer clean-result payload"
  done
  assert_logged "$client|${prefix}implement-address|731 1 /tmp/implement-findings-pr-731-round-1.md" "$client review address payload"
  assert_logged "$client|${prefix}review-docs|Review PR #731 for documentation compliance, round 1" "$client docs payload"
  assert_logged "$client|${prefix}implement-address|731 docs-1 /tmp/implement-docs-findings-pr-731-round-1.md" "$client docs address payload"
  assert_logged "$client|${prefix}verify|731" "$client verification payload"
  assert_logged "$client|${prefix}merge-pr|731" "$client merge payload"
done

# Required results must gate transitions; missing or partial reviewer output is a hard failure.
if bash "$CONTRACT" transition review correctness=0 security=0 architecture=0 >/dev/null 2>&1; then
  fail "review transition accepted a missing testing result"
fi
if bash "$CONTRACT" transition verify VERDICT=UNKNOWN >/dev/null 2>&1; then
  fail "verification transition accepted an unknown verdict"
fi

echo "PASS: real Claude/Codex skill targets, parallel specialist dispatch, and result-gated lifecycle transitions are covered with external effects stubbed."
