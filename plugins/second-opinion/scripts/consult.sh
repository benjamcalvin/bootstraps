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

  # agy -p / --print: print mode, runs one prompt non-interactively and exits.
  # Tool calls without an allow rule are denied in print mode, so the agent can
  # read the repo but not modify it.
  #
  # `agy -p` takes the prompt as its ARGUMENT VALUE (agy -p "<prompt text>") —
  # verified against real agy 1.1.4. It is NOT a stdin-reading toggle: `agy -p
  # < file` fails with "flag needs an argument: -p". There is no documented agy
  # stdin-prompt mechanism, so we must pass the prompt as an argv element and
  # read stdin from /dev/null — the /dev/null redirect only prevents hanging on
  # an approval prompt in a non-TTY context; it is not the prompt source.
  #
  # Passing the prompt as an argv element reintroduces the per-argument size cap
  # (Linux MAX_ARG_STRLEN is ~128 KiB regardless of ARG_MAX). Guard against it
  # below and fail loudly rather than letting the shell die with a cryptic
  # E2BIG / "Argument list too long". The SKILL's ~4000-line diff truncation
  # normally keeps prompts well under this; this guard is the backstop.
  local size
  size=$(wc -c < "$prompt_file")
  if [ "$size" -gt 122880 ]; then
    log "antigravity prompt is ${size} bytes, over the ~120 KiB limit for agy's argument-based interface; narrow the review scope (fewer files / smaller diff)"
    return 3
  fi

  response=$(agy -p "$(cat "$prompt_file")" \
    ${SECOND_OPINION_ANTIGRAVITY_MODEL:+-m "$SECOND_OPINION_ANTIGRAVITY_MODEL"} \
    < /dev/null) || return 3

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
