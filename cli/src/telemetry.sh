#!/usr/bin/env bash
# cli/src/telemetry.sh — eidolons telemetry kernel
# ═══════════════════════════════════════════════════════════════════════════
# Implements the D1 capture path (§4.1) and the D2 store layout (§4.2).
# Dispatched by `cli/eidolons` via: exec bash "$CLI_SRC/telemetry.sh" "$@"
#
# Subcommands (Phase C — only `capture` is functional):
#   capture --hook STOP_<HOST> --stdin   Read Stop hook stdin, project turns
#   rollup  [opts]                       (Phase D stub)
#   report  [opts]                       (Phase D stub)
#   enable                               (Phase F stub)
#   disable                              (Phase F stub)
#
# Honesty contract (C6): every row carries source:audited|estimated.
# Fail-open contract (C5/hook safety): errors NEVER propagate; exit 0 always.
# All log output → stderr. stdout reserved for JSON/data output.
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

# ─── Usage ────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
eidolons telemetry — opt-in token telemetry subsystem (MLP)

Usage:
  eidolons telemetry capture --hook STOP_<HOST> --stdin
  eidolons telemetry rollup  [--by repo|branch|model|eidolon|tier|day] [--since DATE] [--project <slug>] [--json]
  eidolons telemetry report  [--project <slug>] [--since DATE] [--json]
  eidolons telemetry enable
  eidolons telemetry disable

capture   Read a Stop/SessionEnd hook event from stdin, project each assistant
          turn's real API token usage into a turn.v1 row, and append to the
          day-partitioned D2 store. Source 'audited' for claude-code; 'estimated'
          stub for other hosts. ALWAYS exits 0 (fail-open; hook path never errors).

rollup    (Phase D — not yet implemented) Pure-jq M1/M2/M3 aggregation over the store.

report    (Phase D — not yet implemented) Human dashboard: M1 spend by
          repo/branch/model/eidolon/tier, always source-split (audited vs estimated).

enable    (Phase F — not yet implemented) Write the zero-logic Stop shim +
          register the hook in .claude/settings.json.

disable   (Phase F — not yet implemented) Remove the Stop shim + hook entry.

Store layout:
  $EIDOLONS_HOME/telemetry/<project-slug>/<YYYY-MM-DD>.jsonl

Honesty contract: source:audited rows derive from the real session transcript
(ground-truth token counts). source:estimated rows are proxy/heuristic
approximations. Reports ALWAYS split these two — never blend them.

For per-thread ECL token estimates, see: eidolons trace cost
EOF
}

# ─── Subcommand dispatch ─────────────────────────────────────────────────
sub="${1:-}"
[[ $# -gt 0 ]] && shift

case "$sub" in
  capture) ;;  # handled below
  rollup|report|enable|disable)
    die "telemetry $sub: not yet implemented (Phase D/F)"
    ;;
  --help|-h|help)
    usage
    exit 0
    ;;
  "")
    usage
    exit 0
    ;;
  *)
    printf '%s\n' "eidolons telemetry: unknown subcommand '$sub'" >&2
    printf '%s\n' "Run 'eidolons telemetry --help' for usage." >&2
    exit 1
    ;;
esac

# ══════════════════════════════════════════════════════════════════════════
# telemetry capture
# ══════════════════════════════════════════════════════════════════════════

# ── Parse capture args ────────────────────────────────────────────────────
HOOK_NAME=""
READ_STDIN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hook)
      HOOK_NAME="${2:-}"
      [[ -z "$HOOK_NAME" ]] && { printf '%s\n' "telemetry capture: --hook requires a value" >&2; exit 1; }
      shift 2
      ;;
    --stdin)
      READ_STDIN=1
      shift
      ;;
    --help|-h)
      cat <<'CHELP'
eidolons telemetry capture --hook STOP_<HOST> --stdin

Reads a Stop/SessionEnd hook event JSON from stdin.  --hook names the host
adapter (STOP_claude-code, STOP_codex, STOP_copilot, STOP_cursor, STOP_opencode).
Always exits 0 — a hook path must never propagate errors.
CHELP
      exit 0
      ;;
    *)
      printf '%s\n' "telemetry capture: unknown option '$1'" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$HOOK_NAME" ]]; then
  printf '%s\n' "telemetry capture: --hook STOP_<HOST> is required" >&2
  exit 1
