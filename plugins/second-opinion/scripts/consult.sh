#!/usr/bin/env bash
set -euo pipefail

# consult.sh — privilege-tiered, sandboxed delegation to external AI CLIs.
#
# Usage:
#   consult.sh list                                  # print available providers, one per line
#   consult.sh [--tier <tier>] <provider> <prompt-file>
#                                                    # run delegation, print result text to stdout
#
# Providers:
#   codex        OpenAI Codex CLI (binary: codex)
#   antigravity  Google Antigravity CLI (binary: agy)
#
# Tiers (ADR-001, docs/adr/001-task-delegation-privilege-model.md):
#   consult        (default) Read-only review — the only tier wired today.
#   act-sandboxed  NOT YET IMPLEMENTED (issue #77 PR 3). Refused with exit 1.
#   act-full       NOT YET IMPLEMENTED (issue #77 PR 4). Refused with exit 1;
#                  will additionally require explicit per-invocation approval.
#   Escalation is never silent: an unimplemented tier is refused, never
#   downgraded to consult (ADR-001 Decision 4).
#
# Sandbox (ADR-001 Decisions 5-6, fail-closed):
#   Every delegate subprocess runs inside the pinned Anthropic sandbox-runtime
#   wrapper (`srt`, npm @anthropic-ai/sandbox-runtime@0.0.66) — OS-level
#   filesystem jail + default-deny egress through a localhost allowlisting
#   proxy. srt and its platform deps (Seatbelt's sandbox-exec on macOS,
#   bubblewrap + socat on Linux) are HARD prerequisites: if missing, the
#   delegation is refused with exit 2; if the wrapper fails to start, exit 3.
#   There is no silent degradation to the provider CLIs' own sandbox flags —
#   those stay on underneath as defense-in-depth only.
#
#   Note: `srt --version` reports the CLI's internal version (1.0.0 for the
#   0.0.66 npm release), so the pin cannot be verified at runtime; it is
#   enforced at install time via the exact-version install command below.
#
# Egress allowlists (ADR-001 Decision 7):
#   Shipped per-provider files (provider API endpoints only) live in
#   ../assets/allowlists/<provider>.txt. Users extend them via
#   $SECOND_OPINION_ALLOWLIST_DIR (default:
#   ${XDG_CONFIG_HOME:-~/.config}/second-opinion/allowlist.d)/<provider>.txt —
#   never by editing the shipped files. Any extension is surfaced loudly on
#   stderr at invocation time.
#
# Least-privilege pass-down (ADR-001):
#   The delegate runs with a scrubbed environment (env -i): only HOME, PATH,
#   TMPDIR, TERM, and the one provider credential var (codex: OPENAI_API_KEY;
#   antigravity: ANTIGRAVITY_API_KEY) pass through. Ambient secrets
#   (AWS_*, GITHUB_TOKEN, ...) never reach the delegate.
#
# Sandbox limits (honest): the jail restricts writes and egress, and denies
# reads of known credential paths — it does not stop the model from reading
# other in-jail files and transmitting them to its provider. See the ADR risk
# register.
#
# Model overrides (optional):
#   SECOND_OPINION_CODEX_MODEL        e.g. "gpt-5-codex"
#   SECOND_OPINION_ANTIGRAVITY_MODEL  e.g. "Gemini 3.1 Pro"
#
# Exit codes: 0 success, 1 usage error or refused tier,
#             2 required component not installed (provider CLI, srt, or srt
#               platform deps), 3 component failed (provider run or wrapper
#               failed to start).

PROVIDERS=(codex antigravity)

SRT_PIN="0.0.66"
SRT_PKG="@anthropic-ai/sandbox-runtime"
SRT_INSTALL="npm install -g ${SRT_PKG}@${SRT_PIN}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOWLIST_DIR="$SCRIPT_DIR/../assets/allowlists"

# Globals set in main before any provider runs.
TIER="consult"
RUN_TMP=""
SRT_BIN=""
SRT_SETTINGS=""
CRED_VAR=""

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

# --- srt fail-closed checks (ADR-001 Decisions 5-6) -------------------------

