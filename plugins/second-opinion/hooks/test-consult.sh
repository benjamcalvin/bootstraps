#!/usr/bin/env bash
set -uo pipefail
# autotest — self-contained, no external dependencies; run by validate-all.sh

# test-consult.sh — Regression tests for scripts/consult.sh.
#
# Covers the deterministic argument-dispatch and error-contract paths, plus
# provider detection and CLI-failure paths using PATH-mounted stub binaries.
# No network, no real codex/agy CLI required.
#
# Usage:
#   ./test-consult.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONSULT="$SCRIPT_DIR/../scripts/consult.sh"
BASH_BIN="$(command -v bash)"

if [ ! -f "$CONSULT" ]; then
  echo "FAIL: consult.sh not found at $CONSULT"
  exit 1
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Scratch workspace (stub bins, prompt files). Cleaned on exit.
WORK="$(mktemp -d -t second-opinion-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

PROMPT="$WORK/prompt.md"
printf 'Review this diff.\n' > "$PROMPT"

# Real PATH is needed by run_codex/run_antigravity (mktemp/cat/sh). Stub dirs
# get prepended to it so a stub binary shadows any real CLI on the machine.
REAL_PATH="$PATH"

# make_stub <dir> <name> <body-line...> — create an executable stub on a fresh
# PATH dir. Uses /bin/sh (absolute interpreter) so it runs regardless of PATH.
make_stub() {
  local dir="$1" name="$2"; shift 2
  mkdir -p "$dir"
  { printf '#!/bin/sh\n'; printf '%s\n' "$@"; } > "$dir/$name"
  chmod +x "$dir/$name"
}

# expect_exit <expected> <desc> <path> -- <consult-args...>
# Runs consult.sh with PATH set to <path>; compares the exit code. Args after
# the literal `--` are passed to consult.sh (may be empty, e.g. the no-arg case).
expect_exit() {
  local expected="$1" desc="$2" path="$3"; shift 3
  shift  # drop the literal --
  PATH="$path" "$BASH_BIN" "$CONSULT" "$@" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq "$expected" ]; then pass; else fail "$desc (expected exit $expected, got $rc)"; fi
}

# run_stdout <path> -- <consult-args...> : echo consult.sh stdout (exit ignored).
run_stdout() {
  local path="$1"; shift 2  # drop path and the literal --
  PATH="$path" "$BASH_BIN" "$CONSULT" "$@" 2>/dev/null
}

echo "=== consult.sh Tests ==="
echo ""

# --- Argument-dispatch / usage errors (exit 1) ---
# An empty PATH is fine: none of these paths invoke an external binary.
expect_exit 1 "no args -> usage error"           "" --
expect_exit 1 "unknown provider -> error"        "" -- gemini "$PROMPT"
expect_exit 1 "missing prompt-file arg -> error" "" -- codex
expect_exit 1 "nonexistent prompt file -> error" "" -- codex "$WORK/does-not-exist.md"

# --- Provider installed check (exit 2) ---
# Valid provider + valid prompt file, but the binary is not on PATH.
expect_exit 2 "codex not on PATH -> exit 2"       "" -- codex "$PROMPT"
expect_exit 2 "antigravity not on PATH -> exit 2" "" -- antigravity "$PROMPT"

# --- list / available() detection ---
# Empty case: no providers on PATH -> empty output, exit 0.
expect_exit 0 "list exits 0 with no providers" "" -- list
out="$(run_stdout "" -- list)"
if [ -z "$out" ]; then pass; else fail "list with no providers should print nothing (got: $out)"; fi

# Positive detection + binary_for mapping, via stub bins on a temp PATH.
STUB_BOTH="$WORK/bin-both"
make_stub "$STUB_BOTH" codex "exit 0"
make_stub "$STUB_BOTH" agy   "exit 0"
out="$(run_stdout "$STUB_BOTH" -- list)"
echo "$out" | grep -qx codex       && pass || fail "list should include 'codex' when codex is on PATH"
echo "$out" | grep -qx antigravity && pass || fail "list should include 'antigravity' when agy is on PATH"

# binary_for mapping isolated: only codex present -> only 'codex'.
STUB_CODEX="$WORK/bin-codex"
make_stub "$STUB_CODEX" codex "exit 0"
out="$(run_stdout "$STUB_CODEX" -- list)"
if [ "$out" = "codex" ]; then pass; else fail "codex-only PATH should list exactly 'codex' (got: $out)"; fi