fi

# ── Read stdin (mirror run.sh:96-98) ─────────────────────────────────────
HOOK_STDIN_INPUT=""
if [[ "$READ_STDIN" == "1" ]]; then
  HOOK_STDIN_INPUT="$(cat 2>/dev/null || true)"
fi

# ── Derive host from --hook STOP_<HOST> ──────────────────────────────────
# HOOK_NAME is e.g. STOP_claude-code → host = claude-code
_hook_host=""
case "$HOOK_NAME" in
  STOP_*)  _hook_host="${HOOK_NAME#STOP_}" ;;
  *)       _hook_host="$HOOK_NAME" ;;
esac

# ══════════════════════════════════════════════════════════════════════════
# Helper: sha256 of a string (bash 3.2; shasum/sha256sum fallback)
# Writes hex digest to stdout. Returns 0 on success, 1 on failure.
# ══════════════════════════════════════════════════════════════════════════
_sha256_str() {
  local _s="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$_s" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$_s" | sha256sum | awk '{print $1}'
  else
    # Fallback: deterministic composite without hash (still unique per session+index)
    printf '%s' "$_s" | od -A n -t x1 | tr -d ' \n' | head -c 64
  fi
}

# ══════════════════════════════════════════════════════════════════════════
# Helper: append a row to the D2 store, skipping duplicate event_ids
# Args: $1=row_json  $2=day_file
# ══════════════════════════════════════════════════════════════════════════
_append_row_if_new() {
  local _row="$1"
  local _day_file="$2"
  local _event_id
  _event_id="$(printf '%s' "$_row" | jq -r '.event_id // empty' 2>/dev/null || true)"
  if [[ -z "$_event_id" ]]; then
    info "telemetry: row has no event_id, skipping append"
    return 0
  fi
  # Best-effort skip-on-append: check if event_id already in day file.
  if [[ -f "$_day_file" ]]; then
    if grep -qF "\"$_event_id\"" "$_day_file" 2>/dev/null; then
      info "telemetry: event_id $_event_id already present in $_day_file, skipping"
      return 0
    fi
  fi
  # Atomic single-printf append (rows <4KB, O_APPEND safe).
  printf '%s\n' "$_row" >> "$_day_file"
}

