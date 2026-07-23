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
  category=${3:-Action Required}
  label_override=${4:-}
  pr=${5:-731}
  round=${6:-1}
  type=${7:-code}
  case "$reviewer" in
    correctness) label=Correctness ;;
    security) label=Security ;;
    architecture) label=Architecture ;;
    testing) label=Testing ;;
    docs) label=Docs ;;
  esac
  [ -z "$label_override" ] || label=$label_override
  printf '## Review Result\n**PR:** #%s\n**Round:** %s\n**Type:** %s\n**Reviewer:** %s\n\n' "$pr" "$round" "$type" "$reviewer"
  if [ "$findings" -gt 0 ]; then
    printf '### %s\n' "$category"
    index=1
    while [ "$index" -le "$findings" ]; do
      printf -- '- **[%s]** Finding %s with file:line and details\n' "$label" "$index"
      index=$((index + 1))
    done
    printf '\n'
  fi
  printf '### Summary\n%s review complete.\n' "$label"
}

verification_output() {
  verdict=$1
  printf '## End-to-End Verification — PR #731\n\n### Verdict: %s\n\n' "$verdict"
  printf '### System Flow Verified\nTrigger through downstream outcome completed.\n\n### Evidence\n#### Synthetic scenario\n'
  if [ "$verdict" = FAIL ]; then
    printf '**Result:** FAIL — complete flow failed.\n\n### Issues Found\n- **[Verification]** End-to-end flow failed at app:42; expected success but observed failure.\n\n'
  elif [ "$verdict" = PARTIAL ]; then
    printf '**Result:** PARTIAL — only part of the flow completed.\n\n### Issues Found\n- **[Verification]** End-to-end flow partially failed at app:42.\n\n'
  else
    printf '**Result:** PASS — complete flow succeeded.\n\n'
    printf '### Issues Found\nNone\n\n'
  fi
  printf '### Holistic Assessment\nSynthetic verification complete.\n'
}

na_verification_output() {
  printf '## End-to-End Verification — PR #731\n\n### Verdict: N/A\n\nPure documentation change — no code, configuration, or build artifacts affected.\n'
}

address_output() {
  phase=$1
  round=$2
  shift 2
  ids=("${@:-1}")
  printf '## Address Result\n**PR:** #731\n**Round:** %s\n**Phase:** %s\n\n### Findings\n' "$round" "$phase"
  cat <<'EOF'
| # | Finding | Action | Details |
|---|---------|--------|---------|
EOF
  for id in "${ids[@]}"; do printf '| %s | Contract issue | Applied | Updated and verified. |\n' "$id"; done
  cat <<'EOF'

### Tests
- **Command:** `./validate-all.sh`
- **Result:** all validators passed
- **Status:** PASS
### Commits
- `abcdef1` — `fix: address lifecycle contract`
EOF
}

merge_output() {
  cat <<'EOF'
## Merge Complete

**PR:** #731 — feat: synthetic acceptance
**Base:** main
**Issues updated:** none

### Changes
- Added synthetic lifecycle acceptance.
EOF
}

# External effects are stubbed here; target resolution and state transitions are production code.
dispatch_stub() {
  client=$1
  worker=$2
  payload=$3
  target=$(bash "$CONTRACT" target "$client" "$worker")
  printf '%s|%s|%s\n' "$client" "$target" "$payload" >> "$DISPATCH_LOG"
  if [[ "$worker" = review-* ]] && [ -n "${REVIEW_BARRIER_DIR:-}" ]; then
    : > "$REVIEW_BARRIER_DIR/${REVIEW_BARRIER_MEMBER}.ready"
    while [ ! -f "$REVIEW_BARRIER_DIR/release" ]; do sleep 0.01; done
  fi
  case "$worker|$payload" in
    implement-code*) RESULT=$'PR_NUMBER: 731\nPR_TITLE: feat: synthetic acceptance\nSUMMARY: Implemented.' ;;
    review-correctness*"round 1") RESULT=$(review_output correctness 2) ;;
    review-security*"round 1") RESULT=$(review_output security 0) ;;
    review-architecture*"round 1") RESULT=$(review_output architecture 1) ;;
    review-testing*"round 1") RESULT=$(review_output testing 1) ;;
    review-docs*"round 1") RESULT=$(review_output docs 1 "" "" 731 1 docs) ;;
    review-docs*"round 2") RESULT=$(review_output docs 0 "" "" 731 2 docs) ;;
    review-*"round 2") reviewer=${worker#review-}; RESULT=$(review_output "$reviewer" 0 "" "" 731 2 code) ;;
    implement-address*"docs-1"*) RESULT=$(address_output docs docs-1) ;;
    implement-address*"verification-1"*) RESULT=$(address_output verification verification-1) ;;
    implement-address*) RESULT=$(address_output code 1) ;;
    verify*) RESULT=$(verification_output "${VERIFY_VERDICT:-PASS}") ;;
    merge-pr*) RESULT=$(merge_output) ;;
    *) fail "unhandled controlled dispatch: $worker $payload" ;;
  esac
}

