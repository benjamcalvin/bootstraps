#!/usr/bin/env bash
set -uo pipefail
# autotest — self-contained, no external dependencies; run by validate-all.sh

# test-consult.sh — Regression tests for scripts/consult.sh.
#
# Covers the deterministic argument-dispatch and error-contract paths, the
# privilege-tier interface (default `consult`, escalation refusal), the
# fail-closed srt wrapper checks (ADR-001 Decisions 5-6), allowlist plumbing,
# environment scrubbing, and run-dir cleanup — all using PATH-mounted stub
# binaries. No network, no real codex/agy/srt required.
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

# make_srt_stub <dir> <extra-line...> — create a passthrough `srt` stub that
# mimics the real invocation shape (`srt --settings <cfg> -- <cmd...>`): it
# strips srt's own options, runs any extra lines (with $settings holding the
# settings-file path), then execs the wrapped command. Platform-dep stubs
# (sandbox-exec/bwrap/socat) are added so the fail-closed platform check
# passes on any host OS.
make_srt_stub() {
  local dir="$1"; shift
  make_stub "$dir" srt \
    'settings=' \
    'while [ $# -gt 0 ]; do' \
    '  case "$1" in' \
    '    -s|--settings) settings="$2"; shift 2 ;;' \
    '    --) shift; break ;;' \
    '    *) shift ;;' \
    '  esac' \
    'done' \
    "$@" \
    'exec "$@"'
  make_stub "$dir" sandbox-exec 'exit 0'
  make_stub "$dir" bwrap 'exit 0'
  make_stub "$dir" socat 'exit 0'
  # Deterministic platform answer so the platform-dep check resolves against
  # the stubs above regardless of the host OS.
  make_stub "$dir" uname 'echo Darwin'
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

# run_stderr <path> -- <consult-args...> : echo consult.sh stderr (exit ignored).
run_stderr() {
  local path="$1"; shift 2  # drop path and the literal --
  PATH="$path" "$BASH_BIN" "$CONSULT" "$@" 2>&1 >/dev/null
}

echo "=== consult.sh Tests ==="
echo ""

# Passthrough srt stub used by every test that reaches provider execution:
# the wrapper is a hard prerequisite now, so provider stubs alone are not
# enough to get past the fail-closed checks.
STUB_SRT_OK="$WORK/bin-srt-ok"
make_srt_stub "$STUB_SRT_OK"

# --- Argument-dispatch / usage errors (exit 1) ---
# An empty PATH is fine: none of these paths invoke an external binary.
expect_exit 1 "no args -> usage error"           "" --
expect_exit 1 "unknown provider -> error"        "" -- gemini "$PROMPT"
expect_exit 1 "missing prompt-file arg -> error" "" -- codex
expect_exit 1 "nonexistent prompt file -> error" "" -- codex "$WORK/does-not-exist.md"
expect_exit 1 "unknown option -> error"          "" -- --bogus codex "$PROMPT"

# --- Tier interface: parsing errors and act-full escalation refusal (exit 1) ---
# act-sandboxed is now wired (issue #77 PR 3); act-full remains gated/refused.
expect_exit 1 "unknown tier -> error"            "" -- --tier super-user codex "$PROMPT"
expect_exit 1 "--tier without value -> error"    "" -- --tier
expect_exit 1 "act-full tier -> refused"         "" -- --tier act-full codex "$PROMPT"

# act-full refusal must be actionable: name the tier and its approval gate, and
# point at the working tier. No silent escalation (ADR-001 Decision 4).
err="$(run_stderr "" -- --tier act-full codex "$PROMPT")"
echo "$err" | grep -q "act-full" && echo "$err" | grep -qi "approval" \
  && pass || fail "act-full refusal should name the tier and its approval gate (got: $err)"
echo "$err" | grep -q -- "--tier consult" && pass || fail "act-full refusal should point at the consult tier (got: $err)"

# act-full refusal must happen before any provider invocation: a provider stub
# that drops a marker file must never run.
STUB_MARKER="$WORK/bin-marker"
make_stub "$STUB_MARKER" codex "touch $WORK/invoked-marker" "exit 0"
PATH="$STUB_MARKER:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" --tier act-full codex "$PROMPT" >/dev/null 2>&1
if [ ! -f "$WORK/invoked-marker" ]; then pass; else fail "refused act-full tier must not invoke the provider CLI"; fi

# --- Fail-closed srt checks (ADR-001 Decisions 5-6) ---

# srt missing entirely (provider IS present) -> exit 2, actionable message
# naming the pinned version and the install command. PATH is the codex stub dir
# ONLY (no REAL_PATH), so a real srt installed on the host cannot leak in and
# make the fail-closed check pass; the check fires before SCRIPT_DIR is used.
STUB_CODEX_ONLY="$WORK/bin-codex-only"
make_stub "$STUB_CODEX_ONLY" codex "exit 0"
expect_exit 2 "srt not on PATH -> exit 2" "$STUB_CODEX_ONLY" -- codex "$PROMPT"
err="$(run_stderr "$STUB_CODEX_ONLY" -- codex "$PROMPT")"
echo "$err" | grep -q "sandbox-runtime@0.0.66" && echo "$err" | grep -q "npm install" \
  && pass || fail "srt-missing error should name the pinned version and install command (got: $err)"

# Bare PATH: neither srt nor the provider is installed -> exit 2 (fail-closed
# fires on the missing wrapper before the provider check is even reached).
expect_exit 2 "codex + srt not on PATH -> exit 2"       "" -- codex "$PROMPT"
expect_exit 2 "antigravity + srt not on PATH -> exit 2" "" -- antigravity "$PROMPT"

# srt present but the provider missing -> exit 2 mentioning the provider CLI.
# PATH is the srt stub dir ONLY (not REAL_PATH), so a codex CLI installed on
# the host machine cannot leak into this test and get invoked for real.
expect_exit 2 "srt present, codex missing -> exit 2" "$STUB_SRT_OK" -- codex "$PROMPT"
err="$(run_stderr "$STUB_SRT_OK" -- codex "$PROMPT")"
echo "$err" | grep -q "codex" && pass || fail "provider-missing error should name the provider (got: $err)"

# srt present but fails to start (preflight) -> exit 3, actionable message.
STUB_SRT_FAIL="$WORK/bin-srt-fail"
make_stub "$STUB_SRT_FAIL" srt 'echo "srt: boom" >&2' 'exit 1'
make_stub "$STUB_SRT_FAIL" sandbox-exec 'exit 0'
make_stub "$STUB_SRT_FAIL" bwrap 'exit 0'
make_stub "$STUB_SRT_FAIL" socat 'exit 0'
STUB_CODEX_OK0="$WORK/bin-codex-ok0"
make_stub "$STUB_CODEX_OK0" codex "exit 0"
expect_exit 3 "srt fails to start -> exit 3" "$STUB_CODEX_OK0:$STUB_SRT_FAIL:$REAL_PATH" -- codex "$PROMPT"
err="$(run_stderr "$STUB_CODEX_OK0:$STUB_SRT_FAIL:$REAL_PATH" -- codex "$PROMPT")"
echo "$err" | grep -qi "failed to start" && pass || fail "srt-failure error should say the wrapper failed to start (got: $err)"

# --- Platform-dependency fail-closed checks (ADR-001 Decision 6) ---
# srt itself is present, but the OS-level dependency it needs to enforce the
# jail is not -> exit 2, never a silent skip. These PATHs deliberately exclude
# REAL_PATH so the host machine's own sandbox-exec/bwrap/socat cannot leak in;
# a dirname stub covers the one external binary consult.sh needs before the
# check fires (SCRIPT_DIR resolution).
#
# make_srt_nodep_stub <dir> <platform> — srt present, `uname -s` forced to
# <platform>, and NO platform-dep binaries on the PATH.
make_srt_nodep_stub() {
  local dir="$1" platform="$2"
  make_stub "$dir" srt 'exit 0'
  make_stub "$dir" uname "echo $platform"
  make_stub "$dir" dirname 'echo "${1%/*}"'
}

# Darwin with sandbox-exec (Seatbelt) missing -> exit 2 naming the dep.
STUB_NODEP_DARWIN="$WORK/bin-srt-nodep-darwin"
make_srt_nodep_stub "$STUB_NODEP_DARWIN" Darwin
expect_exit 2 "Darwin: sandbox-exec missing -> exit 2" "$STUB_NODEP_DARWIN" -- codex "$PROMPT"
err="$(run_stderr "$STUB_NODEP_DARWIN" -- codex "$PROMPT")"
echo "$err" | grep -q "sandbox-exec" && pass || fail "Darwin dep-missing error should name sandbox-exec (got: $err)"

# Linux with bwrap and socat missing -> exit 2 naming the first missing dep.
STUB_NODEP_LINUX="$WORK/bin-srt-nodep-linux"
make_srt_nodep_stub "$STUB_NODEP_LINUX" Linux
expect_exit 2 "Linux: bwrap missing -> exit 2" "$STUB_NODEP_LINUX" -- codex "$PROMPT"
err="$(run_stderr "$STUB_NODEP_LINUX" -- codex "$PROMPT")"
echo "$err" | grep -q "bwrap" && pass || fail "Linux dep-missing error should name bwrap (got: $err)"

# Linux with bwrap present but socat missing -> exit 2 naming socat.
STUB_NOSOCAT_LINUX="$WORK/bin-srt-nosocat-linux"
make_srt_nodep_stub "$STUB_NOSOCAT_LINUX" Linux
make_stub "$STUB_NOSOCAT_LINUX" bwrap 'exit 0'
expect_exit 2 "Linux: socat missing -> exit 2" "$STUB_NOSOCAT_LINUX" -- codex "$PROMPT"
err="$(run_stderr "$STUB_NOSOCAT_LINUX" -- codex "$PROMPT")"
echo "$err" | grep -q "socat" && pass || fail "Linux socat-missing error should name socat (got: $err)"

# Unknown platform -> exit 2 (explicit refusal, not a silent skip), even with
# every dep binary present — the refusal is about the platform itself.
STUB_UNKNOWN_OS="$WORK/bin-srt-unknown-os"
make_srt_nodep_stub "$STUB_UNKNOWN_OS" SunOS
make_stub "$STUB_UNKNOWN_OS" sandbox-exec 'exit 0'
make_stub "$STUB_UNKNOWN_OS" bwrap 'exit 0'
make_stub "$STUB_UNKNOWN_OS" socat 'exit 0'
expect_exit 2 "unknown platform -> exit 2 (fail-closed)" "$STUB_UNKNOWN_OS" -- codex "$PROMPT"
err="$(run_stderr "$STUB_UNKNOWN_OS" -- codex "$PROMPT")"
echo "$err" | grep -qi "unsupported platform" && pass || fail "unknown-platform refusal should say unsupported platform (got: $err)"

# --- list / available() detection ---
# Empty case: no providers on PATH -> empty output, exit 0.
expect_exit 0 "list exits 0 with no providers" "" -- list
out="$(run_stdout "" -- list)"
if [ -z "$out" ]; then pass; else fail "list with no providers should print nothing (got: $out)"; fi

# list warns on stderr (stdout stays machine-readable) when srt is missing.
err="$(run_stderr "" -- list)"
echo "$err" | grep -q "srt" && pass || fail "list should warn on stderr when srt is missing (got: $err)"

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
expect_exit 3 "codex non-zero exit -> exit 3" "$STUB_CODEX_FAIL:$STUB_SRT_OK:$REAL_PATH" -- codex "$PROMPT"

# codex exits 0 but writes nothing to --output-last-message -> exit 3.
STUB_CODEX_EMPTY="$WORK/bin-codex-empty"
make_stub "$STUB_CODEX_EMPTY" codex "exit 0"
expect_exit 3 "codex empty output -> exit 3" "$STUB_CODEX_EMPTY:$STUB_SRT_OK:$REAL_PATH" -- codex "$PROMPT"

# agy exits non-zero -> exit 3.
STUB_AGY_FAIL="$WORK/bin-agy-fail"
make_stub "$STUB_AGY_FAIL" agy "exit 1"
expect_exit 3 "agy non-zero exit -> exit 3" "$STUB_AGY_FAIL:$STUB_SRT_OK:$REAL_PATH" -- antigravity "$PROMPT"

# agy exits 0 but prints nothing -> exit 3 (empty response).
STUB_AGY_EMPTY="$WORK/bin-agy-empty"
make_stub "$STUB_AGY_EMPTY" agy "exit 0"
expect_exit 3 "agy empty response -> exit 3" "$STUB_AGY_EMPTY:$STUB_SRT_OK:$REAL_PATH" -- antigravity "$PROMPT"

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
out="$(PATH="$STUB_AGY_ECHO:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- 'Review this diff.'; then pass; else fail "prompt text must be passed as an argv element to agy, not on stdin (got: $out)"; fi
# And the -p/--print flag must be present.
if echo "$out" | grep -qxE -- '-p|--print'; then pass; else fail "agy must be invoked with -p/--print (got: $out)"; fi
# Read-only guarantee: agy must always be invoked with --sandbox. This is the
# antigravity analogue of codex's `--sandbox read-only`; dropping it would
# silently remove the read-only isolation (regression cover for finding round
# verify-2 #1/#2). The srt wrapper is the load-bearing boundary now, but the
# native flag stays on as defense-in-depth (ADR-001 Decision 3 note).
if echo "$out" | grep -qx -- '--sandbox'; then pass; else fail "agy must pass --sandbox for read-only isolation (got: $out)"; fi

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
out="$(PATH="$STUB_AGY_STRICT:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "STRICT AGY OK" ]; then pass; else fail "agy must receive a positional prompt after -p (rc=$rc, got: $out)"; fi

