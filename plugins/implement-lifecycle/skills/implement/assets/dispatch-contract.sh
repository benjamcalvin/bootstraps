#!/bin/bash
# Shared dispatch and transition contract for the implement lifecycle.
set -euo pipefail

PLUGIN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

usage() {
  echo "usage: $0 target <claude|codex> <worker> | targets <claude|codex> <worker>... | transition <phase> [--reviewers <reviewer>...] -- <worker-output>..." >&2
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
  require_nonempty_output "$reviewer reviewer" "$output"
  label=$(reviewer_label "$reviewer")
  printf '%s\n' "$output" | grep -Eq '^### Summary[[:space:]]*$' || {
    echo "malformed $reviewer reviewer output: missing ### Summary" >&2
    return 2
  }
  printf '%s\n' "$output" | awk '/^### Summary[[:space:]]*$/{if (getline > 0 && $0 ~ /[^[:space:]]/) found=1} END{exit !found}' || {
    echo "malformed $reviewer reviewer output: empty summary" >&2
    return 2
  }
  invalid_headings=$(printf '%s\n' "$output" | grep '^### ' | grep -Ev '^### (Action Required|Recommended|Minor|Summary)[[:space:]]*$' || true)
  [ -z "$invalid_headings" ] || {
    echo "malformed $reviewer reviewer output: unsupported category" >&2
    return 2
  }
  findings=$(printf '%s\n' "$output" | grep -Ec "^- \*\*\[($label)\]\*\* .+" || true)
  bullets=$(printf '%s\n' "$output" | grep -Ec '^- ' || true)
  [ "$findings" -eq "$bullets" ] || {
    echo "malformed $reviewer reviewer output: finding tag does not match reviewer" >&2
    return 2
  }
  printf '%s\n' "$findings"
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
  case "$verdict" in PASS|FAIL|PARTIAL|N/A) printf '%s\n' "$verdict" ;; *) echo "unsupported verification verdict: $verdict" >&2; return 2 ;; esac
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
      [ "${1-}" = --reviewers ] || { echo "review transition requires --reviewers" >&2; return 2; }
      shift
      reviewers=()
      while [ "$#" -gt 0 ] && [ "$1" != -- ]; do reviewers+=("$1"); shift; done
      [ "${1-}" = -- ] || { echo "review transition requires -- before outputs" >&2; return 2; }
      shift
      [ "${#reviewers[@]}" -gt 0 ] || { echo "review transition requires one or more reviewers" >&2; return 2; }
      [ "$#" -eq "${#reviewers[@]}" ] || { echo "review transition requires exactly one output per selected reviewer" >&2; return 2; }
      outputs=("$@")
      total=0
      seen=' '
      index=0
      for reviewer in "${reviewers[@]}"; do
        case "$reviewer" in correctness|security|architecture|testing) ;; *) echo "invalid code reviewer: $reviewer" >&2; return 2 ;; esac
        case "$seen" in *" $reviewer "*) echo "duplicate selected reviewer: $reviewer" >&2; return 2 ;; esac
        seen="$seen$reviewer "
        output=${outputs[$index]}
        count=$(parse_review_count "$reviewer" "$output")
        total=$((total + count))
        index=$((index + 1))
      done
      if [ "$total" -eq 0 ]; then echo docs; else echo address; fi
      ;;
    address)
      [ "$#" -eq 1 ] || { echo "address transition requires exactly one output" >&2; return 2; }
      parse_addressed "$1"
      echo review
      ;;
    docs)
      [ "$#" -eq 1 ] || { echo "docs transition requires exactly one output" >&2; return 2; }
      count=$(parse_review_count docs "$1")
      if [ "$count" -eq 0 ]; then echo verify; else echo docs-address; fi
      ;;
    docs-address)
      [ "$#" -eq 1 ] || { echo "docs-address transition requires exactly one output" >&2; return 2; }
      parse_addressed "$1"
      echo docs
      ;;
    verify)
      [ "$#" -eq 1 ] || { echo "verify transition requires exactly one output" >&2; return 2; }
      verdict=$(parse_verdict "$1")
      case "$verdict" in PASS|N/A) echo merge ;; FAIL|PARTIAL) echo address ;; esac
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
  transition)
    [ "$#" -ge 3 ] || usage
    phase=$2
    shift 2
    transition "$phase" "$@"
    ;;
  *) usage ;;
esac
