#!/usr/bin/env bash
set -euo pipefail

# consult.sh — run a headless, read-only code review via an external AI CLI.
#
# Usage:
#   consult.sh list                        # print available providers, one per line
#   consult.sh <provider> <prompt-file>    # run review, print review text to stdout
#
# Providers:
#   codex        OpenAI Codex CLI (binary: codex)
#   antigravity  Google Antigravity CLI (binary: agy)
#
# Both providers are invoked read-only: codex via --sandbox read-only,
# antigravity via print mode, which denies tool calls that lack an allow
# rule (reads are permitted, writes/commands are not). Run from the repo
# root you want reviewed — providers inherit the CWD.
#
# Model overrides (optional):
#   SECOND_OPINION_CODEX_MODEL        e.g. "gpt-5-codex"
#   SECOND_OPINION_ANTIGRAVITY_MODEL  e.g. "Gemini 3.1 Pro"
#
# Exit codes: 0 success, 1 usage error, 2 provider not installed, 3 provider failed.

PROVIDERS=(codex antigravity)

log() { echo "consult.sh: $*" >&2; }

binary_for() {
  case "$1" in
    codex) echo "codex" ;;
    antigravity) echo "agy" ;;
  esac
}

available() {
  for p in "${PROVIDERS[@]}"; do
    if command -v "$(binary_for "$p")" >/dev/null 2>&1; then
      echo "$p"
    fi
  done
}

run_codex() {
  local prompt_file="$1"
  local out rc=0
  out=$(mktemp -t second-opinion-codex.XXXXXX)
  # Cleanup is explicit (not a RETURN trap): a RETURN trap persists globally
  # and would re-fire when later functions (e.g. main) return, so its scope is
  # ambiguous and fragile if a call is ever added after run_$provider in main.
  # Removing the temp file on every path here keeps the scope unambiguous.

  # codex exec: non-interactive mode. Final agent message goes to the
  # --output-last-message file; progress noise stays on stdout/stderr.
  codex exec \
    --sandbox read-only \
    --skip-git-repo-check \
    ${SECOND_OPINION_CODEX_MODEL:+-m "$SECOND_OPINION_CODEX_MODEL"} \
    --output-last-message "$out" \
    - < "$prompt_file" >&2 || rc=3

  if [ "$rc" -eq 0 ] && [ ! -s "$out" ]; then
    log "codex produced no output"
    rc=3
  fi

  [ "$rc" -eq 0 ] && cat "$out"
  rm -f "$out"
  return "$rc"
}

run_antigravity() {
  local prompt_file="$1"
  local response

  # agy -p: print mode, runs one prompt non-interactively and exits.
  # Tool calls without an allow rule are denied in print mode, so the
  # agent can read the repo but not modify it.
  #
  # The prompt is fed on stdin rather than as an argv element. Passing it
  # as an argument (agy -p "$(cat …)") caps the prompt at the per-argument
  # limit — on Linux MAX_ARG_STRLEN is 128 KiB regardless of ARG_MAX — so a
  # large diff would fail with E2BIG. stdin has no such cap, and it still
  # can't hang waiting for approval in a non-TTY context because the prompt
  # file reaches EOF (equivalent to the previous < /dev/null behaviour).
  #
  # NOTE: that `agy -p` consumes stdin as the prompt is expected but not yet
  # verified against a real `agy` install — unlike codex, agy has no documented
  # explicit stdin marker (codex uses `-`). Do NOT revert to an argv prompt to
  # "fix" this: stdin is required for the large diffs this plugin exists to
  # review. Confirm behaviour via maintainer real-machine verification.
  response=$(agy -p \
    ${SECOND_OPINION_ANTIGRAVITY_MODEL:+-m "$SECOND_OPINION_ANTIGRAVITY_MODEL"} \
    < "$prompt_file") || return 3

  [ -n "$response" ] || { log "antigravity produced an empty response"; return 3; }
  printf '%s\n' "$response"
}

main() {
  [ $# -ge 1 ] || { log "usage: consult.sh list | consult.sh <provider> <prompt-file>"; exit 1; }

  if [ "$1" = "list" ]; then
    available
    exit 0
  fi

  local provider="$1" prompt_file="${2:-}"
  case "$provider" in
    codex|antigravity) ;;
    *) log "unknown provider: $provider (supported: ${PROVIDERS[*]})"; exit 1 ;;
  esac
  [ -n "$prompt_file" ] || { log "usage: consult.sh <provider> <prompt-file>"; exit 1; }
  [ -f "$prompt_file" ] || { log "prompt file not found: $prompt_file"; exit 1; }

  local bin
  bin=$(binary_for "$provider")
  command -v "$bin" >/dev/null 2>&1 || {
    log "$provider CLI ($bin) not found in PATH"
    exit 2
  }

  "run_$provider" "$prompt_file"
}

main "$@"
