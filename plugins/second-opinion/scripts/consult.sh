#!/usr/bin/env bash
set -euo pipefail

# consult.sh — privilege-tiered, sandboxed delegation to external AI CLIs.
#
# Usage:
#   consult.sh list                                  # print available providers, one per line
#   consult.sh [--tier <tier>] [--i-approve-full-access] [--primary-tree] \
#              <provider> <prompt-file>
#                                                    # run delegation, print result text to stdout
#
# Gate flags:
#   --i-approve-full-access  Second, distinct per-invocation approval REQUIRED to
#                            grant --tier act-full (ADR-001 Decision 4). Without
#                            it, act-full is refused (exit 1). Persists nothing.
#   --primary-tree           act-full only: run in the primary working tree
#                            instead of the default isolated worktree, forfeiting
#                            write-scope tripwire attribution (ADR-001 Decision 8).
#
# Providers:
#   codex        OpenAI Codex CLI (binary: codex)
#   antigravity  Google Antigravity CLI (binary: agy)
#
# Tiers (ADR-001, docs/adr/001-task-delegation-privilege-model.md):
#   consult        (default) Read-only review. No writes; unchanged from PR 2.
#   act-sandboxed  (opt-in) Read-write, but WRITES ARE CONFINED to an isolated
#                  scope: a dedicated detached git worktree of the current repo,
#                  created under the run temp dir. The srt jail's write-allowlist
#                  is the enforcement (worktree + run dir writable, everything
#                  else — including the primary repo tree, $HOME, credential
#                  paths — denied). A post-hoc write-scope tripwire re-checks
#                  everywhere the delegate is NOT allowed to write — the primary
#                  tree, any sibling worktrees of the repo, and the shared git
#                  dir's hooks/config — and surfaces any out-of-scope write
#                  LOUDLY. Its before/after snapshots live in a separate,
#                  delegate-unwritable temp dir so they cannot be tampered with.
#                  The worktree diff (the work product) is printed after the delegate
#                  output; the worktree is destroyed on exit like the run dir.
#                  Requires being inside a git repository (exit 1 otherwise).
#   act-full       (gated) Unrestricted write / terminal / network. Requires TWO
#                  independent affirmative signals on the SAME invocation: the
#                  tier AND --i-approve-full-access (ADR-001 Decision 4).
#                  Requesting act-full without the approval flag is REFUSED with
#                  exit 1 and an actionable error — never silently downgraded to
#                  consult, never silently granted. When granted, the srt wrapper
#                  is OFF (unsandboxed: codex --sandbox danger-full-access, agy
#                  UNSANDBOXED, never the forbidden --sandbox
#                  --dangerously-skip-permissions combo). Writes default into a
#                  dedicated worktree (Decision 8); --primary-tree opts out into
#                  the primary tree, forfeiting tripwire attribution (surfaced
#                  loudly). The widened posture is surfaced loudly on stderr at
#                  invocation and in the result on stdout.
#   Escalation is never silent: an ungranted higher tier is refused, never
#   downgraded to consult (ADR-001 Decision 4).
#
# Sandbox (ADR-001 Decisions 5-6, fail-closed):
#   At consult and act-sandboxed, every delegate subprocess runs inside the
#   pinned Anthropic sandbox-runtime wrapper (`srt`, npm
#   @anthropic-ai/sandbox-runtime@0.0.66) — OS-level filesystem jail +
#   default-deny egress through a localhost allowlisting proxy. srt and its
#   platform deps (Seatbelt's sandbox-exec on macOS, bubblewrap + socat on Linux)
#   are HARD prerequisites AT THOSE TIERS: if missing, the delegation is refused
#   with exit 2; if the wrapper fails to start, exit 3. There is no silent
#   degradation to the provider CLIs' own sandbox flags — those stay on
#   underneath as defense-in-depth only. At act-full the wrapper is intentionally
#   OFF (the explicit outcome of the Decision 4 gate, not a fail-closed
#   violation), so the srt checks are skipped and an approved act-full run is NOT
#   blocked by srt's absence.
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
# act-full gate (ADR-001 Decision 4): act-full needs TWO independent affirmative
# signals on the SAME invocation — the tier AND --i-approve-full-access. Neither
# persists; both are per-invocation only. A THIRD flag, --primary-tree, is the
# distinct opt-out that leaves the default isolated worktree for the primary tree
# (ADR-001 Decision 8), forfeiting tripwire attribution.
APPROVE_FULL=0
PRIMARY_TREE_OPTOUT=0
# act-full runs with the srt wrapper intentionally OFF (ADR-001 Decision 3/6):
# unrestricted write/terminal/network. run_srt honours this by launching the
# delegate directly (still env-scrubbed) instead of through srt.
WRAPPER_OFF=0
RUN_TMP=""
SRT_BIN=""
SRT_SETTINGS=""
CRED_VAR=""
# Acting tiers only: the isolated write scope (a detached git worktree) and the
# repo it was cut from. Empty at consult, and at act-full when --primary-tree is
# chosen. SANDBOX_CWD is the cwd the delegate subprocess runs in (the worktree at
# act-sandboxed, and at act-full by default).
SRC_REPO=""
WORKTREE=""
SANDBOX_CWD=""
# Acting tiers only: a tamper-resistant store for the write-scope tripwire's
# before/after snapshots. Its own mktemp dir — deliberately NOT under RUN_TMP and
# NOT in the srt write-allowlist — so the jailed delegate cannot overwrite the
# before-snapshots to erase evidence of an out-of-scope write. Empty at consult,
# and at act-full when --primary-tree is chosen.
TRIPWIRE_TMP=""

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
    *)
      log "unsupported platform for the srt sandbox: $(uname -s) (supported: macOS, Linux)."
      log "delegation is refused (fail-closed, ADR-001 Decision 6)."
      exit 2
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
  # Guard the assignment: parse_allowlist's `done < "$file"` fails (non-zero)
  # if the shipped file exists but is unreadable, which would otherwise abort
  # under `set -e` with a raw bash redirection error instead of this actionable
  # broken-install message.
  if ! domains=$(parse_allowlist "$shipped"); then
    log "shipped egress allowlist $shipped could not be read (broken plugin install — reinstall the second-opinion plugin)"
    exit 2
  fi
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
  #
  # act-sandboxed adds the dedicated worktree as an allowed write scope
  # (ADR-001 Decision 3: "write-allowlist = the worktree + run temp dir only").
  # The worktree lives under RUN_TMP so RUN_TMP already covers it, but it is
  # listed explicitly so the allowed scope is unambiguous in the settings.
  #
  # Deliberately NOT writable: the repo's shared git dir (its object/ref store,
  # index, config, hooks). A linked worktree keeps its index/HEAD and new
  # objects partly under that shared common-dir, so an act-sandboxed delegate
  # CANNOT run `git add`/`git commit` or other index-writing ops inside the
  # worktree — the jail denies those writes. This is intentional: the delegate
  # produces WORKING-TREE edits only; the orchestrator reviews the worktree diff
  # (printed after the run) and integrates it, exactly as it would an external
  # PR. Keeping the shared git dir unwritable is also what makes the .git
  # hooks/config plant (a code-exec vector) impossible in the first place.
  local write_json="\"$RUN_TMP\""
  if [ -n "$WORKTREE" ]; then write_json="$write_json, \"$WORKTREE\""; fi

  # Tripwire state store (act-sandboxed): kept OUT of allowWrite above (it is its
  # own mktemp dir, not under RUN_TMP) AND explicitly denied here — belt and
  # suspenders — so a delegate cannot tamper with the before-snapshots to erase
  # evidence of an out-of-scope write. Tampering would then require a jail escape
  # to an arbitrary path, i.e. at least the privilege the tripwire exists to catch.
  local deny_write_json=""
  if [ -n "$TRIPWIRE_TMP" ]; then deny_write_json="\"$TRIPWIRE_TMP\""; fi
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
    "denyWrite": [$deny_write_json]
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
#
# When SANDBOX_CWD is set (act-sandboxed, and act-full by default), the delegate
# runs with its working directory inside the isolated worktree, so provider
# "workspace"/cwd-relative writes land there. The cd happens in a subshell so it
# never leaks into the launcher. srt reads are default-allow, so it starts fine
# from the worktree.
#
# When WRAPPER_OFF is set (act-full — ADR-001 Decision 3/6), the srt jail is
# intentionally absent and the delegate is launched DIRECTLY. Environment
# scrubbing (least-privilege pass-down) still applies at every tier: only
# HOME/PATH/TMPDIR/TERM plus the one provider credential pass through, so ambient
# secrets never reach the delegate even when the jail is off. What act-full drops
# is the filesystem/egress jail, not the env hygiene.
run_srt() {
  local cred_val=""
  if [ -n "$CRED_VAR" ]; then
    cred_val="${!CRED_VAR:-}"
  fi
  (
    if [ -n "$SANDBOX_CWD" ]; then
      cd "$SANDBOX_CWD" || exit 3
    fi
    if [ "$WRAPPER_OFF" = "1" ]; then
      if [ -n "$cred_val" ]; then
        env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" TERM="${TERM:-dumb}" \
          "$CRED_VAR=$cred_val" \
          "$@"
      else
        env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" TERM="${TERM:-dumb}" \
          "$@"
      fi
    elif [ -n "$cred_val" ]; then
      env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" TERM="${TERM:-dumb}" \
        "$CRED_VAR=$cred_val" \
        "$SRT_BIN" --settings "$SRT_SETTINGS" -- "$@"
    else
      env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" TERM="${TERM:-dumb}" \
        "$SRT_BIN" --settings "$SRT_SETTINGS" -- "$@"
    fi
  )
}

