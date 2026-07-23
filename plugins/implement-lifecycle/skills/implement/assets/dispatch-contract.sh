#!/bin/bash
# Shared dispatch and transition contract for the implement lifecycle.
set -euo pipefail

PLUGIN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

usage() {
  echo "usage: $0 target <claude|codex> <worker> | targets <claude|codex> <worker>... | validate <review|docs> --pr <number> --round <number> [--reviewers <reviewer>...] -- <worker-output>... | transition <phase> [--accepted-count <count>] [--finding-ids <id>...] [--pr <number>] [--round <identifier>] [--base <branch>] [--title <title>] [--reviewers <reviewer>...] -- <worker-output>..." >&2
  exit 2
}

is_reviewer() {
  case "$1" in
    review-correctness|review-security|review-architecture|review-testing|review-docs) return 0 ;;
    *) return 1 ;;
  esac
}

is_worker() {
  case "$1" in
    implement-code|review-correctness|review-security|review-architecture|review-testing|implement-address|review-docs|verify|merge-pr) return 0 ;;
    *) return 1 ;;
  esac
}

entry_path() {
  client=$1
  worker=$2
  is_worker "$worker" || return 1
  if [ "$client" = claude ] && is_reviewer "$worker"; then
    printf '%s/agents/%s.md\n' "$PLUGIN_DIR" "$worker"
  else
    printf '%s/skills/%s/SKILL.md\n' "$PLUGIN_DIR" "$worker"
  fi
}

target() {
  client=$1
  worker=$2
  case "$client" in claude|codex) ;; *) echo "unknown client: $client" >&2; return 2 ;; esac
  path=$(entry_path "$client" "$worker") || {
    echo "unknown lifecycle worker: $worker" >&2
    return 2
  }
  if [ ! -f "$path" ]; then
    echo "missing $client lifecycle entry point: ${path#"$PLUGIN_DIR"/}" >&2
    return 2
  fi
  case "$client" in
    claude) printf '%s\n' "$worker" ;;
    codex) printf '$implement-lifecycle:%s\n' "$worker" ;;
  esac
}

require_nonempty_output() {
  label=$1
  value=${2-}
  if [ -z "${value//[[:space:]]/}" ]; then
    echo "missing or empty $label output" >&2
    return 2
  fi
}

require_round_identifier() {
  phase=$1
  value=$2
  case "$phase" in
    code) suffix=$value ;;
    docs) case "$value" in docs-*) suffix=${value#docs-} ;; *) return 2 ;; esac ;;
    verification) case "$value" in verification-*) suffix=${value#verification-} ;; *) return 2 ;; esac ;;
    *) return 2 ;;
  esac
  case "$suffix" in ''|*[!0-9]*|0) return 2 ;; esac
}

parse_pr_number() {
  output=${1-}
  require_nonempty_output implementation "$output"
  matches=$(printf '%s\n' "$output" | sed -n 's/^PR_NUMBER: *\([^ ]*\) *$/\1/p')
  [ "$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ] || {
    echo "implementation output must contain exactly one PR_NUMBER: <positive-integer>" >&2
    return 2
  }
  case "$matches" in ''|*[!0-9]*|0) echo "invalid PR number: $matches" >&2; return 2 ;; esac
  printf '%s\n' "$matches"
}

reviewer_label() {
  case "$1" in
    correctness) echo Correctness ;;
    security) echo 'Security|Requirements' ;;
    architecture) echo Architecture ;;
    testing) echo Testing ;;
    docs) echo Docs ;;
    *) echo "unknown reviewer: $1" >&2; return 2 ;;
  esac
}