# Only agy present -> only 'antigravity' (proves antigravity->agy mapping).
STUB_AGY="$WORK/bin-agy"
make_stub "$STUB_AGY" agy "exit 0"
out="$(run_stdout "$STUB_AGY" -- list)"
if [ "$out" = "antigravity" ]; then pass; else fail "agy-only PATH should list exactly 'antigravity' (got: $out)"; fi

# --- CLI-failure paths (exit 3), via stub bins that shadow the real CLI. ---

# codex exits non-zero -> exit 3.
STUB_CODEX_FAIL="$WORK/bin-codex-fail"
make_stub "$STUB_CODEX_FAIL" codex "exit 1"
expect_exit 3 "codex non-zero exit -> exit 3" "$STUB_CODEX_FAIL:$REAL_PATH" -- codex "$PROMPT"

# codex exits 0 but writes nothing to --output-last-message -> exit 3.
STUB_CODEX_EMPTY="$WORK/bin-codex-empty"
make_stub "$STUB_CODEX_EMPTY" codex "exit 0"
expect_exit 3 "codex empty output -> exit 3" "$STUB_CODEX_EMPTY:$REAL_PATH" -- codex "$PROMPT"

# agy exits non-zero -> exit 3.
STUB_AGY_FAIL="$WORK/bin-agy-fail"
make_stub "$STUB_AGY_FAIL" agy "exit 1"
expect_exit 3 "agy non-zero exit -> exit 3" "$STUB_AGY_FAIL:$REAL_PATH" -- antigravity "$PROMPT"

# agy exits 0 but prints nothing -> exit 3 (empty response).
STUB_AGY_EMPTY="$WORK/bin-agy-empty"
make_stub "$STUB_AGY_EMPTY" agy "exit 0"
expect_exit 3 "agy empty response -> exit 3" "$STUB_AGY_EMPTY:$REAL_PATH" -- antigravity "$PROMPT"

# --- Antigravity invocation: prompt passed as an argv element (not stdin) ---
# Real `agy -p` takes the prompt as its ARGUMENT VALUE, not on stdin; feeding
# it on stdin fails with "flag needs an argument: -p". This regression test
# would have caught the round-1 stdin approach: the agy stub echoes its argv
# one element per line, and run_antigravity returns it as the review text, so
# the prompt text itself must appear as a captured argv line.
STUB_AGY_ECHO="$WORK/bin-agy-echo"
make_stub "$STUB_AGY_ECHO" agy 'for a in "$@"; do printf "%s\n" "$a"; done'

# The prompt CONTENT must reach agy as an argv element (proves it is an argument,
# not sent on stdin). PROMPT holds "Review this diff." (see above).
out="$(PATH="$STUB_AGY_ECHO:$REAL_PATH" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- 'Review this diff.'; then pass; else fail "prompt text must be passed as an argv element to agy, not on stdin (got: $out)"; fi
# And the -p/--print flag must be present.
if echo "$out" | grep -qxE -- '-p|--print'; then pass; else fail "agy must be invoked with -p/--print (got: $out)"; fi

# A stub that rejects a missing positional prompt (mimicking real agy's "flag
# needs an argument: -p") must NOT fire — the prompt is always supplied as an
# argument, so this stub should succeed and echo the prompt back.
STUB_AGY_STRICT="$WORK/bin-agy-strict"
make_stub "$STUB_AGY_STRICT" agy \
  'has_prompt=0' \
  'prev=' \
  'for a in "$@"; do case "$prev" in -p|--print) has_prompt=1;; esac; prev="$a"; done' \
  'if [ "$has_prompt" -eq 0 ]; then echo "flag needs an argument: -p" >&2; exit 2; fi' \
  'echo "STRICT AGY OK"'
out="$(PATH="$STUB_AGY_STRICT:$REAL_PATH" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "STRICT AGY OK" ]; then pass; else fail "agy must receive a positional prompt after -p (rc=$rc, got: $out)"; fi

# Prompt-size guard: a prompt over the ~120 KiB argv limit must fail with exit 3
# rather than letting the shell die with E2BIG. Uses the echo stub (never reached).
BIG_PROMPT="$WORK/big-prompt.md"
head -c 130000 /dev/zero | tr '\0' 'x' > "$BIG_PROMPT"
expect_exit 3 "oversized antigravity prompt -> exit 3" "$STUB_AGY_ECHO:$REAL_PATH" -- antigravity "$BIG_PROMPT"