# --- providers --------------------------------------------------------------

run_codex() {
  local prompt_file="$1"
  local out="$RUN_TMP/codex-last-message" rc=0
  # The run dir (and this file with it) is removed by the top-level EXIT trap
  # on every exit path, so no per-path cleanup is needed here.

  # codex exec: non-interactive mode. Final agent message goes to the
  # --output-last-message file; progress noise stays on stdout/stderr.
  #
  # Native --sandbox mode tracks the tier (ADR-001 Decision 3): read-only at
  # consult, workspace-write at act-sandboxed, danger-full-access at act-full.
  # At consult/act-sandboxed it stays on as defense-in-depth under the srt jail;
  # at act-full the srt jail is off (WRAPPER_OFF) and danger-full-access is the
  # intended unrestricted posture. At act-sandboxed and (by default) act-full the
  # delegate's cwd is the worktree (run_srt cds there via SANDBOX_CWD), so codex's
  # writable "workspace" is that scope; the srt write-allowlist is the
  # load-bearing enforcement at act-sandboxed.
  local codex_sandbox="read-only"
  if [ "$TIER" = "act-sandboxed" ]; then codex_sandbox="workspace-write"; fi
  if [ "$TIER" = "act-full" ]; then codex_sandbox="danger-full-access"; fi
  run_srt codex exec \
    --sandbox "$codex_sandbox" \
    --skip-git-repo-check \
    ${SECOND_OPINION_CODEX_MODEL:+-m "$SECOND_OPINION_CODEX_MODEL"} \
    --output-last-message "$out" \
    - < "$prompt_file" >&2 || rc=3

  if [ "$rc" -eq 0 ] && [ ! -s "$out" ]; then
    log "codex produced no output"
    rc=3
  fi

  # Guard the cat explicitly: run_codex is called via `|| prc=$?`, so errexit is
  # suppressed for the whole body — a cat failure after the -s check passed
  # would otherwise leave rc=0 and report success with no output on stdout.
  if [ "$rc" -eq 0 ]; then cat "$out" || rc=3; fi
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

  # Sandbox/edit posture by tier (ADR-001 Decision 3). agy has NO native
  # write-scoped mode (only the binary --sandbox terminal-restriction toggle):
  #   consult        --sandbox, no edit mode           (read-only)
  #   act-sandboxed  --sandbox --mode accept-edits      (srt write-allowlist is
  #                  the sole write-scope enforcement; --sandbox stays on for its
  #                  terminal restrictions, accept-edits applies edits
  #                  non-interactively — without it, print mode blocks on an
  #                  edit-approval prompt with stdin at /dev/null)
  #   act-full       UNSANDBOXED (--sandbox DROPPED) --mode accept-edits (the srt
  #                  jail is off, WRAPPER_OFF; ADR-001 Decision 3 says agy is
  #                  unsandboxed at act-full)
  #
  # FORBIDDEN COMBO (ADR-001 Decision 3 / risk #6): agy --sandbox
  # --dangerously-skip-permissions auto-approves the sandbox-bypass prompt. It is
  # STRUCTURALLY IMPOSSIBLE to emit here: --dangerously-skip-permissions is never
  # a token this script produces at ANY tier, and --sandbox is present only at
  # consult/act-sandboxed (never combined with any skip-permissions flag) and
  # absent entirely at act-full. accept-edits is the standard edit-acceptance
  # mode, NOT that sandbox-bypass auto-approve. The delegate's cwd is the worktree
  # (SANDBOX_CWD) at act-sandboxed and by default at act-full.
  local agy_sandbox="--sandbox" agy_mode=""
  if [ "$TIER" = "act-sandboxed" ]; then agy_mode="--mode accept-edits"; fi
  if [ "$TIER" = "act-full" ]; then agy_sandbox=""; agy_mode="--mode accept-edits"; fi
  response=$(run_srt agy $agy_sandbox $agy_mode -p "$(cat "$prompt_file")" \
    ${SECOND_OPINION_ANTIGRAVITY_MODEL:+-m "$SECOND_OPINION_ANTIGRAVITY_MODEL"} \
    < /dev/null) || return 3

  [ -n "$response" ] || { log "antigravity produced an empty response"; return 3; }
  printf '%s\n' "$response"
}