run_review_batch() {
  client=$1
  round=$2
  accepted=$3
  shift 3
  selected=("$@")
  workers=()
  for reviewer in "${selected[@]}"; do workers+=("review-$reviewer"); done
  targets=$(bash "$CONTRACT" targets "$client" "${workers[@]}")
  target_count=$(printf '%s\n' "$targets" | wc -l | tr -d ' ')
  assert_equal "$target_count" "${#selected[@]}" "$client selected reviewer target count"

  results=()
  pids=()
  barrier_dir=$(mktemp -d "$TMP_DIR/reviewer-barrier.XXXXXX")
  for reviewer in "${selected[@]}"; do
    result_file="$TMP_DIR/$client-$reviewer-$round.result"
    (
      DISPATCH_LOG="$TMP_DIR/$client-$reviewer-$round.log"
      REVIEW_BARRIER_DIR=$barrier_dir
      REVIEW_BARRIER_MEMBER=$reviewer
      dispatch_stub "$client" "review-$reviewer" "Review PR #731, round $round"
      printf '%s\n' "$RESULT" > "$result_file"
    ) &
    pids+=("$!")
  done
  attempts=0
  while :; do
    ready=0
    for reviewer in "${selected[@]}"; do
      [ -f "$barrier_dir/$reviewer.ready" ] && ready=$((ready + 1))
    done
    [ "$ready" -eq "${#selected[@]}" ] && break
    attempts=$((attempts + 1))
    [ "$attempts" -lt 500 ] || fail "$client reviewer stubs did not overlap at the synchronization barrier"
    sleep 0.01
  done
  : > "$barrier_dir/release"
  for pid in "${pids[@]}"; do wait "$pid"; done
  for reviewer in "${selected[@]}"; do
    cat "$TMP_DIR/$client-$reviewer-$round.log" >> "$DISPATCH_LOG"
    results+=("$(cat "$TMP_DIR/$client-$reviewer-$round.result")")
  done
  raw_count=$(bash "$CONTRACT" validate review --pr 731 --round "$round" --reviewers "${selected[@]}" -- "${results[@]}")
  [ "$raw_count" -ge "$accepted" ] || fail "$client accepted reviewer count exceeds validated raw count"
  bash "$CONTRACT" transition review --pr 731 --round "$round" --accepted-count "$accepted" --reviewers "${selected[@]}" -- "${results[@]}"
}