# Prompt-size guard: a prompt over the ~120 KiB argv limit must fail with exit 3
# rather than letting the shell die with E2BIG. Uses the echo stub (never reached).
BIG_PROMPT="$WORK/big-prompt.md"
head -c 130000 /dev/zero | tr '\0' 'x' > "$BIG_PROMPT"
expect_exit 3 "oversized antigravity prompt -> exit 3" "$STUB_AGY_ECHO:$STUB_SRT_OK:$REAL_PATH" -- antigravity "$BIG_PROMPT"

# --- Model-override flag construction (antigravity path) ---
# With no override, no -m flag should be constructed.
out="$(PATH="$STUB_AGY_ECHO:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m'; then fail "no override should not pass -m (got: $out)"; else pass; fi

# With a single-word override, -m and the model name should both be present.
out="$(PATH="$STUB_AGY_ECHO:$STUB_SRT_OK:$REAL_PATH" SECOND_OPINION_ANTIGRAVITY_MODEL="my-model" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m' && echo "$out" | grep -qx -- 'my-model'; then pass; else fail "override should pass '-m my-model' (got: $out)"; fi

# With a spaced (multi-word) override, the whole value must survive as one argv
# element — i.e. a line equal to "Gemini 3.1 Pro", not truncated at the space.
out="$(PATH="$STUB_AGY_ECHO:$STUB_SRT_OK:$REAL_PATH" SECOND_OPINION_ANTIGRAVITY_MODEL="Gemini 3.1 Pro" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"
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
out="$(PATH="$STUB_CODEX_OK:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "CODEX REVIEW OK" ]; then pass; else fail "codex happy path should print review text and exit 0 (rc=$rc, got: $out)"; fi