# ══════════════════════════════════════════════════════════════════════════
# Adapter: claude-code (audited path)
# ══════════════════════════════════════════════════════════════════════════
telemetry_capture_claude_code() {
  # Extract transcript_path from hook stdin.
  local _tp=""
  if [[ -n "$HOOK_STDIN_INPUT" ]]; then
    _tp="$(printf '%s' "$HOOK_STDIN_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  fi

  # Fail-open: missing/empty transcript_path → info + exit 0 (AC-F1-5).
  if [[ -z "$_tp" ]]; then
    info "telemetry capture claude-code: no transcript_path in hook event; skipping"
    return 0
  fi
  if [[ ! -f "$_tp" ]]; then
    info "telemetry capture claude-code: transcript not found: $_tp; skipping"
    return 0
  fi
  if [[ ! -r "$_tp" ]]; then
    info "telemetry capture claude-code: transcript not readable: $_tp; skipping"
    return 0
  fi

  # Derive the project-slug for the D2 store.
  # We use the transcript's cwd (first assistant line), falling back to PWD.
  local _cwd_from_transcript
  _cwd_from_transcript="$(jq -r 'select(.type=="assistant") | .cwd // empty' "$_tp" 2>/dev/null | head -1 || true)"
  local _store_slug
  if [[ -n "$_cwd_from_transcript" ]]; then
    local _bn
    _bn="$(basename "$_cwd_from_transcript")"
    _store_slug="$(printf '%s' "$_bn" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -e 's|^-||' -e 's|-$||')"
  else
    _store_slug="$(project_slug)"
  fi

  # Get git commit + dirty status (one call per session, using the transcript cwd).
  local _git_commit="" _git_dirty=""
  local _git_cwd="${_cwd_from_transcript:-$PWD}"
  if git -C "$_git_cwd" rev-parse HEAD >/dev/null 2>&1; then
    _git_commit="$(git -C "$_git_cwd" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "$(git -C "$_git_cwd" status --porcelain 2>/dev/null || true)" ]]; then
      _git_dirty="true"
    else
      _git_dirty="false"
    fi
  fi

  # Get PR info from environment.
  local _pr_ref="null"
  if [[ -n "${GITHUB_REF:-}" ]]; then
    _pr_ref="\"${GITHUB_REF}\""
  elif [[ -n "${PR_NUMBER:-}" ]]; then
    _pr_ref="\"${PR_NUMBER}\""
  fi

  # Single jq pass: filter assistant lines, map to turn.v1 rows.
  # We need per-turn event_ids computed in bash (sha256 requires shell),
  # so we first extract the raw turn data via jq, then loop in bash to
  # hash and assemble each row. The jq slice is the bulk work; the bash
  # loop is O(turns) with one sha call each.
  local _turns_json
  _turns_json="$(jq -c '
    [
      . as $line |
      select(.type == "assistant") |
      {
        session_id: .sessionId,
        ts: .timestamp,
        model: (.message.model // "unknown"),
        input_tokens: (.message.usage.input_tokens // 0),
        output_tokens: (.message.usage.output_tokens // 0),
        cache_creation_input_tokens: (.message.usage.cache_creation_input_tokens // 0),
        cache_read_input_tokens: (.message.usage.cache_read_input_tokens // 0),
        cwd: (.cwd // ""),
        git_branch: (.gitBranch // null),
        is_sidechain: (.isSidechain // false),
        request_id: (.requestId // "")
      }
    ]
  ' "$_tp" 2>/dev/null | jq -c '.[]' 2>/dev/null || true)"

  if [[ -z "$_turns_json" ]]; then
    info "telemetry capture claude-code: no assistant turns found in transcript; skipping"
    return 0
  fi

  local _turn_index=0
  local _today
  _today="$(date -u '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')"

  # Process each turn.
  while IFS= read -r _turn; do
    [[ -z "$_turn" ]] && continue

    local _sess_id _ts _model _in _out _cc _cr _cwd _branch _is_sc _req_id
    _sess_id="$(printf '%s' "$_turn" | jq -r '.session_id // "unknown"')"
    _ts="$(printf '%s' "$_turn" | jq -r '.ts // "1970-01-01T00:00:00Z"')"
    _model="$(printf '%s' "$_turn" | jq -r '.model // "unknown"')"
    _in="$(printf '%s' "$_turn" | jq -r '.input_tokens // 0')"
    _out="$(printf '%s' "$_turn" | jq -r '.output_tokens // 0')"
    _cc="$(printf '%s' "$_turn" | jq -r '.cache_creation_input_tokens // 0')"
    _cr="$(printf '%s' "$_turn" | jq -r '.cache_read_input_tokens // 0')"
    _cwd="$(printf '%s' "$_turn" | jq -r '.cwd // ""')"
    _branch="$(printf '%s' "$_turn" | jq -r '.git_branch // null')"
    _is_sc="$(printf '%s' "$_turn" | jq -r '.is_sidechain // false')"

    # Compute event_id: sha256(session_id|turn_index).
    local _event_id
    _event_id="$(_sha256_str "${_sess_id}|${_turn_index}" 2>/dev/null || printf '%s' "${_sess_id}|${_turn_index}" | od -A n -t x1 | tr -d ' \n' | head -c 64)"

    # Derive ts date for day partitioning (from the turn's timestamp).
    local _day
    _day="$(printf '%s' "$_ts" | sed 's/T.*//' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || echo "$_today")"

    # D2 store path.
    local _store_dir="$EIDOLONS_HOME/telemetry/${_store_slug}"
    local _day_file="${_store_dir}/${_day}.jsonl"
    mkdir -p "$_store_dir"

    # Attribution keys (AC-F3-1/F3-2):
    #   repo = basename of cwd (free from transcript line)
    #   branch = from transcript line (no extra git call)
    #   commit/dirty = from the one-per-session git call above
    #   is_sidechain = from transcript line
    #   eidolon = "main" if not sidechain, else "unknown" (honest fallback, Phase E join)
    local _repo
    _repo="$(basename "${_cwd:-$PWD}" 2>/dev/null || echo "unknown")"

    local _eidolon
    if [[ "$_is_sc" == "true" ]]; then
      _eidolon="unknown"
    else
      _eidolon="main"
    fi

    # Build JSON row via jq -nc (no raw prompt/response text — AC-F1-4).
    local _row
    _row="$(jq -nc \
      --arg schema "eidolons.telemetry.turn.v1" \
      --arg event_id "$_event_id" \
      --arg ts "$_ts" \
      --arg source "audited" \
      --arg host "claude-code" \
      --arg session_id "$_sess_id" \
      --argjson turn_index "$_turn_index" \
      --arg model "$_model" \
      --argjson input_tokens "$_in" \
      --argjson output_tokens "$_out" \
      --argjson cache_creation_input_tokens "$_cc" \
      --argjson cache_read_input_tokens "$_cr" \
      --arg repo "$_repo" \
      --argjson branch "$(printf '%s' "$_branch" | jq -R 'if . == "null" then null else . end')" \
      --argjson commit "$(if [[ -n "$_git_commit" ]]; then printf '"%s"' "$_git_commit"; else printf 'null'; fi)" \
      --argjson dirty "$(if [[ -n "$_git_dirty" ]]; then printf '%s' "$_git_dirty"; else printf 'null'; fi)" \
      --argjson pr "$_pr_ref" \
      --arg cwd "${_cwd:-}" \
      --argjson is_sidechain "$_is_sc" \
      --arg eidolon "$_eidolon" \
      '{
        schema: $schema,
        event_id: $event_id,
        ts: $ts,
        source: $source,
        host: $host,
        session_id: $session_id,
        turn_index: $turn_index,
        model: $model,
        usage: {
          input_tokens: $input_tokens,
          output_tokens: $output_tokens,
          cache_creation_input_tokens: $cache_creation_input_tokens,
          cache_read_input_tokens: $cache_read_input_tokens
        },
        self_reported_tokens: null,
        reconciliation_delta: null,
        attribution: {
          repo: $repo,
          branch: $branch,
          commit: $commit,
          dirty: $dirty,
          pr: $pr,
          cwd: $cwd,
          is_sidechain: $is_sidechain,
          eidolon: $eidolon,
          eidolon_prompt_sha: null,
          objective_hash: null,
          task_id: null,
          prompt_version: null,
          tier: null
        },
        ecl_thread_id: null
      }' 2>/dev/null || true)"

    if [[ -z "$_row" ]]; then
      info "telemetry capture: failed to build row for turn $_turn_index; skipping"
      _turn_index=$((_turn_index + 1))
      continue
    fi

    _append_row_if_new "$_row" "$_day_file"
    _turn_index=$((_turn_index + 1))
  done <<EOF
$_turns_json
EOF
}

# ══════════════════════════════════════════════════════════════════════════
# Stubs for non-CC hosts (estimated tier; never tagged audited — AC-F1-6)
# ══════════════════════════════════════════════════════════════════════════
telemetry_capture_codex() {
  info "telemetry capture codex: no audited adapter for codex; estimate tier (P2)"
  # Stub: exits 0, emits nothing audited.
}

telemetry_capture_copilot() {
  info "telemetry capture copilot: no audited adapter for copilot; estimate tier (P2)"
}

telemetry_capture_cursor() {
  info "telemetry capture cursor: no audited adapter for cursor; estimate tier (P2)"
}

telemetry_capture_opencode() {
  info "telemetry capture opencode: no audited adapter for opencode; estimate tier (P2)"
}

# ── Table-driven dispatch by host (one point, no per-host branches in shim)
# Wraps the whole capture in a fail-open guard (AC-F1-5).
# ══════════════════════════════════════════════════════════════════════════

_dispatch_capture() {
  local _host="$1"
  case "$_host" in
    claude-code)
      telemetry_capture_claude_code
      ;;
    codex)
      telemetry_capture_codex
      ;;
    copilot)
      telemetry_capture_copilot
      ;;
    cursor)
      telemetry_capture_cursor
      ;;
    opencode)
      telemetry_capture_opencode
      ;;
    *)
      info "telemetry capture: unknown host '$_host'; no adapter; skipping"
      ;;
  esac
}

# Fail-open wrapper: any unhandled error → info + exit 0.
{
  _dispatch_capture "$_hook_host"
} 2>&1 1>&2 || {
  info "telemetry capture: non-fatal error in adapter for host '$_hook_host'; exiting 0"
}

exit 0