require_srt() {
  if ! SRT_BIN=$(command -v srt); then
    log "the pinned sandbox-runtime wrapper 'srt' is required for tier '$TIER' and was not found in PATH."
    log "delegation is refused without it (fail-closed, ADR-001 Decision 6) — install the pinned version: $SRT_INSTALL"
    exit 2
  fi
  case "$(uname -s)" in
    Darwin)
      if ! command -v sandbox-exec >/dev/null 2>&1; then
        log "srt platform dependency missing: sandbox-exec (macOS Seatbelt) not found — the OS sandbox jail cannot be enforced."
        log "delegation is refused (fail-closed, ADR-001 Decision 6)."
        exit 2
      fi
      ;;
    Linux)
      local dep
      for dep in bwrap socat; do
        if ! command -v "$dep" >/dev/null 2>&1; then
          log "srt platform dependency missing: $dep — install bubblewrap and socat (e.g. apt-get install bubblewrap socat)."
          log "delegation is refused (fail-closed, ADR-001 Decision 6)."
          exit 2
        fi
      done
      ;;
  esac
}

srt_preflight() {
  # Verify the wrapper actually starts before handing it the real delegation,
  # so a broken srt surfaces as its own actionable error (exit 3) instead of
  # being folded into a generic provider failure.
  local rc=0
  run_srt true >/dev/null 2>"$RUN_TMP/srt-preflight.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    log "srt wrapper failed to start (exit $rc): $(tail -3 "$RUN_TMP/srt-preflight.err" 2>/dev/null | tr '\n' ' ')"
    log "delegation is refused without a working sandbox (fail-closed, ADR-001 Decision 6). Reproduce with: srt --debug --settings <settings.json> -- true"
    exit 3
  fi
}

# --- egress allowlists (ADR-001 Decision 7) ---------------------------------

# parse_allowlist <file> — print one validated domain per line. Comments (#)
# and blank lines are stripped; entries with characters outside [A-Za-z0-9.*-]
# are rejected (also prevents JSON injection via user-owned config).
parse_allowlist() {
  local file="$1" line d
  while IFS= read -r line || [ -n "$line" ]; do
    d="${line%%#*}"
    d="$(printf '%s' "$d" | tr -d '[:space:]')"
    [ -n "$d" ] || continue
    if printf '%s' "$d" | grep -Eq '^[A-Za-z0-9.*-]+$'; then
      echo "$d"
    else
      log "warning: ignoring invalid domain entry '$d' in $file"
    fi
  done < "$file"
}