run_lifecycle() {
  client=$1
  dispatch_stub "$client" implement-code "0 synthetic acceptance task"
  state=$(bash "$CONTRACT" transition implement "$RESULT")
  assert_equal "$state" review "$client implementation result propagation"

  state=$(run_review_batch "$client" 1 2 correctness security architecture testing)
  assert_equal "$state" address "$client mixed accepted and rejected findings drive address transition"
  dispatch_stub "$client" implement-address "731 1 /tmp/implement-findings-pr-731-round-1.md"
  state=$(bash "$CONTRACT" transition address --pr 731 --round 1 --finding-ids 1 3 -- "$(address_output code 1 1 3)")
  assert_equal "$state" review "$client addresser result continues review"

  state=$(run_review_batch "$client" 2 0 correctness security architecture testing)
  assert_equal "$state" docs "$client clean reviewer results open docs gate"
  dispatch_stub "$client" review-docs "Review PR #731 for documentation compliance, round 1"
  assert_equal "$(bash "$CONTRACT" validate docs --pr 731 --round 1 -- "$RESULT")" 1 "$client raw docs validation with findings"
  state=$(bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 1 -- "$RESULT")
  assert_equal "$state" docs-address "$client docs findings drive address transition"
  dispatch_stub "$client" implement-address "731 docs-1 /tmp/implement-docs-findings-pr-731-round-1.md"
  state=$(bash "$CONTRACT" transition docs-address --pr 731 --round docs-1 --finding-ids 1 -- "$RESULT")
  assert_equal "$state" docs "$client docs addresser result continues docs review"
  dispatch_stub "$client" review-docs "Review PR #731 for documentation compliance, round 2"
  assert_equal "$(bash "$CONTRACT" validate docs --pr 731 --round 2 -- "$RESULT")" 0 "$client raw clean docs validation"
  state=$(bash "$CONTRACT" transition docs --pr 731 --round 2 --accepted-count 0 -- "$RESULT")
  assert_equal "$state" verify "$client clean docs result opens verification"
  VERIFY_VERDICT=FAIL
  dispatch_stub "$client" verify 731
  state=$(bash "$CONTRACT" transition verify --pr 731 -- "$RESULT")
  assert_equal "$state" verification-address "$client FAIL verdict opens verification-specific addressing"
  verification_findings="$TMP_DIR/implement-verification-findings-pr-731-round-1.md"
  printf '# Verification Findings — Round 1\n\n| # | Finding | Severity | Details |\n|---|---------|----------|---------|\n| 1 | End-to-end flow failed | Action Required | app:42 expected success but observed failure. |\n' > "$verification_findings"
  dispatch_stub "$client" implement-address "731 verification-1 $verification_findings"
  state=$(bash "$CONTRACT" transition verification-address --pr 731 --round verification-1 --finding-ids 1 -- "$RESULT")
  assert_equal "$state" verify "$client verification addresser result requires reverification"
  VERIFY_VERDICT=PASS
  dispatch_stub "$client" verify 731
  state=$(bash "$CONTRACT" transition verify --pr 731 -- "$RESULT")
  assert_equal "$state" merge "$client PASS reverification opens merge gate"
  state=$(bash "$CONTRACT" transition verify --pr 731 -- "$(verification_output PARTIAL)")
  assert_equal "$state" verification-address "$client PARTIAL verdict opens verification-specific addressing"
  state=$(bash "$CONTRACT" transition verify --pr 731 -- "$(na_verification_output)")
  assert_equal "$state" merge "$client N/A verdict opens merge gate"
  dispatch_stub "$client" merge-pr 731
  state=$(bash "$CONTRACT" transition merge --pr 731 --base main --title "feat: synthetic acceptance" -- "$RESULT")
  assert_equal "$state" complete "$client merge result completes lifecycle"

  # Explicit one- and multi-reviewer subsets are dispatched in parallel by the same path.
  state=$(run_review_batch "$client" 1 1 correctness)
  assert_equal "$state" address "$client one-reviewer selection"
  state=$(run_review_batch "$client" 2 0 security testing)
  assert_equal "$state" docs "$client multi-reviewer selection"
}

for client in claude codex; do
  run_lifecycle "$client"
  prefix=""
  [ "$client" = codex ] && prefix='$implement-lifecycle:'
  assert_logged "$client|${prefix}implement-code|0 synthetic acceptance task" "$client implementation payload"
  assert_logged "$client|${prefix}implement-address|731 1 /tmp/implement-findings-pr-731-round-1.md" "$client address payload"
  assert_logged "$client|${prefix}implement-address|731 verification-1 $TMP_DIR/implement-verification-findings-pr-731-round-1.md" "$client verification address payload"
  assert_logged "$client|${prefix}review-docs|Review PR #731 for documentation compliance, round 1" "$client docs payload"
  assert_logged "$client|${prefix}verify|731" "$client verification payload"
  assert_logged "$client|${prefix}merge-pr|731" "$client merge payload"