parse_review_count() {
  reviewer=$1
  expected_pr=$2
  expected_round=$3
  expected_type=$4
  output=${5-}
  require_nonempty_output "$reviewer reviewer" "$output" || return 2
  label=$(reviewer_label "$reviewer") || return 2
  printf '%s\n' "$output" | awk -v reviewer="$reviewer" -v labels="$label" -v pr="$expected_pr" -v round="$expected_round" -v type="$expected_type" '
    function fail(message) {
      failed = 1
      print "malformed " reviewer " reviewer output: " message > "/dev/stderr"
      exit 2
    }
    function close_category() {
      if (in_category && category_findings == 0) fail("empty category")
    }
    BEGIN { last_rank = 0; findings = 0; metadata = 0 }
    /^[[:space:]]*$/ { next }
    metadata < 5 {
      metadata++
      if (metadata == 1 && $0 != "## Review Result") fail("missing or misplaced identity heading")
      if (metadata == 2 && $0 != "**PR:** #" pr) fail("PR identity mismatch")
      if (metadata == 3 && $0 != "**Round:** " round) fail("round identity mismatch")
      if (metadata == 4 && $0 != "**Type:** " type) fail("review type mismatch")
      if (metadata == 5 && $0 != "**Reviewer:** " reviewer) fail("reviewer identity mismatch")
      next
    }
    /^### / {
      if ($0 == "### Action Required") rank = 1
      else if ($0 == "### Recommended") rank = 2
      else if ($0 == "### Minor") rank = 3
      else if ($0 == "### Summary") rank = 4
      else fail("unsupported category")
      if (rank <= last_rank) fail("categories must be unique and ordered")
      close_category()
      last_rank = rank
      if (rank == 4) {
        summary_seen = 1
        in_category = 0
      } else {
        in_category = 1
        category_findings = 0
      }
      next
    }
    {
      if (last_rank == 0) fail("content before first category")
      if (summary_seen) {
        # Summary is prose, not another Markdown container. Requiring an
        # alphanumeric first character rejects headings, every list form,
        # quotes, fences, rules, tables, indented code, and HTML structure.
        if ($0 !~ /^[[:alnum:]]/ || $0 ~ /^[0-9]+[.)][[:space:]]/ || $0 ~ /<[^>]*>/) fail("summary must contain plain prose lines")
        summary_nonempty = 1
        next
      }
      if (!in_category) fail("content outside a finding category")
      expected = "^- \\*\\*\\[(" labels ")\\]\\*\\* .+"
      if ($0 !~ expected) fail("category contains a malformed or mismatched finding")
      category_findings++
      findings++
    }
    END {
      if (failed) exit 2
      close_category()
      if (metadata != 5) fail("incomplete identity envelope")
      if (!summary_seen) fail("missing final ### Summary")
      if (!summary_nonempty) fail("empty summary")
      print findings
    }
  '
}

validate_accepted_count() {
  accepted=${1-}
  raw=$2
  case "$accepted" in ''|*[!0-9]*) echo "accepted finding count must be a non-negative integer" >&2; return 2 ;; esac
  [ "$accepted" -le "$raw" ] || {
    echo "accepted finding count cannot exceed validated raw findings" >&2
    return 2
  }
}

parse_review_batch() {
  [ "${1-}" = --pr ] && [ "${3-}" = --round ] || { echo "review validation requires --pr <positive-integer> --round <positive-integer>" >&2; return 2; }
  expected_pr=$2
  expected_round=$4
  case "$expected_pr:$expected_round" in *[!0-9:]*|0:*|*:0|:) echo "review identity requires positive PR and round numbers" >&2; return 2 ;; esac
  shift 4
  [ "${1-}" = --reviewers ] || { echo "review validation requires --reviewers" >&2; return 2; }
  shift
  reviewers=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do reviewers+=("$1"); shift; done
  [ "${1-}" = -- ] || { echo "review validation requires -- before outputs" >&2; return 2; }
  shift
  [ "${#reviewers[@]}" -gt 0 ] || { echo "review validation requires one or more reviewers" >&2; return 2; }
  [ "$#" -eq "${#reviewers[@]}" ] || { echo "review validation requires exactly one output per selected reviewer" >&2; return 2; }
  outputs=("$@")
  total=0
  seen=' '
  index=0
  for reviewer in "${reviewers[@]}"; do
    case "$reviewer" in correctness|security|architecture|testing) ;; *) echo "invalid code reviewer: $reviewer" >&2; return 2 ;; esac
    case "$seen" in *" $reviewer "*) echo "duplicate selected reviewer: $reviewer" >&2; return 2 ;; esac
    seen="$seen$reviewer "
    count=$(parse_review_count "$reviewer" "$expected_pr" "$expected_round" "code" "${outputs[$index]}") || return 2
    total=$((total + count))
    index=$((index + 1))
  done
  printf '%s\n' "$total"
}