# write_srt_settings <provider> — generate the per-run srt settings JSON:
# shipped + user-extended egress allowlist, credential-path denyRead policy,
# and a write scope confined to the run dir + the provider's own state dirs.
write_srt_settings() {
  local provider="$1"
  SRT_SETTINGS="$RUN_TMP/srt-settings.json"

  local shipped="$ALLOWLIST_DIR/$provider.txt"
  if [ ! -f "$shipped" ]; then
    log "shipped egress allowlist missing: $shipped (broken plugin install — reinstall the second-opinion plugin)"
    exit 2
  fi
  local domains
  domains=$(parse_allowlist "$shipped")
  if [ -z "$domains" ]; then
    log "shipped egress allowlist $shipped contains no valid domains (broken plugin install)"
    exit 2
  fi

  # User extension (user-owned config, never the shipped file). Surfaced
  # loudly so a widened egress surface is never invisible.
  local ext_file ext_domains
  ext_file="${SECOND_OPINION_ALLOWLIST_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/second-opinion/allowlist.d}/$provider.txt"
  if [ -f "$ext_file" ]; then
    ext_domains=$(parse_allowlist "$ext_file")
    if [ -n "$ext_domains" ]; then
      log "NOTICE: egress allowlist for $provider extended beyond shipped defaults (from $ext_file): $(printf '%s' "$ext_domains" | tr '\n' ' ')"
      domains=$(printf '%s\n%s\n' "$domains" "$ext_domains")
    fi
  fi

  local domains_json="" d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    domains_json="${domains_json}\"${d}\", "
  done <<EOF
$domains
EOF
  domains_json="${domains_json%, }"

  # Write scope: tighter than the ADR's "read-only outside temp" floor — only
  # the run dir and the provider's own state dirs (session logs, caches) are
  # writable. Verified sufficient against the real CLIs under srt 0.0.66.
  # (Paths are physical: srt's jail does not follow symlinks like macOS /tmp.)
  local write_json="\"$RUN_TMP\""
  case "$provider" in
    codex)
      if [ -d "$HOME/.codex" ]; then write_json="$write_json, \"$HOME/.codex\""; fi
      ;;
    antigravity)
      if [ -d "$HOME/.gemini" ]; then write_json="$write_json, \"$HOME/.gemini\""; fi
      if [ -d "$HOME/.cache/antigravity" ]; then write_json="$write_json, \"$HOME/.cache/antigravity\""; fi
      ;;
  esac

  # Provider quirks (verified against real CLIs under srt 0.0.66 on macOS):
  # - agy spawns an internal language server that binds a loopback port, so
  #   it needs allowLocalBinding.
  # - agy is a Go binary: on macOS, Go TLS certificate verification goes
  #   through the trustd mach service, which the Seatbelt profile blocks by
  #   default. enableWeakerNetworkIsolation re-allows com.apple.trustd.agent.
  #   Without it every HTTPS call fails and agy reports "not logged in".
  #   Security trade-off documented in the plugin README (ADR risk register).
  # - agy stores its OAuth token in the macOS login keychain, which the
  #   denyRead policy below blocks. Per ADR-001 Decision 5, a narrow
  #   allowRead carve-out re-permits exactly that file, and the carve-out is
  #   surfaced loudly at invocation time (same mechanism as allowlist
  #   extensions).
  local local_binding="false" weaker="false" allowread_json=""
  if [ "$provider" = "antigravity" ]; then
    local_binding="true"
    weaker="true"
    allowread_json="\"~/Library/Keychains/login.keychain-db\""
    log "NOTICE: allowRead carve-out into a denied credential path for $provider: ~/Library/Keychains/login.keychain-db (the agy CLI reads its stored OAuth token from the macOS login keychain; ADR-001 Decision 5)"
  fi

  # denyRead: known credential/secret paths (ADR-001 Decision 5 minimum set:
  # ssh, cloud creds, gh, shell history, OS keychain stores) plus gnupg.
  cat > "$SRT_SETTINGS" <<EOF
{
  "network": {
    "allowedDomains": [$domains_json],
    "deniedDomains": [],
    "allowLocalBinding": $local_binding
  },
  "filesystem": {
    "denyRead": [
      "~/.ssh", "~/.aws", "~/.config/gh", "~/.gnupg",
      "~/.bash_history", "~/.zsh_history", "~/.history",
      "~/Library/Keychains", "~/.local/share/keyrings"
    ],
    "allowRead": [$allowread_json],
    "allowWrite": [$write_json],
    "denyWrite": []
  },
  "enableWeakerNetworkIsolation": $weaker
}
EOF
}

# --- sandboxed, environment-scrubbed subprocess launch ----------------------

# run_srt <cmd...> — run a command inside the srt jail with a scrubbed
# environment. Upstream srt inherits the launcher's ambient environment on
# macOS/Linux, so scrubbing is this launcher's job (ADR-001 least-privilege
# pass-down): only HOME/PATH/TMPDIR/TERM plus the single provider credential
# var pass through.
run_srt() {
  local cred_val=""
  if [ -n "$CRED_VAR" ]; then
    cred_val="${!CRED_VAR:-}"
  fi
  if [ -n "$cred_val" ]; then
    env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" TERM="${TERM:-dumb}" \
      "$CRED_VAR=$cred_val" \
      "$SRT_BIN" --settings "$SRT_SETTINGS" -- "$@"
  else
    env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" TERM="${TERM:-dumb}" \
      "$SRT_BIN" --settings "$SRT_SETTINGS" -- "$@"
  fi
}

# --- providers --------------------------------------------------------------

run_codex() {
  local prompt_file="$1"
  local out="$RUN_TMP/codex-last-message" rc=0
  # The run dir (and this file with it) is removed by the top-level EXIT trap
  # on every exit path, so no per-path cleanup is needed here.

  # codex exec: non-interactive mode. Final agent message goes to the
  # --output-last-message file; progress noise stays on stdout/stderr. The
  # native --sandbox read-only flag stays on as defense-in-depth under the
  # srt jail (ADR-001 Decision 3 note).
  run_srt codex exec \
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
  return "$rc"
}