done

# Claude reviewers are named agents; Codex reviewers are skill wrappers.
assert_equal "$(bash "$CONTRACT" target claude review-correctness)" review-correctness "Claude named reviewer entry point"
assert_equal "$(bash "$CONTRACT" target codex review-correctness)" '$implement-lifecycle:review-correctness' "Codex reviewer skill entry point"

# Raw envelopes are validated independently; explicit post-referee counts control transitions.
RAW_TWO=$(review_output correctness 2)
assert_equal "$(bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness -- "$RAW_TWO")" docs "all code findings rejected by referee"
assert_equal "$(bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 1 --reviewers correctness -- "$RAW_TWO")" address "mixed accepted and rejected code findings"
assert_equal "$(bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness -- "$(review_output correctness 0)")" docs "zero raw code findings"
DOCS_TWO=$(review_output docs 2 "" "" 731 1 docs)
assert_equal "$(bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 0 -- "$DOCS_TWO")" verify "all docs findings rejected by referee"
assert_equal "$(bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 1 -- "$DOCS_TWO")" docs-address "mixed accepted and rejected docs findings"
assert_equal "$(bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 0 -- "$(review_output docs 0 "" "" 731 1 docs)")" verify "zero raw docs findings"

# Every documented category and security/requirements label is accepted in its valid position.
assert_equal "$(bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 1 --reviewers correctness -- "$(review_output correctness 1 Recommended)")" address "Recommended category"
assert_equal "$(bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 1 --reviewers architecture -- "$(review_output architecture 1 Minor)")" address "Minor category"
assert_equal "$(bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 1 --reviewers security -- "$(review_output security 1 Recommended Requirements)")" address "Requirements label"
assert_equal "$(bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 1 -- "$(review_output docs 1 Recommended "" 731 1 docs)")" docs-address "docs Recommended category"
assert_equal "$(bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 1 -- "$(review_output docs 1 Minor "" 731 1 docs)")" docs-address "docs Minor category"
ORDERED_REVIEW=$'## Review Result\n**PR:** #731\n**Round:** 1\n**Type:** code\n**Reviewer:** security\n\n### Action Required\n- **[Security]** Required.\n### Recommended\n- **[Requirements]** Recommended.\n### Minor\n- **[Security]** Minor.\n### Summary\nSecurity and requirements review complete.'
assert_equal "$(bash "$CONTRACT" validate review --pr 731 --round 1 --reviewers security -- "$ORDERED_REVIEW")" 3 "all ordered reviewer categories"
ORDERED_DOCS=$'## Review Result\n**PR:** #731\n**Round:** 1\n**Type:** docs\n**Reviewer:** docs\n\n### Action Required\n- **[Docs]** Required.\n### Recommended\n- **[Docs]** Recommended.\n### Minor\n- **[Docs]** Minor.\n### Summary\nDocumentation review complete.'
assert_equal "$(bash "$CONTRACT" validate docs --pr 731 --round 1 -- "$ORDERED_DOCS")" 3 "all ordered docs categories"
MULTILINE_REVIEW=$'## Review Result\n**PR:** #731\n**Round:** 1\n**Type:** code\n**Reviewer:** correctness\n\n### Summary\nFirst prose sentence.\nSecond prose sentence.'
MULTILINE_DOCS=$'## Review Result\n**PR:** #731\n**Round:** 1\n**Type:** docs\n**Reviewer:** docs\n\n### Summary\nFirst prose sentence.\nSecond prose sentence.'
assert_equal "$(bash "$CONTRACT" validate review --pr 731 --round 1 --reviewers correctness -- "$MULTILINE_REVIEW")" 0 "multiline plain-prose review summary"
assert_equal "$(bash "$CONTRACT" validate docs --pr 731 --round 1 -- "$MULTILINE_DOCS")" 0 "multiline plain-prose docs summary"