# --- Tier flag: explicit consult behaves exactly like the default ---
out="$(PATH="$STUB_CODEX_OK:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" --tier consult codex "$PROMPT" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "CODEX REVIEW OK" ]; then pass; else fail "--tier consult should behave like the default (rc=$rc, got: $out)"; fi
out="$(PATH="$STUB_CODEX_OK:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" --tier=consult codex "$PROMPT" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "CODEX REVIEW OK" ]; then pass; else fail "--tier=consult form should work (rc=$rc, got: $out)"; fi

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
out="$(PATH="$STUB_CODEX_ECHO:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m'; then fail "codex no override should not pass -m (got: $out)"; else pass; fi

# Read-only guarantee: codex must always be invoked with --sandbox read-only.
# Reuse the argv captured above (per-line, so grep -x matches each element).
if echo "$out" | grep -qx -- '--sandbox' && echo "$out" | grep -qx -- 'read-only'; then pass; else fail "codex must pass '--sandbox read-only' (got: $out)"; fi

# With a single-word override, -m and the model name should both be present.
out="$(PATH="$STUB_CODEX_ECHO:$STUB_SRT_OK:$REAL_PATH" SECOND_OPINION_CODEX_MODEL="my-model" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m' && echo "$out" | grep -qx -- 'my-model'; then pass; else fail "codex override should pass '-m my-model' (got: $out)"; fi

