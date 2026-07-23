#!/bin/bash
# Shared dispatch and transition contract for the implement lifecycle.
set -euo pipefail

PLUGIN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

usage() {
  echo "usage: $0 target <claude|codex> <worker> | targets <claude|codex> <worker>... | validate <review|docs> [--reviewers <reviewer>...] -- <worker-output>... | transition <phase> [--accepted-count <count>] [--reviewers <reviewer>...] -- <worker-output>..." >&2
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
        if ($0 ~ /^- /) fail("finding bullet outside a finding category")
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

parse_addressed() {
  output=${1-}
  require_nonempty_output addresser "$output"
  printf '%s\n' "$output" | grep -Fq '| # | Finding | Action | Details |' || {
    echo "malformed addresser output: missing summary table" >&2; return 2;
  }
  rows=$(printf '%s\n' "$output" | grep -Ec '^\| [0-9]+ \|' || true)
  successful_rows=$(printf '%s\n' "$output" | grep -Ec '^\| [0-9]+ \| .+ \| (Applied|Partially applied) \| .+ \|$' || true)
  [ "$rows" -gt 0 ] && [ "$successful_rows" -eq "$rows" ] || {
    echo "malformed or unsuccessful addresser output: every finding must be Applied or Partially applied" >&2; return 2;
  }
  printf '%s\n' "$output" | grep -Eq '^\*\*Tests:\*\* .+' || {
    echo "malformed addresser output: missing test result" >&2; return 2;
  }
  printf '%s\n' "$output" | grep -Eq '^\*\*Commits:\*\* .+' || {
    echo "malformed addresser output: missing commit result" >&2; return 2;
  }
}

parse_verdict() {
  output=${1-}
  require_nonempty_output verification "$output"
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
    PASS|N/A) printf '%s\n' "$verdict" ;;
    *) echo "unsupported verification verdict: $verdict" >&2; return 2 ;;
  esac
}

parse_merged() {
  output=${1-}
  require_nonempty_output merge "$output"
  printf '%s\n' "$output" | grep -Eq '^## Merge Complete[[:space:]]*$' || {
    echo "malformed merge output: missing success heading" >&2; return 2;
  }
  printf '%s\n' "$output" | grep -Eq '^\*\*PR:\*\* #[1-9][0-9]* .+' || {
    echo "malformed merge output: missing positive PR number" >&2; return 2;
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
      [ "$#" -eq 1 ] || { echo "address transition requires exactly one output" >&2; return 2; }
      parse_addressed "$1"
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
      [ "$#" -eq 1 ] || { echo "docs-address transition requires exactly one output" >&2; return 2; }
      parse_addressed "$1"
      echo docs
      ;;
    verify)
      [ "$#" -eq 1 ] || { echo "verify transition requires exactly one output" >&2; return 2; }
      verdict=$(parse_verdict "$1")
      case "$verdict" in PASS|N/A) echo merge ;; FAIL|PARTIAL) echo verification-address ;; esac
      ;;
    verification-address)
      [ "$#" -eq 1 ] || { echo "verification-address transition requires exactly one output" >&2; return 2; }
      parse_addressed "$1"
      echo verify
      ;;
    merge)
      [ "$#" -eq 1 ] || { echo "merge transition requires exactly one output" >&2; return 2; }
      parse_merged "$1"
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