# --- act-sandboxed: isolated write scope + write-scope tripwire -------------

# cleanup — remove the run temp dir AND (act-sandboxed) the dedicated worktree
# and the tripwire state dir on EVERY exit path (mandatory-cleanup rule; ADR-001
# least-privilege scope).
# Registered as the EXIT trap, so it fires on success, refusal, error, or
# signal. The worktree is torn down via `git worktree remove` (which also drops
# the .git/worktrees admin entry); rm is the fallback if git is unavailable.
#
# This trap runs while `set -e` is still in effect, and traps are NOT exempt
# from errexit the way `||`-guarded call sites are. So cleanup must be unable to
# abort partway: it captures the real exit status first, turns errexit OFF, and
# guards EVERY command so a failed worktree/rm removal can neither skip the
# mandatory `rm -rf "$RUN_TMP"` nor corrupt the script's exit code. A removal
# that genuinely fails is logged with the leaked path so it is discoverable.
cleanup() {
  local rc=$?
  set +e
  if [ -n "$WORKTREE" ] && [ -n "$SRC_REPO" ] && [ -e "$WORKTREE" ]; then
    if ! git -C "$SRC_REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1; then
      rm -rf "$WORKTREE" 2>/dev/null \
        || log "cleanup: failed to remove the worktree; it is leaked on disk at $WORKTREE"
    fi
    git -C "$SRC_REPO" worktree prune >/dev/null 2>&1 || true
  fi
  if [ -n "$RUN_TMP" ]; then
    rm -rf "$RUN_TMP" 2>/dev/null \
      || log "cleanup: failed to remove the run dir; it is leaked on disk at $RUN_TMP"
  fi
  if [ -n "$TRIPWIRE_TMP" ]; then
    rm -rf "$TRIPWIRE_TMP" 2>/dev/null \
      || log "cleanup: failed to remove the tripwire state dir; it is leaked on disk at $TRIPWIRE_TMP"
  fi
  # Preserve the real exit status: a cleanup failure must never mask it.
  exit "$rc"
}