# With a spaced (multi-word) override, the whole value must survive as one argv
# element — a line equal to "Gemini 3.1 Pro", not split at the spaces.
out="$(PATH="$STUB_CODEX_ECHO:$STUB_SRT_OK:$REAL_PATH" SECOND_OPINION_CODEX_MODEL="Gemini 3.1 Pro" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -qx -- '-m' && echo "$out" | grep -qx -- 'Gemini 3.1 Pro'; then pass; else fail "codex spaced override should pass '-m' then intact 'Gemini 3.1 Pro' (got: $out)"; fi

# --- srt settings generation: shipped allowlist + denyRead policy ---
# A capturing srt stub copies the generated settings file to a known path so
# its contents can be asserted after the run-dir cleanup trap has fired.
CAPTURED="$WORK/captured-settings.json"
STUB_SRT_CAP="$WORK/bin-srt-cap"
make_srt_stub "$STUB_SRT_CAP" "cp \"\$settings\" \"$CAPTURED\" 2>/dev/null"

rm -f "$CAPTURED"
PATH="$STUB_CODEX_OK:$STUB_SRT_CAP:$REAL_PATH" "$BASH_BIN" "$CONSULT" codex "$PROMPT" >/dev/null 2>&1
if [ -f "$CAPTURED" ]; then pass; else fail "srt must be invoked with a --settings file"; fi
# Shipped codex allowlist domain present (provider API endpoints only).
grep -q '"chatgpt.com"' "$CAPTURED" 2>/dev/null && pass || fail "codex settings should contain the shipped chatgpt.com domain"
# Credential-path denyRead policy present (ADR-001 Decision 5 minimum set).
grep -q '~/.ssh' "$CAPTURED" 2>/dev/null && grep -q '~/.aws' "$CAPTURED" 2>/dev/null && grep -q '~/.config/gh' "$CAPTURED" 2>/dev/null \
  && pass || fail "settings must denyRead the credential paths (~/.ssh, ~/.aws, ~/.config/gh)"
