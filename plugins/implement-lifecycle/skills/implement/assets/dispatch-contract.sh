#!/bin/bash
# Shared dispatch and transition contract for the implement lifecycle.
set -euo pipefail

PLUGIN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

usage() {
  echo "usage: $0 target <claude|codex> <worker> | targets <claude|codex> <worker>... | validate <review|docs> [--reviewers <reviewer>...] -- <worker-output>... | transition <phase> [--accepted-count <count>] [--finding-ids <id>...] [--pr <number>] [--reviewers <reviewer>...] -- <worker-output>..." >&2
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
  output=${2-}
  require_nonempty_output "$reviewer reviewer" "$output" || return 2
  label=$(reviewer_label "$reviewer") || return 2
  printf '%s\n' "$output" | awk -v reviewer="$reviewer" -v labels="$label" '
    function fail(message) {
      failed = 1
      print "malformed " reviewer " reviewer output: " message > "/dev/stderr"
      exit 2
    }
    function close_category() {
      if (in_category && category_findings == 0) fail("empty category")
    }
    BEGIN { last_rank = 0; findings = 0 }
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
    /^[[:space:]]*$/ { next }
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
    count=$(parse_review_count "$reviewer" "${outputs[$index]}") || return 2
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
      [ "${1-}" = -- ] && [ "$#" -eq 2 ] || { echo "docs validation requires -- <output>" >&2; return 2; }
      parse_review_count docs "$2"
      ;;
    *) echo "unknown validation phase: $phase" >&2; return 2 ;;
  esac
}