# setup_worktree — create the isolated write scope: a detached git worktree of
# the current repo's HEAD, under the run temp dir (so one cleanup covers both).
#
# This bounds the WRITABLE surface only, via the srt write-allowlist (Decision
# 3). It is NOT a read barrier: per ADR-001's Exposure Model the worktree is "a
# scoping convention, not a read barrier" — srt reads are default-allow and
# $SRC_REPO is not in denyRead, so the delegate can still read the primary tree
# (the worktree's linked .git metadata even reveals its absolute path), and
# those reads reach the provider at every tier (risk #7). Only the credential
# paths in denyRead are blocked.
#
# `--detach HEAD` checks out the committed HEAD only: uncommitted staged/unstaged
# changes in the primary tree are NOT part of what the delegate sees or acts on.
# Requires being inside a git repository — refused with exit 1 otherwise.
setup_worktree() {
  if ! SRC_REPO=$(git rev-parse --show-toplevel 2>/dev/null) || [ -z "$SRC_REPO" ]; then
    SRC_REPO=""
    log "tier '$TIER' defaults to a dedicated git worktree as its write scope, but no git repository was found at $PWD."
    if [ "$TIER" = "act-full" ]; then
      log "to run act-full in the current directory instead, re-run with --primary-tree — this forfeits write-scope tripwire attribution (ADR-001 Decision 8)."
    fi
    exit 1
  fi
  SRC_REPO=$(cd "$SRC_REPO" && pwd -P)
  WORKTREE="$RUN_TMP/worktree"
  if ! git -C "$SRC_REPO" worktree add --detach "$WORKTREE" HEAD >"$RUN_TMP/worktree-add.log" 2>&1; then
    log "failed to create the act-sandboxed worktree: $(tail -3 "$RUN_TMP/worktree-add.log" 2>/dev/null | tr '\n' ' ')"
    WORKTREE=""
    exit 3
  fi
  # Resolve to a physical path via a temp var so a failed resolution cannot
  # blank out WORKTREE: cleanup() must still see the registered path (the
  # unresolved but valid "$RUN_TMP/worktree") to drop the .git/worktrees admin
  # entry, or a stale registration would leak into the user's primary repo.
  local wt_phys
  if wt_phys=$(cd "$WORKTREE" && pwd -P) && [ -n "$wt_phys" ]; then
    WORKTREE="$wt_phys"
  else
    log "failed to resolve the act-sandboxed worktree to a physical path: $WORKTREE"
    exit 3
  fi
  SANDBOX_CWD="$WORKTREE"
}

# setup_tripwire_state — allocate the store for the write-scope tripwire's
# before/after snapshots. It lives in its OWN mktemp dir, NOT under $RUN_TMP and
# deliberately NOT in the srt write-allowlist (and additionally listed in
# denyWrite when the wrapper is on).
#
# Tamper-resistance is TIER-DEPENDENT — do not overstate it:
#   act-sandboxed — TAMPER-RESISTANT. The srt jail is ON: the delegate's writable
#     scope is the worktree under $RUN_TMP and this store is denied, so
#     overwriting the before-snapshots to erase evidence would require a jail
#     escape to an arbitrary path — i.e. at least the privilege the tripwire
#     exists to catch.
#   act-full — BEST-EFFORT DETECTION ONLY. WRAPPER_OFF=1 means write_srt_settings
#     is skipped, so no srt jail / denyWrite is ever generated and the delegate
#     runs unsandboxed with unrestricted write access (ADR-001 Decision 3). It
#     can trivially discover this store (an mktemp dir under $TMPDIR, readable
#     and listable) and overwrite the snapshots — NO jail escape needed, it
#     already holds the arbitrary-write privilege the guarantee above assumed
#     absent. Genuine tamper-resistance is impossible at act-full (same-user, no
#     jail); the tripwire is a courtesy signal, not tamper-proof, and this is
#     surfaced loudly in the act-full banner (announce_act_full/report_act_full).
# Torn down by cleanup() on every exit path.
setup_tripwire_state() {
  TRIPWIRE_TMP=$(mktemp -d -t second-opinion-tripwire.XXXXXX)
  local phys
  if phys=$(cd "$TRIPWIRE_TMP" && pwd -P) && [ -n "$phys" ]; then
    TRIPWIRE_TMP="$phys"
  else
    log "failed to resolve the tripwire state dir to a physical path: $TRIPWIRE_TMP"
    exit 3
  fi
}