# Settings must be valid JSON (jq is a repo prerequisite via validate-all.sh).
if command -v jq >/dev/null 2>&1; then
  jq . "$CAPTURED" >/dev/null 2>&1 && pass || fail "generated srt settings must be valid JSON"
fi

# codex must NOT get the antigravity-only relaxations: no keychain carve-out,
# no local binding, no weaker (trustd) network isolation.
if grep -q 'login.keychain-db' "$CAPTURED" 2>/dev/null; then fail "codex settings must not carve out the keychain"; else pass; fi
grep -q '"allowLocalBinding": false' "$CAPTURED" 2>/dev/null && grep -q '"enableWeakerNetworkIsolation": false' "$CAPTURED" 2>/dev/null \
  && pass || fail "codex settings should keep allowLocalBinding/enableWeakerNetworkIsolation off"

# Antigravity settings: shipped Google endpoints; no OpenAI endpoints leak in.
rm -f "$CAPTURED"
err="$(PATH="$STUB_AGY_ECHO:$STUB_SRT_CAP:$REAL_PATH" "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>&1 >/dev/null)"
grep -q 'googleapis.com' "$CAPTURED" 2>/dev/null && pass || fail "antigravity settings should contain the shipped Google API domains"
if grep -q 'chatgpt.com' "$CAPTURED" 2>/dev/null; then fail "antigravity settings must not contain codex domains"; else pass; fi
# The agy OAuth-token keychain carve-out must be present in the settings AND
# surfaced loudly on stderr at invocation time (ADR-001 Decision 5).
grep -q '"~/Library/Keychains/login.keychain-db"' "$CAPTURED" 2>/dev/null && pass || fail "antigravity settings should carve out the login keychain for the stored OAuth token"
echo "$err" | grep -q "login.keychain-db" && pass || fail "keychain carve-out must be surfaced on stderr (got: $err)"

# --- Allowlist user-extension mechanism (ADR-001 Decision 7) ---
# Extensions live in user-owned config (never the shipped files) and are
# surfaced loudly on stderr at invocation time.
EXT_DIR="$WORK/allowlist.d"
mkdir -p "$EXT_DIR"
printf '# my registry\nregistry.example.com\n' > "$EXT_DIR/codex.txt"
rm -f "$CAPTURED"
err="$(PATH="$STUB_CODEX_OK:$STUB_SRT_CAP:$REAL_PATH" SECOND_OPINION_ALLOWLIST_DIR="$EXT_DIR" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>&1 >/dev/null)"
grep -q '"registry.example.com"' "$CAPTURED" 2>/dev/null && pass || fail "user extension domain should be added to the settings"
grep -q '"chatgpt.com"' "$CAPTURED" 2>/dev/null && pass || fail "shipped domains should survive alongside extensions"
echo "$err" | grep -q "registry.example.com" && pass || fail "extension must be surfaced loudly on stderr (got: $err)"

# Malformed extension entries (JSON-injection attempts, junk) are skipped.
printf 'evil.com", "pwned.example\n' > "$EXT_DIR/codex.txt"
rm -f "$CAPTURED"
PATH="$STUB_CODEX_OK:$STUB_SRT_CAP:$REAL_PATH" SECOND_OPINION_ALLOWLIST_DIR="$EXT_DIR" "$BASH_BIN" "$CONSULT" codex "$PROMPT" >/dev/null 2>&1
if grep -q 'pwned.example' "$CAPTURED" 2>/dev/null; then fail "malformed extension entries must be rejected"; else pass; fi
if command -v jq >/dev/null 2>&1; then
  jq . "$CAPTURED" >/dev/null 2>&1 && pass || fail "settings must stay valid JSON when an extension entry is malformed"
fi
# With no extension file at all, no NOTICE is emitted.
err="$(PATH="$STUB_CODEX_OK:$STUB_SRT_CAP:$REAL_PATH" SECOND_OPINION_ALLOWLIST_DIR="$WORK/no-such-dir" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>&1 >/dev/null)"
if echo "$err" | grep -qi "extended beyond"; then fail "no extension file should mean no extension NOTICE (got: $err)"; else pass; fi

