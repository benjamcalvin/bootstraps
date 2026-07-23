#!/bin/bash
# Shared dispatch and transition contract for the implement lifecycle.
set -euo pipefail

PLUGIN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

usage() {
  echo "usage: $0 target <claude|codex> <worker> | targets <claude|codex> <worker>... | transition <phase> <result>..." >&2
  exit 2
}

skill_path() {
  case "$1" in
    implement-code|review-correctness|review-security|review-architecture|review-testing|implement-address|review-docs|verify|merge-pr)
      printf '%s/skills/%s/SKILL.md\n' "$PLUGIN_DIR" "$1"
      ;;
    *) return 1 ;;
  esac
}

target() {
  client=$1
  worker=$2
  path=$(skill_path "$worker") || {
    echo "unknown lifecycle worker: $worker" >&2
    return 2
  }
  if [ ! -f "$path" ]; then
    echo "missing lifecycle skill entry point: ${path#"$PLUGIN_DIR"/}" >&2
    return 2
  fi
  case "$client" in
    claude) printf '%s\n' "$worker" ;;
    codex) printf '$implement-lifecycle:%s\n' "$worker" ;;
    *) echo "unknown client: $client" >&2; return 2 ;;
  esac
}

require_result() {
  key=$1
  shift
  for result in "$@"; do
    case "$result" in
      "$key"=*) printf '%s\n' "${result#*=}"; return 0 ;;
    esac
  done
  echo "missing required result: $key" >&2
  return 2
}

transition() {
  phase=$1
  shift
  case "$phase" in
    implement)
      require_result PR_NUMBER "$@" >/dev/null
      echo review
      ;;
    review)
      total=0
      for reviewer in correctness security architecture testing; do
        count=$(require_result "$reviewer" "$@")
        case "$count" in *[!0-9]*|'') echo "invalid $reviewer finding count: $count" >&2; return 2 ;; esac
        total=$((total + count))
      done
      if [ "$total" -eq 0 ]; then echo docs; else echo address; fi
      ;;
    address)
      require_result ADDRESSED "$@" >/dev/null
      echo review
      ;;
    docs)
      count=$(require_result docs "$@")
      case "$count" in *[!0-9]*|'') echo "invalid docs finding count: $count" >&2; return 2 ;; esac
      if [ "$count" -eq 0 ]; then echo verify; else echo docs-address; fi
      ;;
    docs-address)
      require_result ADDRESSED "$@" >/dev/null
      echo docs
      ;;
    verify)
      verdict=$(require_result VERDICT "$@")
      case "$verdict" in PASS|N/A) echo merge ;; FAIL) echo address ;; *) echo "invalid verification verdict: $verdict" >&2; return 2 ;; esac
      ;;
    merge)
      require_result MERGED "$@" >/dev/null
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
    [ "$#" -ge 4 ] || usage
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