validate_outputs() {
  phase=$1
  shift
  case "$phase" in
    review) parse_review_batch "$@" ;;
    docs)
      [ "${1-}" = --pr ] && [ "${3-}" = --round ] && [ "${5-}" = -- ] && [ "$#" -eq 6 ] || { echo "docs validation requires --pr <positive-integer> --round <positive-integer> -- <output>" >&2; return 2; }
      case "$2:$4" in *[!0-9:]*|0:*|*:0|:) echo "docs identity requires positive PR and round numbers" >&2; return 2 ;; esac
      parse_review_count docs "$2" "$4" docs "$6"
      ;;
    *) echo "unknown validation phase: $phase" >&2; return 2 ;;
  esac
}

parse_finding_ids() {
  [ "${1-}" = --pr ] && [ "${3-}" = --round ] && [ "${5-}" = --finding-ids ] || { echo "address transition requires --pr <positive-integer> --round <identifier> --finding-ids" >&2; return 2; }
  ADDRESS_PR=$2
  ADDRESS_ROUND=$4
  case "$ADDRESS_PR" in ''|*[!0-9]*|0) echo "address transition requires a positive PR number" >&2; return 2 ;; esac
  shift 4
  [ "${1-}" = --finding-ids ] || return 2
  shift
  FINDING_IDS=()
  seen=' '
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    case "$1" in ''|*[!0-9]*|0) echo "finding IDs must be positive integers" >&2; return 2 ;; esac
    case "$seen" in *" $1 "*) echo "duplicate expected finding ID: $1" >&2; return 2 ;; esac
    FINDING_IDS+=("$1")
    seen="$seen$1 "
    shift
  done
  [ "${#FINDING_IDS[@]}" -gt 0 ] || { echo "address transition requires one or more finding IDs" >&2; return 2; }
  [ "${1-}" = -- ] || { echo "address transition requires -- before output" >&2; return 2; }
  shift
  [ "$#" -eq 1 ] || { echo "address transition requires exactly one output" >&2; return 2; }
  ADDRESS_OUTPUT=$1
}