# --- Environment scrubbing (ADR-001 least-privilege pass-down) ---
# The delegate subprocess gets a scrubbed environment: ambient secrets must
# not leak in; HOME/PATH survive; the provider's own credential var passes.
STUB_AGY_ENV="$WORK/bin-agy-env"
make_stub "$STUB_AGY_ENV" agy 'env'
out="$(PATH="$STUB_AGY_ENV:$STUB_SRT_OK:$REAL_PATH" CANARY_SECRET=leakme AWS_SECRET_ACCESS_KEY=leakme2 ANTIGRAVITY_API_KEY=agy-cred "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -q 'CANARY_SECRET'; then fail "ambient env vars must not reach the delegate (CANARY_SECRET leaked)"; else pass; fi
if echo "$out" | grep -q 'AWS_SECRET_ACCESS_KEY'; then fail "ambient AWS credentials must not reach the delegate"; else pass; fi
echo "$out" | grep -q '^HOME=' && pass || fail "delegate must keep HOME (got env: $out)"
echo "$out" | grep -q '^ANTIGRAVITY_API_KEY=agy-cred$' && pass || fail "the provider's own credential var must pass through"
# The other provider's credential must NOT pass to codex runs and vice versa:
out="$(PATH="$STUB_AGY_ENV:$STUB_SRT_OK:$REAL_PATH" OPENAI_API_KEY=codex-cred "$BASH_BIN" "$CONSULT" antigravity "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -q 'OPENAI_API_KEY'; then fail "codex credential must not be passed to the antigravity delegate"; else pass; fi

# --- Run-dir cleanup on all exit paths ---
# Point TMPDIR at a private dir; after each run, no second-opinion-run.*
# residue may remain (mandatory-cleanup rule, ADR-001 least-privilege scope).
TDIR="$WORK/tmpdir"
mkdir -p "$TDIR"
leftovers() { ls "$TDIR" 2>/dev/null | grep -c 'second-opinion'; }
# happy path
PATH="$STUB_CODEX_OK:$STUB_SRT_OK:$REAL_PATH" TMPDIR="$TDIR" "$BASH_BIN" "$CONSULT" codex "$PROMPT" >/dev/null 2>&1
if [ "$(leftovers)" -eq 0 ]; then pass; else fail "happy path left run dirs behind: $(ls "$TDIR")"; fi
# provider-failure path (exit 3)
PATH="$STUB_CODEX_FAIL:$STUB_SRT_OK:$REAL_PATH" TMPDIR="$TDIR" "$BASH_BIN" "$CONSULT" codex "$PROMPT" >/dev/null 2>&1
if [ "$(leftovers)" -eq 0 ]; then pass; else fail "provider-failure path left run dirs behind: $(ls "$TDIR")"; fi
# srt-failure path (exit 3, preflight)
PATH="$STUB_CODEX_OK0:$STUB_SRT_FAIL:$REAL_PATH" TMPDIR="$TDIR" "$BASH_BIN" "$CONSULT" codex "$PROMPT" >/dev/null 2>&1
if [ "$(leftovers)" -eq 0 ]; then pass; else fail "srt-failure path left run dirs behind: $(ls "$TDIR")"; fi

echo ""
echo "=== act-sandboxed tier (issue #77 PR 3) ==="
echo ""
# These exercise the tier plumbing with the PASSTHROUGH srt stub: the srt jail's
# real write enforcement needs real srt (verified manually against real
# srt+codex — see the PR description). Here the stub lets us prove the launcher
# creates the isolated worktree, points the delegate's cwd at it, emits the work
# product, runs the write-scope tripwire, and cleans everything up.

# make_git_repo <dir> — a throwaway git repo to act as the source tree the
# delegate is confined away from.
make_git_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name "second-opinion test"
  printf 'orig\n' > "$repo/tracked.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init >/dev/null 2>&1
}

# worktree_count <repo> — number of registered worktrees (1 == just the main
# tree, i.e. no dangling act-sandboxed registration left behind).
worktree_count() { git -C "$1" worktree list 2>/dev/null | grep -c . ; }

# A codex stub that (1) writes the required --output-last-message file so
# run_codex succeeds and (2) creates a NEW file in its cwd — which the launcher
# sets to the worktree. Proves the delegate's writes land in the isolated scope.
STUB_CODEX_WT="$WORK/bin-codex-wt"
make_stub "$STUB_CODEX_WT" codex \
  'prev=; out=' \
  'for a in "$@"; do if [ "$prev" = "--output-last-message" ]; then out="$a"; fi; prev="$a"; done' \
  'printf "CODEX ACTED\n" > "$out"' \
  'printf "delegate wrote this\n" > delegate-artifact.txt' \
  'exit 0'