# Every phase fails closed for missing, empty, malformed, duplicate, partial, or extra results.
GOOD_REVIEW=$(review_output correctness 0)
GOOD_ADDRESS=$(address_output code 1)
assert_rejected "missing implementation output" bash "$CONTRACT" transition implement
assert_rejected "empty implementation output" bash "$CONTRACT" transition implement ""
assert_rejected "zero PR number" bash "$CONTRACT" transition implement 'PR_NUMBER: 0'
assert_rejected "malformed PR number" bash "$CONTRACT" transition implement 'PR_NUMBER: abc'
assert_rejected "duplicate PR number" bash "$CONTRACT" transition implement $'PR_NUMBER: 1\nPR_NUMBER: 2'
assert_rejected "missing accepted reviewer count" bash "$CONTRACT" transition review --pr 731 --round 1 --reviewers correctness -- "$GOOD_REVIEW"
assert_rejected "invalid accepted reviewer count" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count nope --reviewers correctness -- "$GOOD_REVIEW"
assert_rejected "accepted count above raw reviewer findings" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 1 --reviewers correctness -- "$GOOD_REVIEW"
assert_rejected "empty reviewer selection" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers -- "$GOOD_REVIEW"
assert_rejected "missing reviewer output" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness --
assert_rejected "empty reviewer output" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness -- ""
assert_rejected "partial selected reviewer output" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness testing -- "$GOOD_REVIEW"
assert_rejected "extra reviewer output" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness -- "$GOOD_REVIEW" "$GOOD_REVIEW"
assert_rejected "duplicate reviewer" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness correctness -- "$GOOD_REVIEW" "$GOOD_REVIEW"
assert_rejected "unknown reviewer" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers docs -- "$(review_output docs 0 "" "" 731 1 docs)"
assert_rejected "mismatched reviewer tag" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 1 --reviewers correctness -- "$(review_output testing 1)"
assert_rejected "malformed reviewer output" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness -- '### Summary'
REVIEW_ID=$'## Review Result\n**PR:** #731\n**Round:** 1\n**Type:** code\n**Reviewer:** correctness\n\n'
assert_rejected "out-of-order reviewer categories" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness -- "$REVIEW_ID"$'### Minor\n- **[Correctness]** Minor.\n### Recommended\n- **[Correctness]** Recommended.\n### Summary\nDone.'
assert_rejected "duplicate reviewer category" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness -- "$REVIEW_ID"$'### Recommended\n- **[Correctness]** First.\n### Recommended\n- **[Correctness]** Second.\n### Summary\nDone.'
assert_rejected "empty reviewer category" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness -- "$REVIEW_ID"$'### Action Required\n\n### Summary\nDone.'
assert_rejected "finding after reviewer summary" bash "$CONTRACT" transition review --pr 731 --round 1 --accepted-count 0 --reviewers correctness -- "$GOOD_REVIEW"$'\n### Action Required\n- **[Correctness]** Late.'
DOCS_CLEAN=$(review_output docs 0 "" "" 731 1 docs)
for structure in '#### Heading' '- bullet' '* bullet' '+ bullet' '1. numbered' '2) numbered' '> quote' '```text' '~~~text' '---' '| table |' '<!-- comment -->' '<div>HTML</div>' $'    indented code'; do
  assert_rejected "review summary Markdown structure: $structure" bash "$CONTRACT" validate review --pr 731 --round 1 --reviewers correctness -- "${GOOD_REVIEW/Correctness review complete./$structure}"
  assert_rejected "docs summary Markdown structure: $structure" bash "$CONTRACT" validate docs --pr 731 --round 1 -- "${DOCS_CLEAN/Docs review complete./$structure}"