run_antigravity() {
  local prompt_file="$1"
  local response

  # agy --sandbox: run in a sandbox with terminal restrictions enabled (per
  # `agy --help` on 1.1.4). This native flag stays on as defense-in-depth
  # under the srt jail. `-p`/--print only makes the run non-interactive (one
  # prompt, print, exit); it provides NO isolation by itself.
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

  response=$(run_srt agy --sandbox -p "$(cat "$prompt_file")" \
    ${SECOND_OPINION_ANTIGRAVITY_MODEL:+-m "$SECOND_OPINION_ANTIGRAVITY_MODEL"} \
    < /dev/null) || return 3

  [ -n "$response" ] || { log "antigravity produced an empty response"; return 3; }
  printf '%s\n' "$response"
}

# --- main -------------------------------------------------------------------

usage() {
  log "usage: consult.sh list | consult.sh [--tier <consult|act-sandboxed|act-full>] <provider> <prompt-file>"
  exit 1
}

main() {
  [ $# -ge 1 ] || usage

  if [ "$1" = "list" ]; then
    if ! command -v srt >/dev/null 2>&1; then
      log "warning: the pinned sandbox wrapper 'srt' is not installed; delegation will be refused (exit 2) until it is. Install: $SRT_INSTALL"
    fi
    available
    exit 0
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --tier)
        [ $# -ge 2 ] || { log "--tier requires a value (consult | act-sandboxed | act-full)"; exit 1; }
        TIER="$2"; shift 2 ;;
      --tier=*)
        TIER="${1#--tier=}"; shift ;;
      -*)
        log "unknown option: $1"; usage ;;
      *)
        break ;;
    esac
  done

  local provider="${1:-}" prompt_file="${2:-}"
  [ -n "$provider" ] || usage
  case "$provider" in
    codex|antigravity) ;;
    *) log "unknown provider: $provider (supported: ${PROVIDERS[*]})"; exit 1 ;;
  esac
  [ -n "$prompt_file" ] || usage
  [ -f "$prompt_file" ] || { log "prompt file not found: $prompt_file"; exit 1; }

  # Tier gate (ADR-001 Decision 4): only consult is wired; higher tiers are
  # refused — never silently downgraded to consult, never silently granted.
  case "$TIER" in
    consult) ;;
    act-sandboxed)
      log "tier 'act-sandboxed' is not yet implemented (planned: issue #77 PR 3)."
      log "refusing to run rather than silently downgrading (ADR-001 Decision 4). Re-run with --tier consult (or no --tier) for the read-only tier."
      exit 1 ;;
    act-full)
      log "tier 'act-full' is gated behind an explicit per-invocation approval mechanism that is not yet implemented (planned: issue #77 PR 4)."
      log "refusing to run — no silent escalation (ADR-001 Decision 4). Re-run with --tier consult (or no --tier) for the read-only tier."
      exit 1 ;;
    *)
      log "unknown tier: $TIER (supported: consult | act-sandboxed | act-full)"
      exit 1 ;;
  esac

  require_srt

  local bin
  bin=$(binary_for "$provider")
  command -v "$bin" >/dev/null 2>&1 || {
    log "$provider CLI ($bin) not found in PATH"
    exit 2
  }

  case "$provider" in
    codex) CRED_VAR="OPENAI_API_KEY" ;;
    antigravity) CRED_VAR="ANTIGRAVITY_API_KEY" ;;
  esac

  # Per-run temp dir: holds the generated srt settings and provider scratch
  # output. Removed on EVERY exit path via the EXIT trap (mandatory-cleanup
  # rule). Resolved to a physical path because srt's jail does not follow
  # symlinked temp paths (macOS /tmp -> /private/tmp).
  RUN_TMP=$(mktemp -d -t second-opinion-run.XXXXXX)
  trap 'rm -rf "$RUN_TMP"' EXIT
  RUN_TMP=$(cd "$RUN_TMP" && pwd -P)

  write_srt_settings "$provider"
  srt_preflight

  "run_$provider" "$prompt_file"
}

main "$@"