# act-sandboxed default: writes land in the worktree, NOT the source repo.
REPO_WT="$WORK/repo-wt"
make_git_repo "$REPO_WT"
out="$(cd "$REPO_WT" && PATH="$STUB_CODEX_WT:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" --tier act-sandboxed codex "$PROMPT" 2>/dev/null)"
echo "$out" | grep -q "CODEX ACTED" && pass || fail "act-sandboxed should still print the delegate message (got: $out)"
echo "$out" | grep -q "isolated worktree write scope" && pass || fail "act-sandboxed should emit the worktree-changes section (got: $out)"
echo "$out" | grep -q "delegate-artifact.txt" && pass || fail "act-sandboxed should surface the worktree write delegate-artifact.txt (got: $out)"
# The write must NOT have leaked into the source repo tree.
if [ -f "$REPO_WT/delegate-artifact.txt" ]; then fail "act-sandboxed write leaked into the source repo tree"; else pass; fi
if [ -z "$(git -C "$REPO_WT" status --porcelain)" ]; then pass; else fail "source repo tree must stay clean after act-sandboxed run (got: $(git -C "$REPO_WT" status --porcelain))"; fi
# An in-scope write must NOT trip the write-scope tripwire.
if echo "$out" | grep -q "WRITE-SCOPE-TRIPWIRE"; then fail "an in-scope worktree write must NOT trip the tripwire (got: $out)"; else pass; fi

# act-sandboxed wires codex write capability: --sandbox workspace-write, not
# read-only. The stub echoes its argv into the message file (one per line).
STUB_CODEX_WT_ECHO="$WORK/bin-codex-wt-echo"
make_stub "$STUB_CODEX_WT_ECHO" codex \
  'prev=; out=' \
  'for a in "$@"; do if [ "$prev" = "--output-last-message" ]; then out="$a"; fi; prev="$a"; done' \
  'for a in "$@"; do printf "%s\n" "$a"; done > "$out"' \
  'exit 0'
REPO_WT2="$WORK/repo-wt2"
make_git_repo "$REPO_WT2"
out="$(cd "$REPO_WT2" && PATH="$STUB_CODEX_WT_ECHO:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" --tier act-sandboxed codex "$PROMPT" 2>/dev/null)"
echo "$out" | grep -qx -- 'workspace-write' && pass || fail "act-sandboxed codex must use --sandbox workspace-write (got: $out)"
if echo "$out" | grep -qx -- 'read-only'; then fail "act-sandboxed codex must not stay --sandbox read-only (got: $out)"; else pass; fi

# act-sandboxed wires agy write capability: --mode accept-edits plus --sandbox
# (never --dangerously-skip-permissions, ADR-001 Decision 3 forbidden combo).
STUB_AGY_WT_ECHO="$WORK/bin-agy-wt-echo"
make_stub "$STUB_AGY_WT_ECHO" agy 'for a in "$@"; do printf "%s\n" "$a"; done'
REPO_WT3="$WORK/repo-wt3"
make_git_repo "$REPO_WT3"
out="$(cd "$REPO_WT3" && PATH="$STUB_AGY_WT_ECHO:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" --tier act-sandboxed antigravity "$PROMPT" 2>/dev/null)"
echo "$out" | grep -qx -- '--sandbox' && pass || fail "act-sandboxed agy must keep --sandbox (got: $out)"
echo "$out" | grep -qx -- 'accept-edits' && pass || fail "act-sandboxed agy must pass --mode accept-edits (got: $out)"
if echo "$out" | grep -qx -- '--dangerously-skip-permissions'; then fail "act-sandboxed agy must NEVER pass --dangerously-skip-permissions with --sandbox (got: $out)"; else pass; fi

# Out-of-scope write: a delegate that writes OUTSIDE the worktree (into the
# source repo tree) must trip the write-scope tripwire, LOUDLY on both streams.
REPO_TRIP="$WORK/repo-trip"
make_git_repo "$REPO_TRIP"
STUB_CODEX_ESCAPE="$WORK/bin-codex-escape"
make_stub "$STUB_CODEX_ESCAPE" codex \
  'prev=; out=' \
  'for a in "$@"; do if [ "$prev" = "--output-last-message" ]; then out="$a"; fi; prev="$a"; done' \
  'printf "CODEX ESCAPED\n" > "$out"' \
  "printf 'escaped\n' > '$REPO_TRIP/escaped.txt'" \
  'exit 0'