done
for phase in address docs-address verification-address; do
  case "$phase" in
    address) phase_round=1 ;;
    docs-address) phase_round=docs-1 ;;
    verification-address) phase_round=verification-1 ;;
  esac
  case "$phase" in address) phase_name=code ;; docs-address) phase_name=docs ;; verification-address) phase_name=verification ;; esac
  PHASE_ADDRESS=$(address_output "$phase_name" "$phase_round")
  assert_rejected "missing $phase output" bash "$CONTRACT" transition "$phase"
  assert_rejected "missing $phase finding IDs" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" -- "$PHASE_ADDRESS"
  assert_rejected "empty $phase output" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 1 -- ""
  assert_rejected "malformed $phase output" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 1 -- '| # | Finding | Action | Details |'
  assert_rejected "unsuccessful $phase result" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 1 -- "${PHASE_ADDRESS/Applied/Escalated}"
  assert_rejected "missing expected $phase row" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 1 2 -- "$PHASE_ADDRESS"
  assert_rejected "extra $phase row" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 2 -- "$PHASE_ADDRESS"
  assert_rejected "duplicate expected $phase ID" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 1 1 -- "$PHASE_ADDRESS"
  assert_rejected "duplicate result $phase ID" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 1 2 -- "$(address_output "$phase_name" "$phase_round" 1 1)"
  assert_rejected "failed $phase tests" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 1 -- "${PHASE_ADDRESS/- **Status:** PASS/- **Status:** FAIL}"
  assert_rejected "duplicate $phase tests" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 1 -- "$PHASE_ADDRESS"$'\n### Tests\n- **Command:** `other`\n- **Result:** pass\n- **Status:** PASS'
  assert_rejected "missing $phase commit" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 1 -- "$(printf '%s\n' "$PHASE_ADDRESS" | sed '/^- `abcdef1`/d')"
  assert_rejected "none $phase commit" bash "$CONTRACT" transition "$phase" --pr 731 --round "$phase_round" --finding-ids 1 -- "${PHASE_ADDRESS/- \`abcdef1\` — \`fix: address lifecycle contract\`/- none}"
  assert_rejected "mismatched $phase PR" bash "$CONTRACT" transition "$phase" --pr 732 --round "$phase_round" --finding-ids 1 -- "$PHASE_ADDRESS"
  assert_rejected "mismatched $phase round" bash "$CONTRACT" transition "$phase" --pr 731 --round "${phase_round}9" --finding-ids 1 -- "$PHASE_ADDRESS"