parse_addressed() {
  output=${1-}
  expected_pr=$2
  expected_round=$3
  expected_phase=$4
  shift 4
  expected_ids=("$@")
  require_nonempty_output addresser "$output"
  expected_joined=$(IFS=,; echo "${expected_ids[*]}")
  printf '%s\n' "$output" | awk -v pr="$expected_pr" -v round="$expected_round" -v phase="$expected_phase" -v ids="$expected_joined" '
    function fail(message) { print "malformed addresser output: " message > "/dev/stderr"; exit 2 }
    BEGIN { split(ids, expected, ","); state=0; row=0 }
    /^[[:space:]]*$/ { next }
    state==0 { if ($0!="## Address Result") fail("missing identity heading"); state=1; next }
    state==1 { if ($0!="**PR:** #" pr) fail("PR identity mismatch"); state=2; next }
    state==2 { if ($0!="**Round:** " round) fail("round identity mismatch"); state=3; next }
    state==3 { if ($0!="**Phase:** " phase) fail("phase identity mismatch"); state=4; next }
    state==4 { if ($0!="### Findings") fail("missing or misplaced Findings section"); state=5; next }
    state==5 { if ($0!="| # | Finding | Action | Details |") fail("malformed findings header"); state=6; next }
    state==6 { if ($0!="|---|---------|--------|---------|") fail("malformed findings separator"); state=7; next }
    state==7 && /^\| [0-9]+ \|/ {
      split($0, f, "|"); id=f[2]; gsub(/^ +| +$/, "", id); action=f[4]; gsub(/^ +| +$/, "", action)
      row++; if (id != expected[row]) fail("finding IDs must match exactly and in order")
      if (action != "Applied" && action != "Partially applied") fail("every finding must be successfully addressed")
      if (f[3] !~ /[^[:space:]]/ || f[5] !~ /[^[:space:]]/) fail("finding rows require description and details")
      next
    }
    state==7 { if (row != length(expected) || $0!="### Tests") fail("missing finding or Tests section"); state=8; next }
    state==8 { if ($0 !~ /^- \*\*Command:\*\* `[^`]+`$/ || tolower($0) ~ /`none`/) fail("Tests requires one credible command"); state=9; next }
    state==9 { if ($0 !~ /^- \*\*Result:\*\* .+/ || tolower($0) ~ /none/) fail("Tests requires one non-empty result"); state=10; next }
    state==10 { if ($0!="- **Status:** PASS") fail("Tests requires explicit PASS status"); state=11; next }
    state==11 { if ($0!="### Commits") fail("missing or misplaced Commits section"); state=12; next }
    state==12 {
      if ($0 !~ /^- `?[0-9a-f]{7,40}`? — `?[^`[:space:]][^`]*`?$/ || tolower($0) ~ /none/) fail("Commits accepts only real commit rows")
      commits++; next
    }
    END { if (state != 12 || row != length(expected) || commits < 1) fail("incomplete result envelope") }
  ' || return 2
}

parse_verdict() {
  expected_pr=$1
  output=${2-}
  require_nonempty_output verification "$output"
  heading_pr=$(printf '%s\n' "$output" | sed -n 's/^## End-to-End Verification — PR #\([0-9][0-9]*\) *$/\1/p')
  [ "$(printf '%s\n' "$heading_pr" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ] && [ "$heading_pr" = "$expected_pr" ] || {
    echo "verification output must contain exactly one heading for expected PR #$expected_pr" >&2; return 2;
  }
  verdict=$(printf '%s\n' "$output" | sed -n 's/^### Verdict: *//p' | sed 's/ *$//')
  [ "$(printf '%s\n' "$verdict" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ] || {
    echo "verification output must contain exactly one ### Verdict" >&2; return 2;
  }
  case "$verdict" in
    PASS|FAIL|PARTIAL)
      printf '%s\n' "$output" | awk -v verdict="$verdict" '
        function fail() { exit 2 }
        BEGIN { section=0; last=0; envelope=0 }
        /^[[:space:]]*$/ { next }
        !envelope { if ($0 !~ /^## End-to-End Verification — PR #[1-9][0-9]*$/) fail(); envelope=1; next }
        /^## / { fail() }
        /^### / {
          if ($0 == "### Verdict: " verdict) rank = 1
          else if ($0 == "### System Flow Verified") rank = 2
          else if ($0 == "### Evidence") rank = 3
          else if ($0 == "### Issues Found") rank = 4
          else if ($0 == "### Holistic Assessment") rank = 5
          else fail()
          if (rank <= last || seen[rank]++) fail()
          last = rank; section = rank; next
        }
        section == 2 && $0 !~ /^#/ { flow = 1 }
        section == 3 && $0 !~ /^#/ { evidence = 1 }
        section == 3 && $0 ~ /^(\*\*)?Result:(\*\*)? PASS([[:space:]]|$)/ { evidence_pass++ }
        section == 3 && $0 ~ /^(\*\*)?Result:(\*\*)? FAIL([[:space:]]|$)/ { evidence_fail++ }
        section == 3 && $0 ~ /^(\*\*)?Result:(\*\*)? PARTIAL([[:space:]]|$)/ { evidence_partial++ }
        $0 ~ /^(\*\*)?Result:(\*\*)? PASS([[:space:]]|$)/ { pass_result++ }
        $0 ~ /^(\*\*)?Result:(\*\*)? FAIL([[:space:]]|$)/ { fail_result++ }
        $0 ~ /^(\*\*)?Result:(\*\*)? PARTIAL([[:space:]]|$)/ { partial_result++ }
        $0 ~ /^(\*\*)?Result:(\*\*)? UNKNOWN([[:space:]]|$)/ || $0 ~ /### Verdict: UNKNOWN/ { unknown = 1 }
        $0 ~ /^- \*\*\[Verification\]\*\* .+/ { global_issues++ }
        section == 4 {
          if ($0 == "None") none++
          else if ($0 ~ /^- \*\*\[Verification\]\*\* .+/) issues++
          else malformed_issue = 1
        }
        section == 5 && $0 !~ /^#/ { assessment = 1 }
        END {
          if (!envelope || last != 5 || !flow || !evidence || !assessment || unknown || malformed_issue) fail()
          if (verdict == "PASS" && (evidence_pass < 1 || fail_result || partial_result || none != 1 || global_issues)) fail()
          if (verdict == "FAIL" && (evidence_fail < 1 || partial_result || none || issues < 1)) fail()
          if (verdict == "PARTIAL" && ((evidence_fail + evidence_partial) < 1 || none || issues < 1)) fail()
        }
      ' || { echo "verification $verdict output requires the complete ordered envelope and verdict-consistent scenario evidence" >&2; return 2; }
      printf '%s\n' "$verdict"
      ;;
    N/A)
      expected=$(printf '## End-to-End Verification — PR #%s\n\n### Verdict: N/A\n\nPure documentation change — no code, configuration, or build artifacts affected.' "$expected_pr")
      [ "$output" = "$expected" ] || { echo "verification N/A output must use the documented pure-documentation envelope exactly" >&2; return 2; }
      printf '%s\n' "$verdict"
      ;;
    *) echo "unsupported verification verdict: $verdict" >&2; return 2 ;;
  esac
}

parse_merged() {
  expected_pr=$1
  expected_base=$2
  expected_title=$3
  output=${4-}
  require_nonempty_output merge "$output"
  printf '%s\n' "$output" | awk -v pr="$expected_pr" -v base="$expected_base" -v title="$expected_title" '
    function fail(message) { print "malformed merge output: " message > "/dev/stderr"; exit 2 }
    /^[[:space:]]*$/ { next }
    state==0 { if ($0!="## Merge Complete") fail("missing success heading"); state=1; next }
    state==1 { if ($0!="**PR:** #" pr " — " title) fail("PR number or title mismatch"); state=2; next }
    state==2 { if ($0!="**Base:** " base) fail("base branch mismatch"); state=3; next }
    state==3 { if ($0!~/^\*\*Issues updated:\*\* .+/) fail("missing Issues updated value"); state=4; next }
    state==4 { if ($0!="### Changes") fail("missing or misplaced Changes section"); state=5; next }
    state==5 { if ($0!~/^- .+/) fail("Changes accepts only non-empty bullets"); changes++; next }
    END { if (state!=5 || changes<1) fail("incomplete merge report") }
  ' || return 2
}

transition() {
  phase=$1
  shift
  case "$phase" in
    implement)
      [ "$#" -eq 1 ] || { echo "implement transition requires exactly one output" >&2; return 2; }
      parse_pr_number "$1" >/dev/null
      echo review
      ;;
    review)
      [ "${1-}" = --pr ] && [ "${3-}" = --round ] && [ "${5-}" = --accepted-count ] && [ "$#" -ge 6 ] || { echo "review transition requires --pr <number> --round <number> --accepted-count" >&2; return 2; }
      accepted=$6
      identity_args=(--pr "$2" --round "$4")
      shift 6
      total=$(parse_review_batch "${identity_args[@]}" "$@") || return 2
      validate_accepted_count "$accepted" "$total"
      if [ "$accepted" -eq 0 ]; then echo docs; else echo address; fi
      ;;
    address)
      parse_finding_ids "$@" || return 2
      require_round_identifier code "$ADDRESS_ROUND" || { echo "code address round must be a positive integer" >&2; return 2; }
      parse_addressed "$ADDRESS_OUTPUT" "$ADDRESS_PR" "$ADDRESS_ROUND" code "${FINDING_IDS[@]}"
      echo review
      ;;
    docs)
      [ "${1-}" = --pr ] && [ "${3-}" = --round ] && [ "${5-}" = --accepted-count ] && [ "$#" -eq 8 ] && [ "${7-}" = -- ] || {
        echo "docs transition requires --pr <number> --round <number> --accepted-count <count> -- <output>" >&2; return 2;
      }
      accepted=$6
      case "$2:$4" in *[!0-9:]*|0:*|*:0|:) echo "docs identity requires positive PR and round numbers" >&2; return 2 ;; esac
      count=$(parse_review_count docs "$2" "$4" docs "$8") || return 2
      validate_accepted_count "$accepted" "$count"
      if [ "$accepted" -eq 0 ]; then echo verify; else echo docs-address; fi
      ;;
    docs-address)
      parse_finding_ids "$@" || return 2
      require_round_identifier docs "$ADDRESS_ROUND" || { echo "docs address round must be docs-<positive-integer>" >&2; return 2; }
      parse_addressed "$ADDRESS_OUTPUT" "$ADDRESS_PR" "$ADDRESS_ROUND" docs "${FINDING_IDS[@]}"
      echo docs
      ;;
    verify)
      [ "${1-}" = --pr ] && [ "$#" -eq 4 ] && [ "${3-}" = -- ] || { echo "verify transition requires --pr <positive-integer> -- <output>" >&2; return 2; }
      case "$2" in ''|*[!0-9]*|0) echo "verify transition requires a positive PR number" >&2; return 2 ;; esac
      verdict=$(parse_verdict "$2" "$4")
      case "$verdict" in PASS|N/A) echo merge ;; FAIL|PARTIAL) echo verification-address ;; esac
      ;;
    verification-address)
      parse_finding_ids "$@" || return 2
      require_round_identifier verification "$ADDRESS_ROUND" || { echo "verification address round must be verification-<positive-integer>" >&2; return 2; }
      parse_addressed "$ADDRESS_OUTPUT" "$ADDRESS_PR" "$ADDRESS_ROUND" verification "${FINDING_IDS[@]}"
      echo verify
      ;;
    merge)
      [ "${1-}" = --pr ] && [ "${3-}" = --base ] && [ "${5-}" = --title ] && [ "$#" -eq 8 ] && [ "${7-}" = -- ] || { echo "merge transition requires --pr <positive-integer> --base <branch> --title <title> -- <output>" >&2; return 2; }
      case "$2" in ''|*[!0-9]*|0) echo "merge transition requires a positive PR number" >&2; return 2 ;; esac
      [ -n "${4//[[:space:]]/}" ] && [ -n "${6//[[:space:]]/}" ] || { echo "merge transition requires non-empty base and title" >&2; return 2; }
      parse_merged "$2" "$4" "$6" "$8"
      echo complete
      ;;
    *) echo "unknown lifecycle phase: $phase" >&2; return 2 ;;
  esac
}

case "${1:-}" in
  target)
    [ "$#" -eq 3 ] || usage
    target "$2" "$3"
    ;;
  targets)
    [ "$#" -ge 3 ] || usage
    client=$2
    shift 2
    for worker in "$@"; do target "$client" "$worker"; done
    ;;
  validate)
    [ "$#" -ge 4 ] || usage
    phase=$2
    shift 2
    validate_outputs "$phase" "$@"
    ;;
  transition)
    [ "$#" -ge 3 ] || usage
    phase=$2
    shift 2
    transition "$phase" "$@"
    ;;
  *) usage ;;
esac