# git_common_dir — absolute physical path of the repo's shared git directory
# (where the primary tree and every linked worktree keep the shared object/ref
# store, config, and hooks). Empty if it cannot be resolved.
git_common_dir() {
  local d
  d=$(git -C "$SRC_REPO" rev-parse --git-common-dir 2>/dev/null) || return 0
  [ -n "$d" ] || return 0
  case "$d" in
    /*) ;;
    *) d="$SRC_REPO/$d" ;;
  esac
  (cd "$d" && pwd -P) 2>/dev/null || true
}

# tripwire_guarded_trees — print the physical path of every working tree the
# delegate is NOT allowed to write to: the primary tree AND any other linked
# worktrees of the repo, EXCLUDING our own delegate worktree ($WORKTREE) whose
# writes are the expected work product (ADR-001 Decision 8: snapshot "the
# primary working tree (and any other worktrees of the repo)").
tripwire_guarded_trees() {
  local wt wt_phys
  git -C "$SRC_REPO" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{print substr($0, 10)}' \
    | while IFS= read -r wt; do
        [ -n "$wt" ] || continue
        wt_phys=$(cd "$wt" && pwd -P) 2>/dev/null || continue
        [ "$wt_phys" = "$WORKTREE" ] && continue
        printf '%s\n' "$wt_phys"
      done
}

# tripwire_gitdir_listing — a change-detection listing (cksum: CRC + size +
# path) of the shared git dir's hooks/ and config, i.e. the highest-value
# targets a compromised delegate could plant for code-exec on the user's next
# git op. cksum is detection, not a security hash — that is all a post-hoc
# tripwire needs. The srt write-allowlist is what actually PREVENTS the write.
tripwire_gitdir_listing() {
  local common
  common=$(git_common_dir)
  [ -n "$common" ] || return 0
  [ -f "$common/config" ] && cksum "$common/config" 2>/dev/null
  if [ -d "$common/hooks" ]; then
    find "$common/hooks" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
      cksum "$f" 2>/dev/null
    done
  fi
  return 0
}

# tripwire_snapshot — record, before the delegate runs, the state of everywhere
# the delegate is NOT allowed to write (ADR-001 Decision 8): every guarded
# working tree (primary + sibling worktrees) plus the shared git dir's
# hooks/config. The guarded-tree set is frozen here and reused verbatim after
# the run so before/after compare the same trees.
tripwire_snapshot() {
  mkdir -p "$TRIPWIRE_TMP"
  # Guard the enumeration call site: tripwire_guarded_trees is a
  # git|awk|while-read pipeline, and under `set -o pipefail` a `git worktree
  # list` failure makes the whole pipeline non-zero even when the trailing loop
  # exits 0 — which under `set -e` would abort the script mid-snapshot (before
  # the delegate runs), surfacing a bare exit 1 misclassified as a usage error.
  # `|| true` keeps errexit from firing; the fallback below guarantees we never
  # silently guard NOTHING: if enumeration failed or yielded an empty list, guard
  # at least the primary tree ($SRC_REPO).
  tripwire_guarded_trees > "$TRIPWIRE_TMP/trees.list" 2>/dev/null || true
  if [ ! -s "$TRIPWIRE_TMP/trees.list" ]; then
    log "warning: could not enumerate the repo's worktrees for the write-scope tripwire; guarding the primary tree only ($SRC_REPO)"
    printf '%s\n' "$SRC_REPO" > "$TRIPWIRE_TMP/trees.list"
  fi
  local i=0 tree
  while IFS= read -r tree; do
    [ -n "$tree" ] || continue
    git -C "$tree" status --porcelain --ignored > "$TRIPWIRE_TMP/$i.status.before" 2>/dev/null || true
    git -C "$tree" rev-parse HEAD > "$TRIPWIRE_TMP/$i.head.before" 2>/dev/null || true
    i=$((i + 1))
  done < "$TRIPWIRE_TMP/trees.list"
  tripwire_gitdir_listing > "$TRIPWIRE_TMP/gitdir.before" 2>/dev/null || true
}

# report_act_sandboxed — after the delegate finishes: (1) emit the worktree diff
# (the work product, about to be destroyed) to stdout, and (2) run the
# generalized write-scope tripwire — re-snapshot every guarded tree and the
# shared git dir and surface ANY out-of-scope delta LOUDLY. Writes INSIDE the
# delegate worktree are the expected product; writes anywhere else are a
# violation (ADR-001 Decision 8).
#
# Coverage: the primary tree AND sibling worktrees of the repo (working-tree +
# HEAD), plus the shared git dir's hooks/ and config (a .git/hooks or
# core.hooksPath/credential.helper plant is code-exec on the user's next git op
# — the single highest-value target, otherwise invisible to `git status`).
#
# Honest limits carry over (restate wherever the tripwire is described): it
# brackets the whole run and cannot attribute a change to a specific delegate;
# it is blind to appends to existing ignored files, new files under
# already-ignored dirs, writes outside any git worktree ($HOME, ~/.ssh, ...),
# and to shared-git-dir writes OTHER than hooks/config (objects, refs, ...).
# For all of those the srt write-allowlist jail is the real enforcement; this
# tripwire is only the cheap post-hoc "did the jail behave?" check.
report_act_sandboxed() {
  echo ""
  echo "===== $TIER: changes in the isolated worktree write scope ====="
  local wt_status
  wt_status=$(git -C "$WORKTREE" status --porcelain 2>/dev/null || true)
  if [ -n "$wt_status" ]; then
    printf '%s\n' "$wt_status"
    echo "----- worktree diff -----"
    # Intent-to-add first so brand-new (untracked) files — a coding delegate's
    # most common product — have their CONTENT shown in the diff, not just a
    # `??` status line. The worktree is destroyed on exit, so staging it is
    # harmless.
    git -C "$WORKTREE" add -A -N >/dev/null 2>&1 || true
    git -C "$WORKTREE" --no-pager diff 2>/dev/null
  else
    echo "(the delegate wrote nothing to the worktree)"
  fi
  echo "===== end worktree changes ====="

  # Write-scope tripwire. `|| true` throughout: diff exits non-zero when the
  # snapshots differ (the tripwire's whole point), which would otherwise abort
  # under `set -e` before the check.
  local tripped=0 i=0 tree tree_status_delta tree_head_delta
  while IFS= read -r tree; do
    [ -n "$tree" ] || continue
    git -C "$tree" status --porcelain --ignored > "$TRIPWIRE_TMP/$i.status.after" 2>/dev/null || true
    git -C "$tree" rev-parse HEAD > "$TRIPWIRE_TMP/$i.head.after" 2>/dev/null || true
    tree_status_delta=$(diff "$TRIPWIRE_TMP/$i.status.before" "$TRIPWIRE_TMP/$i.status.after" 2>/dev/null || true)
    tree_head_delta=$(diff "$TRIPWIRE_TMP/$i.head.before" "$TRIPWIRE_TMP/$i.head.after" 2>/dev/null || true)
    if [ -n "$tree_status_delta" ] || [ -n "$tree_head_delta" ]; then
      tripped=1
      log "out-of-scope write in guarded tree: $tree"
      [ -n "$tree_status_delta" ] && log "  status delta:" && printf '%s\n' "$tree_status_delta" >&2
      [ -n "$tree_head_delta" ] && log "  HEAD moved:" && printf '%s\n' "$tree_head_delta" >&2
    fi
    i=$((i + 1))
  done < "$TRIPWIRE_TMP/trees.list"

  tripwire_gitdir_listing > "$TRIPWIRE_TMP/gitdir.after" 2>/dev/null || true
  local gitdir_delta
  gitdir_delta=$(diff "$TRIPWIRE_TMP/gitdir.before" "$TRIPWIRE_TMP/gitdir.after" 2>/dev/null || true)
  if [ -n "$gitdir_delta" ]; then
    tripped=1
    log "out-of-scope write in the shared git dir (hooks/ or config) — this is a code-exec vector on your next git operation:"
    printf '%s\n' "$gitdir_delta" >&2
  fi

  if [ "$tripped" -ne 0 ]; then
    # Loud on stderr (banner) AND a greppable marker on stdout so neither an
    # orchestrator reading stdout nor a human watching stderr can miss it.
    log "!!! WRITE-SCOPE TRIPWIRE TRIPPED !!! a write escaped the allowed worktree scope (see the deltas above)."
    log "the delegate (or the jail) let a change land outside the isolated scope — inspect and revert before trusting this run. Note: the bracket cannot attribute it to a specific delegate, and unrelated activity in the window can also trip it."
    echo "WRITE-SCOPE-TRIPWIRE: out-of-scope write detected outside the isolated worktree scope (primary tree, a sibling worktree, or the shared git dir of $SRC_REPO)"
  fi
}

# --- act-full: widened-posture gate surfacing (ADR-001 Decisions 3, 6, 7) ----

# announce_act_full — surface the widened posture LOUDLY on stderr at invocation
# time (ADR-001 Decision 7's loud-extension philosophy applied to the highest
# tier). Called after the gate has granted act-full and before the delegate runs,
# so the user sees — at the moment of the run — that this delegate is unsandboxed.
announce_act_full() {
  log "!!! act-full GRANTED: FULL ACCESS / SANDBOX WRAPPER OFF !!!"
  log "this delegate runs UNSANDBOXED — unrestricted write, terminal, and network. The srt filesystem jail and egress allowlist are intentionally OFF (ADR-001 Decision 3/6)."
  log "granted only by your explicit --i-approve-full-access on THIS invocation (ADR-001 Decision 4); it confers nothing on future runs and is not persisted anywhere."
  if [ "$PRIMARY_TREE_OPTOUT" = "1" ]; then
    log "--primary-tree: running in the PRIMARY working tree (no isolated worktree). Write-scope tripwire ATTRIBUTION IS FORFEITED — the delegate's edits land directly in your tree and cannot be bracketed. Review the full working-tree diff as an external PR before trusting or integrating it."
  else
    log "writes default into a dedicated isolated worktree (ADR-001 Decision 8); any change OUTSIDE it (primary tree, sibling worktrees, or shared .git hooks/config) is still surfaced as a loud write-scope tripwire signal."
    log "CAVEAT: with the wrapper off, that tripwire is BEST-EFFORT detection, NOT tamper-proof — a full-access delegate can overwrite the tripwire's own snapshots to erase evidence (unlike act-sandboxed, where the jail makes it tamper-resistant). Treat a silent tripwire as a courtesy signal, not proof nothing escaped."
  fi
}

# report_act_full — the act-full result surface (stdout). Prints a greppable,
# loud banner so neither an orchestrator reading stdout nor a human can miss that
# this ran with the wrapper off. In the default worktree mode it then delegates to
# report_act_sandboxed for the worktree diff + write-scope tripwire; in
# --primary-tree mode it states the forfeited attribution instead (the tripwire's
# guarded scope IS where the work lands, so it cannot cleanly attribute).
report_act_full() {
  echo ""
  if [ "$PRIMARY_TREE_OPTOUT" = "1" ]; then
    echo "===== act-full: FULL ACCESS in the PRIMARY tree (wrapper off) ====="
    echo "ACT-FULL-WRAPPER-OFF: ran UNSANDBOXED with unrestricted write/terminal/network, approved via --i-approve-full-access (ADR-001 Decision 3/6)."
    echo "ACT-FULL-PRIMARY-TREE: ran in the primary working tree via --primary-tree; write-scope tripwire attribution is FORFEITED. Any change in this tree may be the delegate's and cannot be bracketed — review the full working-tree diff as an external PR before trusting or integrating it (ADR-001 Decision 8)."
    echo "===== end act-full ====="
  else
    echo "===== act-full: FULL ACCESS (wrapper off), writes defaulted into an isolated worktree ====="
    echo "ACT-FULL-WRAPPER-OFF: ran UNSANDBOXED with unrestricted write/terminal/network, approved via --i-approve-full-access (ADR-001 Decision 3/6). Expected work lands in the isolated worktree below; any delta OUTSIDE it is a loud write-scope tripwire signal."
    echo "ACT-FULL-TRIPWIRE-BEST-EFFORT: with the wrapper off, the write-scope tripwire below is BEST-EFFORT detection, NOT tamper-proof — a full-access delegate could overwrite the tripwire's own snapshots to hide an out-of-scope write (no jail escape needed; unlike act-sandboxed, nothing enforces the store's integrity). It is a courtesy signal, not proof of containment (ADR-001 Decision 8)."
    echo "===== end act-full banner ====="
    report_act_sandboxed
  fi
}

# --- main -------------------------------------------------------------------

usage() {
  log "usage: consult.sh list | consult.sh [--tier <consult|act-sandboxed|act-full>] [--i-approve-full-access] [--primary-tree] <provider> <prompt-file>"
  log "  --i-approve-full-access  required second signal to grant act-full (per-invocation; ADR-001 Decision 4)"
  log "  --primary-tree           act-full only: run in the primary tree instead of an isolated worktree, forfeiting tripwire attribution (ADR-001 Decision 8)"
  exit 1
}

main() {
  [ $# -ge 1 ] || usage

  if [ "$1" = "list" ]; then
    # `list` takes no arguments. Reject trailing tokens loudly rather than
    # silently ignoring them, matching the "unexpected args are loud" posture
    # applied to the provider-invocation path (ADR-001 Decision 4).
    if [ "$#" -gt 1 ]; then
      shift
      log "unexpected argument(s) after 'list': $*"
      log "'list' takes no arguments. Usage: consult.sh list"
      exit 1
    fi
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
      --i-approve-full-access)
        APPROVE_FULL=1; shift ;;
      --primary-tree)
        PRIMARY_TREE_OPTOUT=1; shift ;;
      -*)
        log "unknown option: $1"; usage ;;
      *)
        break ;;
    esac
  done

  # Tier gate (ADR-001 Decision 4): consult (read-only) and act-sandboxed
  # (worktree-scoped writes) are wired. act-full requires TWO independent
  # affirmative signals on this SAME invocation — the tier AND
  # --i-approve-full-access — and is otherwise REFUSED, never silently downgraded
  # to consult and never silently granted. Runs immediately after option parsing,
  # before any provider/prompt validation, so the documented check order
  # (usage → tier gate → srt checks → provider check) holds and no later
  # reordering can slip provider execution in front of the gate.
  case "$TIER" in
    consult) ;;
    act-sandboxed) ;;
    act-full)
      if [ "$APPROVE_FULL" -ne 1 ]; then
        log "tier 'act-full' is refused: it grants FULL ACCESS (unrestricted write/terminal/network, srt wrapper off) and requires a SECOND, distinct per-invocation approval beyond selecting the tier."
        log "re-run with BOTH --tier act-full AND --i-approve-full-access to grant it for this one invocation (it persists nothing; ADR-001 Decision 4)."
        log "refusing — no silent escalation (ADR-001 Decision 4). For read-only review use --tier consult (or no --tier)."
        exit 1
      fi
      # Both signals present: act-full is granted for THIS invocation only. Run
      # with the srt wrapper off (ADR-001 Decision 3/6): the fail-closed srt
      # checks are deliberately skipped below, so an approved act-full run is not
      # blocked merely because srt is absent.
      WRAPPER_OFF=1 ;;
    *)
      log "unknown tier: $TIER (supported: consult | act-sandboxed | act-full)"
      exit 1 ;;
  esac

  local provider="${1:-}" prompt_file="${2:-}"
  [ -n "$provider" ] || usage
  case "$provider" in
    codex|antigravity) ;;
    *) log "unknown provider: $provider (supported: ${PROVIDERS[*]})"; exit 1 ;;
  esac
  [ -n "$prompt_file" ] || usage
  [ -f "$prompt_file" ] || { log "prompt file not found: $prompt_file"; exit 1; }

  # Reject any argument AFTER the provider + prompt file. The option-parse loop
  # above stops at the FIRST non-flag token (the provider: `*) break`), so gate
  # flags placed after the provider are never parsed as options — they arrive
  # here as unconsumed trailing positionals. Silently ignoring them would drop
  # the requested tier/approval and run at the default `consult`, violating the
  # "escalation is never silent … never downgraded to consult" invariant
  # (ADR-001 Decision 4). Refuse loudly instead of downgrading silently.
  if [ "$#" -gt 2 ]; then
    shift 2
    log "unexpected trailing argument(s) after the provider and prompt file: $*"
    log "gate flags (--tier, --i-approve-full-access, --primary-tree) MUST come BEFORE the provider; placed after it they are not parsed and would be silently dropped."
    log "refusing rather than silently running at a lower tier (ADR-001 Decision 4). Correct order: consult.sh [--tier <tier>] [--i-approve-full-access] [--primary-tree] <provider> <prompt-file>"
    exit 1
  fi

  # Loud-surface any gate flag that has NO EFFECT at the selected tier (no
  # silent, invisible flags — the same loud-posture philosophy as ADR-001
  # Decisions 4/7). --primary-tree only opts out of the isolated worktree at
  # act-full (Decision 8); --i-approve-full-access is the second approval signal
  # for act-full only and never escalates on its own (Decision 4). Warn (not
  # refuse) so existing valid invocations are never broken. The act-full gate
  # above already exited if act-full was requested without approval, so an
  # APPROVE_FULL=1 that reaches here necessarily sits at a non-act-full tier.
  if [ "$PRIMARY_TREE_OPTOUT" -eq 1 ] && [ "$TIER" != "act-full" ]; then
    log "warning: --primary-tree has NO EFFECT at tier '$TIER' — it only opts out of the isolated worktree at act-full (ADR-001 Decision 8). Ignoring it."
  fi
  if [ "$APPROVE_FULL" -eq 1 ] && [ "$TIER" != "act-full" ]; then
    log "warning: --i-approve-full-access has NO EFFECT at tier '$TIER' — it is the second approval signal for act-full only and does NOT escalate the tier (ADR-001 Decision 4). Ignoring it."
  fi

  # srt is a HARD, fail-closed prerequisite at consult/act-sandboxed (Decisions
  # 5-6). At act-full the wrapper is intentionally OFF (WRAPPER_OFF), so an
  # approved run is NOT blocked by srt's absence — skip the srt requirement check.
  if [ "$WRAPPER_OFF" -ne 1 ]; then
    require_srt
  fi

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
  # cleanup() tears down the run dir AND (act-sandboxed) the worktree on EVERY
  # exit path — registered now, before the worktree exists, so an early failure
  # in setup still cleans the run dir.
  trap cleanup EXIT
  # Resolve via a temp variable so a failed resolution cannot clobber RUN_TMP:
  # the trap must always see a valid path, or the mktemp'd dir would leak.
  local run_tmp_phys
  if run_tmp_phys=$(cd "$RUN_TMP" && pwd -P) && [ -n "$run_tmp_phys" ]; then
    RUN_TMP="$run_tmp_phys"
  else
    log "failed to resolve the run temp dir to a physical path: $RUN_TMP"
    exit 3
  fi

  # Acting-tier setup: create the isolated worktree write scope AND the
  # tamper-resistant tripwire state dir BEFORE running. act-sandboxed always does
  # this; act-full does it BY DEFAULT (ADR-001 Decision 3/8 — worktree by
  # default) unless --primary-tree is chosen, which forfeits the isolated scope
  # and tripwire attribution. (At act-sandboxed the worktree also feeds the srt
  # write-allowlist; at act-full the wrapper is off so it is purely the
  # tripwire's clean before/after scope.)
  local run_tripwire=0
  if [ "$TIER" = "act-sandboxed" ]; then
    setup_worktree
    setup_tripwire_state
    run_tripwire=1
  elif [ "$TIER" = "act-full" ]; then
    # Worktree by default (Decision 3/8); --primary-tree opts out. Set up BEFORE
    # announcing so a no-repo refusal (which points at --primary-tree) fires
    # before the "GRANTED" banner rather than after it.
    if [ "$PRIMARY_TREE_OPTOUT" -ne 1 ]; then
      setup_worktree
      setup_tripwire_state
      run_tripwire=1
    fi
    announce_act_full
  fi

  # srt settings + preflight are the wrapper's config and only apply when the
  # wrapper is ON (consult/act-sandboxed). At act-full the wrapper is off, so
  # neither is generated and the delegate is launched directly by run_srt.
  if [ "$WRAPPER_OFF" -ne 1 ]; then
    write_srt_settings "$provider"
    srt_preflight
  fi

  if [ "$run_tripwire" -eq 1 ]; then
    tripwire_snapshot
  fi

  local prc=0
  "run_$provider" "$prompt_file" || prc=$?

  # Acting tiers: emit the work product and run the write-scope tripwire
  # regardless of the delegate's exit status — an out-of-scope write can happen
  # on a failing run too, and it must still be surfaced loudly.
  if [ "$TIER" = "act-sandboxed" ]; then
    report_act_sandboxed
  elif [ "$TIER" = "act-full" ]; then
    report_act_full
  fi

  return "$prc"
}

main "$@"