done
assert_rejected "missing docs accepted count" bash "$CONTRACT" transition docs --pr 731 --round 1 -- "$DOCS_CLEAN"
assert_rejected "empty docs output" bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 0 -- ""
assert_rejected "malformed docs output" bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 0 -- "$(review_output correctness 1)"
assert_rejected "accepted docs count above raw findings" bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 1 -- "$DOCS_CLEAN"
DOCS_ID=$'## Review Result\n**PR:** #731\n**Round:** 1\n**Type:** docs\n**Reviewer:** docs\n\n'
assert_rejected "out-of-order docs categories" bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 0 -- "$DOCS_ID"$'### Minor\n- **[Docs]** Minor.\n### Recommended\n- **[Docs]** Recommended.\n### Summary\nDone.'
assert_rejected "duplicate docs category" bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 0 -- "$DOCS_ID"$'### Recommended\n- **[Docs]** First.\n### Recommended\n- **[Docs]** Second.\n### Summary\nDone.'
assert_rejected "empty docs category" bash "$CONTRACT" transition docs --pr 731 --round 1 --accepted-count 0 -- "$DOCS_ID"$'### Action Required\n\n### Summary\nDone.'
assert_rejected "missing verification output" bash "$CONTRACT" transition verify
assert_rejected "empty verification output" bash "$CONTRACT" transition verify --pr 731 -- ""
assert_rejected "invalid expected verification PR" bash "$CONTRACT" transition verify --pr 0 -- "$(verification_output PASS)"
assert_rejected "mismatched verification PR" bash "$CONTRACT" transition verify --pr 732 -- "$(verification_output PASS)"
assert_rejected "duplicate verification heading" bash "$CONTRACT" transition verify --pr 731 -- "$(verification_output PASS)"$'\n## End-to-End Verification — PR #731'
assert_rejected "unknown verification verdict" bash "$CONTRACT" transition verify --pr 731 -- $'## End-to-End Verification — PR #731\n### Verdict: UNKNOWN'
assert_rejected "duplicate verification verdict" bash "$CONTRACT" transition verify --pr 731 -- $'## End-to-End Verification — PR #731\n### Verdict: PASS\n### Verdict: FAIL'
assert_rejected "FAIL verification without structured issues" bash "$CONTRACT" transition verify --pr 731 -- $'## End-to-End Verification — PR #731\n### Verdict: FAIL\n### Issues Found\nNone'
assert_rejected "bare PASS verification" bash "$CONTRACT" transition verify --pr 731 -- $'## End-to-End Verification — PR #731\n### Verdict: PASS'
assert_rejected "PASS verification without evidence" bash "$CONTRACT" transition verify --pr 731 -- "$(verification_output PASS | sed '/### Evidence/,/### Issues Found/{ /### Evidence/!{ /### Issues Found/!d; }; }')"
assert_rejected "PASS verification with heading-only evidence" bash "$CONTRACT" transition verify --pr 731 -- "$(verification_output PASS | sed '/\*\*Result:\*\*/d')"
assert_rejected "PASS verification with failure evidence" bash "$CONTRACT" transition verify --pr 731 -- "$(verification_output PASS)"$'\nResult: FAIL'
assert_rejected "PASS verification with failed scenario result" bash "$CONTRACT" transition verify --pr 731 -- "$(verification_output PASS | sed 's/\*\*Result:\*\* PASS/\*\*Result:\*\* FAIL/')"
assert_rejected "PASS verification with structured issue" bash "$CONTRACT" transition verify --pr 731 -- "$(verification_output PASS)"$'\n- **[Verification]** Contradictory failure.'
assert_rejected "duplicate PASS issues section" bash "$CONTRACT" transition verify --pr 731 -- "$(verification_output PASS)"$'\n### Issues Found\nNone'
assert_rejected "non-pure-doc N/A" bash "$CONTRACT" transition verify --pr 731 -- $'## End-to-End Verification — PR #731\n\n### Verdict: N/A\n\nNo testing needed.'
assert_rejected "missing merge output" bash "$CONTRACT" transition merge
assert_rejected "empty merge output" bash "$CONTRACT" transition merge --pr 731 --base main --title "feat: synthetic acceptance" -- ""
assert_rejected "malformed merge output" bash "$CONTRACT" transition merge --pr 731 --base main --title "feat: synthetic acceptance" -- $'## Merge Complete\n**PR:** #0 — bad\n**Base:** main'
assert_rejected "mismatched merge PR" bash "$CONTRACT" transition merge --pr 732 --base main --title "feat: synthetic acceptance" -- "$(merge_output)"
assert_rejected "mismatched merge base" bash "$CONTRACT" transition merge --pr 731 --base release --title "feat: synthetic acceptance" -- "$(merge_output)"
assert_rejected "mismatched merge title" bash "$CONTRACT" transition merge --pr 731 --base main --title "wrong title" -- "$(merge_output)"
assert_rejected "duplicate merge PR" bash "$CONTRACT" transition merge --pr 731 --base main --title "feat: synthetic acceptance" -- "$(merge_output)"$'\n**PR:** #731 — feat: synthetic acceptance'
assert_rejected "out-of-order merge fields" bash "$CONTRACT" transition merge --pr 731 --base main --title "feat: synthetic acceptance" -- "$(merge_output | sed '/\*\*Base:\*\*/d')"$'\n**Base:** main'
assert_rejected "merge without changes" bash "$CONTRACT" transition merge --pr 731 --base main --title "feat: synthetic acceptance" -- "$(merge_output | sed '/^- Added synthetic/d')"
assert_rejected "merge with extra structural field" bash "$CONTRACT" transition merge --pr 731 --base main --title "feat: synthetic acceptance" -- "$(merge_output)"$'\n**Unexpected:** value'