# --- Model-override flag construction (antigravity path) ---
# With no override, no -m flag should be constructed.
out="$(PATH="$STUB_AGY_ECHO:$REAL_PATH" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m'; then fail "no override should not pass -m (got: $out)"; else pass; fi

# With a single-word override, -m and the model name should both be present.
out="$(PATH="$STUB_AGY_ECHO:$REAL_PATH" SECOND_OPINION_ANTIGRAVITY_MODEL="my-model" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m' && echo "$out" | grep -qx -- 'my-model'; then pass; else fail "override should pass '-m my-model' (got: $out)"; fi

# With a spaced (multi-word) override, the whole value must survive as one argv
# element — i.e. a line equal to "Gemini 3.1 Pro", not truncated at the space.
out="$(PATH="$STUB_AGY_ECHO:$REAL_PATH" SECOND_OPINION_ANTIGRAVITY_MODEL="Gemini 3.1 Pro" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m' && echo "$out" | grep -qx -- 'Gemini 3.1 Pro'; then pass; else fail "spaced override should pass '-m' then intact 'Gemini 3.1 Pro' (got: $out)"; fi

# --- Codex happy path (exit 0, review text) ---
# codex writes its final message to the file named after --output-last-message.
# This stub locates that path in its own argv and writes known review text there,
# so run_codex should cat it back verbatim on stdout and exit 0.
STUB_CODEX_OK="$WORK/bin-codex-ok"
make_stub "$STUB_CODEX_OK" codex \
  'prev=; out=' \
  'for a in "$@"; do if [ "$prev" = "--output-last-message" ]; then out="$a"; fi; prev="$a"; done' \
  'printf "CODEX REVIEW OK\n" > "$out"' \
  'exit 0'
out="$(PATH="$STUB_CODEX_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "CODEX REVIEW OK" ]; then pass; else fail "codex happy path should print review text and exit 0 (rc=$rc, got: $out)"; fi

# --- Model-override flag construction (codex path) ---
# codex stub echoes its argv (one element per line) into the --output-last-message
# file, which run_codex then cats to stdout. Per-line output lets us match the
# flag exactly with grep -x, avoiding a false positive from the "-m" substring
# inside "--output-last-message".
STUB_CODEX_ECHO="$WORK/bin-codex-echo"
make_stub "$STUB_CODEX_ECHO" codex \
  'prev=; out=' \
  'for a in "$@"; do if [ "$prev" = "--output-last-message" ]; then out="$a"; fi; prev="$a"; done' \
  'for a in "$@"; do printf "%s\n" "$a"; done > "$out"' \
  'exit 0'

# With no override, no bare -m flag should be constructed.
out="$(PATH="$STUB_CODEX_ECHO:$REAL_PATH" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m'; then fail "codex no override should not pass -m (got: $out)"; else pass; fi

# Read-only guarantee: codex must always be invoked with --sandbox read-only.
# Reuse the argv captured above (per-line, so grep -x matches each element).
if echo "$out" | grep -qx -- '--sandbox' && echo "$out" | grep -qx -- 'read-only'; then pass; else fail "codex must pass '--sandbox read-only' (got: $out)"; fi

# With a single-word override, -m and the model name should both be present.
out="$(PATH="$STUB_CODEX_ECHO:$REAL_PATH" SECOND_OPINION_CODEX_MODEL="my-model" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m' && echo "$out" | grep -qx -- 'my-model'; then pass; else fail "codex override should pass '-m my-model' (got: $out)"; fi

# With a spaced (multi-word) override, the whole value must survive as one argv
# element — a line equal to "Gemini 3.1 Pro", not split at the spaces.
out="$(PATH="$STUB_CODEX_ECHO:$REAL_PATH" SECOND_OPINION_CODEX_MODEL="Gemini 3.1 Pro" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m' && echo "$out" | grep -qx -- 'Gemini 3.1 Pro'; then pass; else fail "codex spaced override should pass '-m' then intact 'Gemini 3.1 Pro' (got: $out)"; fi

echo ""
echo "Results: $PASS passed, $FAIL failed ($(( PASS + FAIL )) total)"

if [ "$FAIL" -gt 0 ]; then
  echo "FAILED"
  exit 1
fi

echo "PASSED"
