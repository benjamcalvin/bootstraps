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
assert_rejected() {
  description=$1
  shift
  if "$@" >/dev/null 2>&1; then fail "$description was accepted"; fi
}

review_output() {
  reviewer=$1
  findings=$2
  case "$reviewer" in
    correctness) label=Correctness ;;
    security) label=Security ;;
    architecture) label=Architecture ;;
    testing) label=Testing ;;
    docs) label=Docs ;;
  esac
  if [ "$findings" -gt 0 ]; then
    printf '### Action Required\n'
    index=1
    while [ "$index" -le "$findings" ]; do
      printf -- '- **[%s]** Finding %s with file:line and details\n' "$label" "$index"
      index=$((index + 1))
    done
    printf '\n'
  fi
  printf '### Summary\n%s review complete.\n' "$label"
}

address_output() {
  cat <<'EOF'
| # | Finding | Action | Details |
|---|---------|--------|---------|
| 1 | Contract issue | Applied | Updated and verified. |

**Tests:** ./validate-all.sh — passed
**Commits:** fix: address review round 3 — contract
EOF
}

merge_output() {
  cat <<'EOF'
## Merge Complete

**PR:** #731 — feat: synthetic acceptance
**Merged to:** main
**Issues updated:** none
EOF
}

# External effects are stubbed here; target resolution and state transitions are production code.
dispatch_stub() {
  client=$1
  worker=$2
  payload=$3
  target=$(bash "$CONTRACT" target "$client" "$worker")
  printf '%s|%s|%s\n' "$client" "$target" "$payload" >> "$DISPATCH_LOG"
  case "$worker|$payload" in
    implement-code*) RESULT=$'PR_NUMBER: 731\nPR_TITLE: feat: synthetic acceptance\nSUMMARY: Implemented.' ;;
    review-correctness*"round 1") RESULT=$(review_output correctness 2) ;;
    review-security*"round 1") RESULT=$(review_output security 0) ;;
    review-architecture*"round 1") RESULT=$(review_output architecture 1) ;;
    review-testing*"round 1") RESULT=$(review_output testing 1) ;;
    review-*"round 2") reviewer=${worker#review-}; RESULT=$(review_output "$reviewer" 0) ;;
    implement-address*) RESULT=$(address_output) ;;
    review-docs*"round 1") RESULT=$(review_output docs 1) ;;
    review-docs*"round 2") RESULT=$(review_output docs 0) ;;
    verify*) RESULT=$'## End-to-End Verification — PR #731\n\n### Verdict: PASS\n\n### Evidence\nVerified.' ;;
    merge-pr*) RESULT=$(merge_output) ;;
    *) fail "unhandled controlled dispatch: $worker $payload" ;;
  esac
}

run_review_batch() {
  client=$1
  round=$2
  shift 2
  selected=("$@")
  workers=()
  for reviewer in "${selected[@]}"; do workers+=("review-$reviewer"); done
  targets=$(bash "$CONTRACT" targets "$client" "${workers[@]}")
  target_count=$(printf '%s\n' "$targets" | wc -l | tr -d ' ')
  assert_equal "$target_count" "${#selected[@]}" "$client selected reviewer target count"

  results=()
  pids=()
  for reviewer in "${selected[@]}"; do
    result_file="$TMP_DIR/$client-$reviewer-$round.result"
    (
      DISPATCH_LOG="$TMP_DIR/$client-$reviewer-$round.log"
      dispatch_stub "$client" "review-$reviewer" "Review PR #731, round $round"
      printf '%s\n' "$RESULT" > "$result_file"
    ) &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
  for reviewer in "${selected[@]}"; do
    cat "$TMP_DIR/$client-$reviewer-$round.log" >> "$DISPATCH_LOG"
    results+=("$(cat "$TMP_DIR/$client-$reviewer-$round.result")")
  done
  bash "$CONTRACT" transition review --reviewers "${selected[@]}" -- "${results[@]}"
}

run_lifecycle() {
  client=$1
  dispatch_stub "$client" implement-code "0 synthetic acceptance task"
  state=$(bash "$CONTRACT" transition implement "$RESULT")
  assert_equal "$state" review "$client implementation result propagation"

  state=$(run_review_batch "$client" 1 correctness security architecture testing)
  assert_equal "$state" address "$client findings drive address transition"
  dispatch_stub "$client" implement-address "731 1 /tmp/implement-findings-pr-731-round-1.md"
  state=$(bash "$CONTRACT" transition address "$RESULT")
  assert_equal "$state" review "$client addresser result continues review"

  state=$(run_review_batch "$client" 2 correctness security architecture testing)
  assert_equal "$state" docs "$client clean reviewer results open docs gate"
  dispatch_stub "$client" review-docs "Review PR #731 for documentation compliance, round 1"
  state=$(bash "$CONTRACT" transition docs "$RESULT")
  assert_equal "$state" docs-address "$client docs findings drive address transition"
  dispatch_stub "$client" implement-address "731 docs-1 /tmp/implement-docs-findings-pr-731-round-1.md"
  state=$(bash "$CONTRACT" transition docs-address "$RESULT")
  assert_equal "$state" docs "$client docs addresser result continues docs review"
  dispatch_stub "$client" review-docs "Review PR #731 for documentation compliance, round 2"
  state=$(bash "$CONTRACT" transition docs "$RESULT")
  assert_equal "$state" verify "$client clean docs result opens verification"
  dispatch_stub "$client" verify 731
  state=$(bash "$CONTRACT" transition verify "$RESULT")
  assert_equal "$state" merge "$client PASS verdict opens merge gate"
  state=$(bash "$CONTRACT" transition verify $'### Verdict: FAIL\n')
  assert_equal "$state" address "$client FAIL verdict returns to addressing"
  state=$(bash "$CONTRACT" transition verify $'### Verdict: PARTIAL\n')
  assert_equal "$state" address "$client PARTIAL verdict returns to addressing"
  state=$(bash "$CONTRACT" transition verify $'### Verdict: N/A\n')
  assert_equal "$state" merge "$client N/A verdict opens merge gate"
  dispatch_stub "$client" merge-pr 731
  state=$(bash "$CONTRACT" transition merge "$RESULT")
  assert_equal "$state" complete "$client merge result completes lifecycle"

  # Explicit one- and multi-reviewer subsets are dispatched in parallel by the same path.
  state=$(run_review_batch "$client" 1 correctness)
  assert_equal "$state" address "$client one-reviewer selection"
  state=$(run_review_batch "$client" 2 security testing)
  assert_equal "$state" docs "$client multi-reviewer selection"
}