trip_err="$WORK/trip.err"
out="$(cd "$REPO_TRIP" && PATH="$STUB_CODEX_ESCAPE:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" --tier act-sandboxed codex "$PROMPT" 2>"$trip_err")"
echo "$out" | grep -q "WRITE-SCOPE-TRIPWIRE" && pass || fail "an out-of-scope write must trip the tripwire on stdout (got: $out)"
grep -qi "TRIPWIRE TRIPPED" "$trip_err" && pass || fail "the tripwire trip must be surfaced loudly on stderr (got: $(cat "$trip_err"))"

# consult (default) tier: no worktree, no worktree section, repo untouched.
REPO_CONSULT="$WORK/repo-consult"
make_git_repo "$REPO_CONSULT"
out="$(cd "$REPO_CONSULT" && PATH="$STUB_CODEX_OK:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" codex "$PROMPT" 2>/dev/null)"
if echo "$out" | grep -q "isolated worktree write scope"; then fail "consult tier must not emit a worktree section"; else pass; fi
if [ "$(worktree_count "$REPO_CONSULT")" -eq 1 ]; then pass; else fail "consult tier must not create a worktree (got: $(git -C "$REPO_CONSULT" worktree list))"; fi
if [ -z "$(git -C "$REPO_CONSULT" status --porcelain)" ]; then pass; else fail "consult tier must leave the repo untouched"; fi

# act-sandboxed requires a git repo: refused with exit 1 outside one.
NONREPO="$WORK/not-a-repo"
mkdir -p "$NONREPO"
rc=0
(cd "$NONREPO" && PATH="$STUB_CODEX_WT:$STUB_SRT_OK:$REAL_PATH" "$BASH_BIN" "$CONSULT" --tier act-sandboxed codex "$PROMPT") >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then pass; else fail "act-sandboxed outside a git repo must exit 1 (got: $rc)"; fi

# --- act-sandboxed cleanup: worktree + run dir removed on ALL exit paths ---
# No second-opinion residue in TMPDIR, and no dangling worktree registration in
# the source repo, on the happy, provider-failure, and srt-failure paths.
# happy path
REPO_CLEAN="$WORK/repo-clean"
make_git_repo "$REPO_CLEAN"
(cd "$REPO_CLEAN" && PATH="$STUB_CODEX_WT:$STUB_SRT_OK:$REAL_PATH" TMPDIR="$TDIR" "$BASH_BIN" "$CONSULT" --tier act-sandboxed codex "$PROMPT") >/dev/null 2>&1
if [ "$(leftovers)" -eq 0 ]; then pass; else fail "act-sandboxed happy path left run/worktree dirs behind: $(ls "$TDIR")"; fi
if [ "$(worktree_count "$REPO_CLEAN")" -eq 1 ]; then pass; else fail "act-sandboxed happy path left a dangling worktree registration: $(git -C "$REPO_CLEAN" worktree list)"; fi
# provider-failure path (exit 3)
REPO_FAIL="$WORK/repo-fail"
make_git_repo "$REPO_FAIL"
(cd "$REPO_FAIL" && PATH="$STUB_CODEX_FAIL:$STUB_SRT_OK:$REAL_PATH" TMPDIR="$TDIR" "$BASH_BIN" "$CONSULT" --tier act-sandboxed codex "$PROMPT") >/dev/null 2>&1
if [ "$(leftovers)" -eq 0 ]; then pass; else fail "act-sandboxed provider-failure path left dirs behind: $(ls "$TDIR")"; fi
if [ "$(worktree_count "$REPO_FAIL")" -eq 1 ]; then pass; else fail "act-sandboxed provider-failure left a dangling worktree registration"; fi
# srt-failure path (exit 3, preflight) — the worktree is created before srt runs.
REPO_SRTFAIL="$WORK/repo-srtfail"
make_git_repo "$REPO_SRTFAIL"
(cd "$REPO_SRTFAIL" && PATH="$STUB_CODEX_OK0:$STUB_SRT_FAIL:$REAL_PATH" TMPDIR="$TDIR" "$BASH_BIN" "$CONSULT" --tier act-sandboxed codex "$PROMPT") >/dev/null 2>&1
if [ "$(leftovers)" -eq 0 ]; then pass; else fail "act-sandboxed srt-failure path left dirs behind: $(ls "$TDIR")"; fi
if [ "$(worktree_count "$REPO_SRTFAIL")" -eq 1 ]; then pass; else fail "act-sandboxed srt-failure left a dangling worktree registration"; fi

echo ""
echo "Results: $PASS passed, $FAIL failed ($(( PASS + FAIL )) total)"

if [ "$FAIL" -gt 0 ]; then
  echo "FAILED"
  exit 1
fi

echo "PASSED"