# Review and docs envelopes are bound to the exact active PR, round, type, and reviewer.
assert_rejected "stale review PR" bash "$CONTRACT" validate review --pr 732 --round 1 --reviewers correctness -- "$(review_output correctness 0)"
assert_rejected "stale review round" bash "$CONTRACT" validate review --pr 731 --round 2 --reviewers correctness -- "$(review_output correctness 0)"
assert_rejected "wrong review type" bash "$CONTRACT" validate review --pr 731 --round 1 --reviewers correctness -- "$(review_output correctness 0 "" "" 731 1 docs)"
assert_rejected "missing review identity" bash "$CONTRACT" validate review --pr 731 --round 1 --reviewers correctness -- "$(review_output correctness 0 | sed '/\*\*Round:\*\*/d')"
assert_rejected "duplicate review identity" bash "$CONTRACT" validate review --pr 731 --round 1 --reviewers correctness -- "$(review_output correctness 0)"$'\n**Round:** 1'
assert_rejected "stale docs PR" bash "$CONTRACT" validate docs --pr 732 --round 1 -- "$(review_output docs 0 "" "" 731 1 docs)"
assert_rejected "stale docs round" bash "$CONTRACT" validate docs --pr 731 --round 2 -- "$(review_output docs 0 "" "" 731 1 docs)"
assert_rejected "wrong docs type" bash "$CONTRACT" validate docs --pr 731 --round 1 -- "$(review_output docs 0 "" "" 731 1 code)"

# Addresser evidence is ordered, unique, phase-bound, and contained in its declared sections.
assert_rejected "out-of-order addresser sections" bash "$CONTRACT" transition address --pr 731 --round 1 --finding-ids 1 -- "$(address_output code 1 | sed '/### Tests/,/- \*\*Status:\*\* PASS/d')"$'\n### Tests\n- **Command:** `./validate-all.sh`\n- **Result:** all validators passed\n- **Status:** PASS'
assert_rejected "empty addresser test result" bash "$CONTRACT" transition address --pr 731 --round 1 --finding-ids 1 -- "$(address_output code 1 | sed 's/- \*\*Result:\*\* all validators passed/- **Result:** none/')"
assert_rejected "commit outside addresser section" bash "$CONTRACT" transition address --pr 731 --round 1 --finding-ids 1 -- "$(address_output code 1 | sed '/### Commits/,$d')"$'\n- `abcdef1` — `fix: misplaced`\n### Commits\n- `bcdef12` — `fix: valid`'
assert_rejected "extra addresser finding" bash "$CONTRACT" transition address --pr 731 --round 1 --finding-ids 1 -- "$(address_output code 1 1 2)"
assert_rejected "wrong addresser phase" bash "$CONTRACT" transition address --pr 731 --round 1 --finding-ids 1 -- "$(address_output docs 1)"
assert_rejected "malformed docs round identifier" bash "$CONTRACT" transition docs-address --pr 731 --round docs-1x --finding-ids 1 -- "$(address_output docs docs-1x)"
assert_rejected "malformed verification round identifier" bash "$CONTRACT" transition verification-address --pr 731 --round verification-1x --finding-ids 1 -- "$(address_output verification verification-1x)"

# All executable verification verdicts require the same complete ordered envelope.
for verdict in PASS FAIL PARTIAL; do
  complete=$(verification_output "$verdict")
  assert_rejected "$verdict missing system flow" bash "$CONTRACT" transition verify --pr 731 -- "$(printf '%s\n' "$complete" | sed '/### System Flow Verified/,/### Evidence/{ /### Evidence/!d; }')"
  assert_rejected "$verdict missing evidence" bash "$CONTRACT" transition verify --pr 731 -- "$(printf '%s\n' "$complete" | sed '/### Evidence/,/### Issues Found/{ /### Issues Found/!d; }')"
  assert_rejected "$verdict missing assessment" bash "$CONTRACT" transition verify --pr 731 -- "$(printf '%s\n' "$complete" | sed '/### Holistic Assessment/,$d')"
  assert_rejected "$verdict unknown scenario" bash "$CONTRACT" transition verify --pr 731 -- "${complete/Result:** ${verdict}/Result:** UNKNOWN}"
done
assert_rejected "FAIL with passing-only evidence" bash "$CONTRACT" transition verify --pr 731 -- "$(verification_output FAIL | sed 's/Result:\*\* FAIL/Result:** PASS/')"
assert_rejected "PARTIAL with passing-only evidence" bash "$CONTRACT" transition verify --pr 731 -- "$(verification_output PARTIAL | sed 's/Result:\*\* PARTIAL/Result:** PASS/')"

echo "PASS: strict worker outputs, referee-driven transitions, verification recovery, client entry points, and deterministic parallel reviewer dispatch are covered."