parse_finding_ids() {
  [ "${1-}" = --finding-ids ] || { echo "address transition requires --finding-ids" >&2; return 2; }
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
  shift
  expected_ids=("$@")
  require_nonempty_output addresser "$output"
  printf '%s\n' "$output" | grep -Fq '| # | Finding | Action | Details |' || {
    echo "malformed addresser output: missing summary table" >&2; return 2;
  }
  rows=$(printf '%s\n' "$output" | grep -E '^\| [0-9]+ \|' || true)
  row_count=$(printf '%s\n' "$rows" | sed '/^$/d' | wc -l | tr -d ' ')
  successful_rows=$(printf '%s\n' "$rows" | grep -Ec '^\| [0-9]+ \| .+ \| (Applied|Partially applied) \| .+ \|$' || true)
  [ "$row_count" -eq "${#expected_ids[@]}" ] && [ "$successful_rows" -eq "$row_count" ] || {
    echo "malformed or unsuccessful addresser output: every finding must be Applied or Partially applied" >&2; return 2;
  }
  actual_ids=$(printf '%s\n' "$rows" | sed -E 's/^\| ([0-9]+) \|.*$/\1/' | sort -n)
  expected_sorted=$(printf '%s\n' "${expected_ids[@]}" | sort -n)
  [ "$actual_ids" = "$expected_sorted" ] || {
    echo "malformed addresser output: result rows must match the expected finding IDs exactly" >&2; return 2;
  }
  [ "$(printf '%s\n' "$output" | grep -Ec '^\*\*Tests:\*\*' || true)" -eq 1 ] &&
    [ "$(printf '%s\n' "$output" | grep -Ec '^\*\*Tests:\*\* .+ — PASS$' || true)" -eq 1 ] || {
    echo "malformed addresser output: require exactly one explicit passing Tests result" >&2; return 2;
  }
  [ "$(printf '%s\n' "$output" | grep -Ec '^\*\*Commits:\*\*[[:space:]]*$' || true)" -eq 1 ] &&
    ! printf '%s\n' "$output" | grep -Eiq '^\*\*Commits:\*\*.*none|^- +none([[:space:]]|$)' || {
    echo "malformed addresser output: require one non-empty Commits section" >&2; return 2;
  }
  printf '%s\n' "$output" | grep -Eq '^- `?[0-9a-f]{7,40}`? — `?[^`[:space:]][^`]*`?$' || {
    echo "malformed addresser output: require at least one real commit identifier and message" >&2; return 2;
  }
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
    FAIL|PARTIAL)
      issue_count=$(printf '%s\n' "$output" | awk '
        /^### Issues Found[[:space:]]*$/ { headings++; in_issues = 1; next }
        /^### / { in_issues = 0 }
        in_issues && /^- \*\*\[Verification\]\*\* .+/ { findings++ }
        in_issues && /^- / && $0 !~ /^- \*\*\[Verification\]\*\* .+/ { malformed = 1 }
        END {
          if (headings != 1 || malformed || findings < 1) exit 2
          print findings
        }
      ') || {
        echo "verification $verdict output requires one or more structured issues under exactly one ### Issues Found heading" >&2
        return 2
      }
      printf '%s\n' "$verdict"
      ;;
    PASS)
      printf '%s\n' "$output" | awk '
        function fail() { exit 2 }
        /^### / {
          if ($0 == "### Verdict: PASS") rank = 1
          else if ($0 == "### System Flow Verified") rank = 2
          else if ($0 == "### Evidence") rank = 3
          else if ($0 == "### Issues Found") rank = 4
          else if ($0 == "### Holistic Assessment") rank = 5
          else fail()
          if (rank <= last || seen[rank]++) fail()
          last = rank; section = rank; next
        }
        /^[[:space:]]*$/ { next }
        section == 2 && $0 !~ /^#/ { flow = 1 }
        section == 3 && $0 !~ /^#/ { evidence = 1 }
        section == 3 && $0 ~ /^\*\*Result:\*\* PASS([[:space:]]|$)/ { passing_result = 1 }
        $0 ~ /^(\*\*)?Result:(\*\*)? (FAIL|PARTIAL)([[:space:]]|$)/ { contradiction = 1 }
        section == 4 { if ($0 == "None") none++; else contradiction = 1 }
        section == 5 && $0 !~ /^#/ { assessment = 1 }
        /- \*\*\[Verification\]\*\*/ { contradiction = 1 }
        END { if (last != 5 || !flow || !evidence || !passing_result || none != 1 || !assessment || contradiction) exit 2 }
      ' || { echo "verification PASS output requires complete, ordered, non-contradictory success evidence" >&2; return 2; }
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
  output=${2-}
  require_nonempty_output merge "$output"
  printf '%s\n' "$output" | grep -Eq '^## Merge Complete[[:space:]]*$' || {
    echo "malformed merge output: missing success heading" >&2; return 2;
  }
  merged_pr=$(printf '%s\n' "$output" | sed -n 's/^\*\*PR:\*\* #\([1-9][0-9]*\) .*/\1/p')
  [ "$(printf '%s\n' "$merged_pr" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ] && [ "$merged_pr" = "$expected_pr" ] || {
    echo "malformed merge output: require exactly one expected PR #$expected_pr" >&2; return 2;
  }
  printf '%s\n' "$output" | grep -Eq '^\*\*Merged to:\*\* .+' || {
    echo "malformed merge output: missing base branch" >&2; return 2;
  }
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
      [ "${1-}" = --accepted-count ] && [ "$#" -ge 2 ] || { echo "review transition requires --accepted-count" >&2; return 2; }
      accepted=$2
      shift 2
      total=$(parse_review_batch "$@") || return 2
      validate_accepted_count "$accepted" "$total"
      if [ "$accepted" -eq 0 ]; then echo docs; else echo address; fi
      ;;
    address)
      parse_finding_ids "$@" || return 2
      parse_addressed "$ADDRESS_OUTPUT" "${FINDING_IDS[@]}"
      echo review
      ;;
    docs)
      [ "${1-}" = --accepted-count ] && [ "$#" -eq 4 ] && [ "${3-}" = -- ] || {
        echo "docs transition requires --accepted-count <count> -- <output>" >&2; return 2;
      }
      accepted=$2
      count=$(parse_review_count docs "$4") || return 2
      validate_accepted_count "$accepted" "$count"
      if [ "$accepted" -eq 0 ]; then echo verify; else echo docs-address; fi
      ;;
    docs-address)
      parse_finding_ids "$@" || return 2
      parse_addressed "$ADDRESS_OUTPUT" "${FINDING_IDS[@]}"
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
      parse_addressed "$ADDRESS_OUTPUT" "${FINDING_IDS[@]}"
      echo verify
      ;;
    merge)
      [ "${1-}" = --pr ] && [ "$#" -eq 4 ] && [ "${3-}" = -- ] || { echo "merge transition requires --pr <positive-integer> -- <output>" >&2; return 2; }
      case "$2" in ''|*[!0-9]*|0) echo "merge transition requires a positive PR number" >&2; return 2 ;; esac
      parse_merged "$2" "$4"
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