for client in claude codex; do
  run_lifecycle "$client"
  prefix=""
  [ "$client" = codex ] && prefix='$implement-lifecycle:'
  assert_logged "$client|${prefix}implement-code|0 synthetic acceptance task" "$client implementation payload"
  assert_logged "$client|${prefix}implement-address|731 1 /tmp/implement-findings-pr-731-round-1.md" "$client address payload"
  assert_logged "$client|${prefix}review-docs|Review PR #731 for documentation compliance, round 1" "$client docs payload"
  assert_logged "$client|${prefix}verify|731" "$client verification payload"
  assert_logged "$client|${prefix}merge-pr|731" "$client merge payload"
done

# Claude reviewers are named agents; Codex reviewers are skill wrappers.
assert_equal "$(bash "$CONTRACT" target claude review-correctness)" review-correctness "Claude named reviewer entry point"
assert_equal "$(bash "$CONTRACT" target codex review-correctness)" '$implement-lifecycle:review-correctness' "Codex reviewer skill entry point"

# Every phase fails closed for missing, empty, malformed, duplicate, partial, or extra results.
GOOD_REVIEW=$(review_output correctness 0)
GOOD_ADDRESS=$(address_output)
assert_rejected "missing implementation output" bash "$CONTRACT" transition implement
assert_rejected "empty implementation output" bash "$CONTRACT" transition implement ""
assert_rejected "zero PR number" bash "$CONTRACT" transition implement 'PR_NUMBER: 0'
assert_rejected "malformed PR number" bash "$CONTRACT" transition implement 'PR_NUMBER: abc'
assert_rejected "duplicate PR number" bash "$CONTRACT" transition implement $'PR_NUMBER: 1\nPR_NUMBER: 2'
assert_rejected "missing reviewer selection" bash "$CONTRACT" transition review "$GOOD_REVIEW"
assert_rejected "empty reviewer selection" bash "$CONTRACT" transition review --reviewers -- "$GOOD_REVIEW"
assert_rejected "missing reviewer output" bash "$CONTRACT" transition review --reviewers correctness --
assert_rejected "empty reviewer output" bash "$CONTRACT" transition review --reviewers correctness -- ""
assert_rejected "partial selected reviewer output" bash "$CONTRACT" transition review --reviewers correctness testing -- "$GOOD_REVIEW"
assert_rejected "extra reviewer output" bash "$CONTRACT" transition review --reviewers correctness -- "$GOOD_REVIEW" "$GOOD_REVIEW"
assert_rejected "duplicate reviewer" bash "$CONTRACT" transition review --reviewers correctness correctness -- "$GOOD_REVIEW" "$GOOD_REVIEW"
assert_rejected "unknown reviewer" bash "$CONTRACT" transition review --reviewers docs -- "$(review_output docs 0)"
assert_rejected "mismatched reviewer tag" bash "$CONTRACT" transition review --reviewers correctness -- "$(review_output testing 1)"
assert_rejected "malformed reviewer output" bash "$CONTRACT" transition review --reviewers correctness -- '### Summary'
for phase in address docs-address; do
  assert_rejected "missing $phase output" bash "$CONTRACT" transition "$phase"
  assert_rejected "empty $phase output" bash "$CONTRACT" transition "$phase" ""
  assert_rejected "malformed $phase output" bash "$CONTRACT" transition "$phase" '| # | Finding | Action | Details |'
  assert_rejected "unsuccessful $phase result" bash "$CONTRACT" transition "$phase" "${GOOD_ADDRESS/Applied/Escalated}"
done
assert_rejected "missing docs output" bash "$CONTRACT" transition docs
assert_rejected "empty docs output" bash "$CONTRACT" transition docs ""
assert_rejected "malformed docs output" bash "$CONTRACT" transition docs "$(review_output correctness 1)"
assert_rejected "missing verification output" bash "$CONTRACT" transition verify
assert_rejected "empty verification output" bash "$CONTRACT" transition verify ""
assert_rejected "unknown verification verdict" bash "$CONTRACT" transition verify '### Verdict: UNKNOWN'
assert_rejected "duplicate verification verdict" bash "$CONTRACT" transition verify $'### Verdict: PASS\n### Verdict: FAIL'
assert_rejected "missing merge output" bash "$CONTRACT" transition merge
assert_rejected "empty merge output" bash "$CONTRACT" transition merge ""
assert_rejected "malformed merge output" bash "$CONTRACT" transition merge $'## Merge Complete\n**PR:** #0 — bad\n**Merged to:** main'

echo "PASS: documented worker outputs, client-specific entry points, dynamic parallel reviewer subsets, and fail-closed lifecycle transitions are covered."
