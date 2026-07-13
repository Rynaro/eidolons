#!/usr/bin/env bash
# cli/src/context_status.sh — 'eidolons context status' (ECM P1, D1 meter)
# ═══════════════════════════════════════════════════════════════════════════
#
# D1 3-rung estimation ladder:
#   rung 1 — host telemetry (Claude Code statusline context_window.used_percentage,
#            evidence C4) -> estimate_source=host, EXACT, no estimation.
#   rung 2 — transcript bytes/ECM_BYTES_PER_TOKEN heuristic (evidence C7, all
#            hook payloads carry transcript_path) -> estimate_source=transcript_heuristic.
#   rung 3 — neither present -> zone=unknown -> policy resolves to `continue`
#            (fail-open floor, CC2). Never blocks.
#
# Writes the .eidolons/.context/meter.json sidecar (spec §3.1 shape). Subagent
# sessions (--subagent) key their OWN file meter-<session_id>.json (D3).
#
# Budget: pure bash+jq, target <=300ms (CC3, prompt_path_ms). Never blocks:
# any failure degrades to zone=unknown, exit 0.
#
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.
# Stderr discipline: say/ok/info/warn/die -> stderr; stdout reserved (--json only).

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_context.sh"

usage() {
  cat <<'EOF'
eidolons context status — write the ECM meter sidecar (D1 3-rung ladder)

Usage: eidolons context status [OPTIONS]

Options:
  --used-percentage <0-100>  Explicit host telemetry utilization (rung-1: exact,
                              no estimation). Mirrors Claude Code statusline's
                              context_window.used_percentage.
  --transcript <path>        Transcript file for the bytes/N heuristic (rung-2).
  --stdin                    Read a hook/statusline JSON payload from stdin and
                              extract context_window.used_percentage /
                              transcript_path / session_id from it.
  --session-id <id>          Session id (subagent meter-file keying, D3).
  --subagent                 This is a subagent session (own meter file, D3).
  --window-tokens <n>        Context window size (default: 200000, or the
                              stdin payload's context_window.context_window_size).
  --tool-result-share <0-1>  tool_result_share_est (default: inherited or 0).
  --compaction-count <n>     compaction_count (default: inherited or 0).
  --budget-ceiling <n>       budget.ceiling_tokens (default: inherited or null).
  --json                     Also print the written meter JSON to stdout.
  -h, --help                 Show this help

Exit: always 0 (fail-open; unreadable telemetry/transcript degrades to
zone=unknown rather than failing).
EOF
}

USED_PCT=""
TRANSCRIPT=""
READ_STDIN=false
SESSION_ID=""
SUBAGENT=0
WINDOW_TOKENS=""
TOOL_RESULT_SHARE=""
COMPACTION_COUNT=""
BUDGET_CEILING=""
JSON_OUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --used-percentage)  USED_PCT="${2:-}"; shift 2 ;;
    --transcript)        TRANSCRIPT="${2:-}"; shift 2 ;;
    --stdin)             READ_STDIN=true; shift ;;
    --session-id)        SESSION_ID="${2:-}"; shift 2 ;;
    --subagent)           SUBAGENT=1; shift ;;
    --window-tokens)      WINDOW_TOKENS="${2:-}"; shift 2 ;;
    --tool-result-share)  TOOL_RESULT_SHARE="${2:-}"; shift 2 ;;
    --compaction-count)   COMPACTION_COUNT="${2:-}"; shift 2 ;;
    --budget-ceiling)     BUDGET_CEILING="${2:-}"; shift 2 ;;
    --json)               JSON_OUT=true; shift ;;
    -h|--help)            usage; exit 0 ;;
    *)                    printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

PROJECT_ROOT="$(pwd)"

# ── Optional stdin payload (statusline JSON or hook event JSON) ───────────
_stdin_json=""
if [ "$READ_STDIN" = "true" ]; then
  _stdin_json="$(cat 2>/dev/null || true)"
fi

_extract_stdin() {
  local field="$1"
  [ -n "$_stdin_json" ] || { printf ''; return 0; }
  printf '%s' "$_stdin_json" | jq -r "$field // empty" 2>/dev/null || printf ''
}

if [ -z "$USED_PCT" ] && [ -n "$_stdin_json" ]; then
  USED_PCT="$(_extract_stdin '.context_window.used_percentage')"
fi
if [ -z "$TRANSCRIPT" ] && [ -n "$_stdin_json" ]; then
  TRANSCRIPT="$(_extract_stdin '.transcript_path')"
fi
if [ -z "$SESSION_ID" ] && [ -n "$_stdin_json" ]; then
  SESSION_ID="$(_extract_stdin '.session_id')"
fi
if [ -z "$WINDOW_TOKENS" ] && [ -n "$_stdin_json" ]; then
  WINDOW_TOKENS="$(_extract_stdin '.context_window.context_window_size')"
fi

[ -n "$WINDOW_TOKENS" ] || WINDOW_TOKENS="$ECM_DEFAULT_WINDOW_TOKENS"

# ── Inherit prior meter fields (compaction_count, budget ceiling, etc.) ────
METER_PATH="$(context_meter_path "$PROJECT_ROOT" "$SESSION_ID" "$SUBAGENT")"
_prev_compaction=0
_prev_ceiling=null
_prev_age=0
# R2: a prior meter that is not valid JSON is treated as ABSENT (inherit
# defaults) rather than partially read. Without this guard, a corrupt file
# makes `jq -r '...' 2>/dev/null || echo 0` capture BOTH jq's partial stdout
# AND the `|| echo 0` fallback (jq prints what it parsed, then exits 5 on the
# trailing garbage) -> a two-line value where --argjson below demands a
# single JSON scalar -> the compose fails -> METER_JSON="" -> the kernel
# bails BEFORE ever reaching the write -> the corrupt file can never be
# overwritten. `jq empty` validates the WHOLE file (including any trailing
# garbage) in one shot, so a corrupt-tailed file fails this guard and falls
# through to the defaults, letting the write below heal it unconditionally.
if [ -f "$METER_PATH" ] && jq empty "$METER_PATH" >/dev/null 2>&1; then
  _prev_compaction="$(jq -r '.compaction_count // 0' "$METER_PATH" 2>/dev/null || echo 0)"
  _prev_ceiling="$(jq -r '.budget.ceiling_tokens // "null"' "$METER_PATH" 2>/dev/null || echo null)"
  _prev_age="$(jq -r '.externalize_age_turns // 0' "$METER_PATH" 2>/dev/null || echo 0)"
fi

[ -n "$COMPACTION_COUNT" ] || COMPACTION_COUNT="$_prev_compaction"
if [ -z "$BUDGET_CEILING" ]; then
  BUDGET_CEILING="$_prev_ceiling"
fi
[ -n "$TOOL_RESULT_SHARE" ] || TOOL_RESULT_SHARE="0"

# ── D1 estimation ladder ───────────────────────────────────────────────────
UTILIZATION=""
ESTIMATE_SOURCE="unknown"
USED_TOKENS_EST=""

case "$USED_PCT" in
  ''|*[!0-9.]*) : ;;  # not numeric -> fall through to rung 2
  *)
    UTILIZATION="$(awk -v p="$USED_PCT" 'BEGIN { printf "%.6f", p/100 }')"
    ESTIMATE_SOURCE="host"
    USED_TOKENS_EST="$(awk -v u="$UTILIZATION" -v w="$WINDOW_TOKENS" 'BEGIN { printf "%d", u*w }')"
    ;;
esac

if [ -z "$UTILIZATION" ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  _bytes="$(wc -c < "$TRANSCRIPT" 2>/dev/null | tr -d ' ' || echo 0)"
  [ -n "$_bytes" ] || _bytes=0
  USED_TOKENS_EST="$(context_bytes_to_tokens "$_bytes")"
  UTILIZATION="$(awk -v t="$USED_TOKENS_EST" -v w="$WINDOW_TOKENS" 'BEGIN { if (w>0) printf "%.6f", t/w; else print "0" }')"
  ESTIMATE_SOURCE="transcript_heuristic"
fi

ZONE="$(context_zone_of "$UTILIZATION")"

UPDATED_AT="$(context_now_iso8601)"

# ── Compose + write meter.json (D1 rung-3: still write, zone=unknown) ─────
_util_json=null
[ -n "$UTILIZATION" ] && _util_json="$UTILIZATION"
_tokens_json=null
[ -n "$USED_TOKENS_EST" ] && _tokens_json="$USED_TOKENS_EST"
_session_json=null
[ -n "$SESSION_ID" ] && _session_json="\"$SESSION_ID\""
_ceiling_json="$BUDGET_CEILING"
case "$_ceiling_json" in ''|null) _ceiling_json=null ;; esac

METER_JSON="$(jq -n \
  --arg ecm_version "0.1" \
  --argjson session_id "$_session_json" \
  --argjson window_tokens "$WINDOW_TOKENS" \
  --argjson used_tokens_est "$_tokens_json" \
  --argjson utilization "$_util_json" \
  --arg estimate_source "$ESTIMATE_SOURCE" \
  --arg zone "$ZONE" \
  --argjson tool_result_share_est "$TOOL_RESULT_SHARE" \
  --argjson compaction_count "$COMPACTION_COUNT" \
  --argjson externalize_age_turns "$_prev_age" \
  --argjson ceiling_tokens "$_ceiling_json" \
  --arg updated_at "$UPDATED_AT" \
  '{
    ecm_version: $ecm_version,
    session_id: $session_id,
    window_tokens: $window_tokens,
    used_tokens_est: $used_tokens_est,
    utilization: $utilization,
    estimate_source: $estimate_source,
    zone: $zone,
    tool_result_share_est: $tool_result_share_est,
    compaction_count: $compaction_count,
    externalize_age_turns: $externalize_age_turns,
    budget: { ceiling_tokens: $ceiling_tokens, spent_tokens_est: $used_tokens_est },
    updated_at: $updated_at
  }' 2>/dev/null)" || METER_JSON=""

if [ -z "$METER_JSON" ]; then
  warn "context status: failed to compose meter.json — degrading to unknown, not writing sidecar"
  exit 0
fi

# R1: atomic write — temp file in the SAME directory (same filesystem, so
# `mv` is an atomic rename) + `mv -f` into place, so a concurrent reader or
# writer never observes a partially-written file. The directory already
# exists (context_meter_path -> context_sidecar_dir does `mkdir -p` above).
# Fail-open at every step; clean up the temp file on any failure.
_meter_dir="$(dirname "$METER_PATH")"
_meter_tmp="$(mktemp "$_meter_dir/.meter.XXXXXX" 2>/dev/null || true)"
if [ -z "$_meter_tmp" ]; then
  warn "context status: could not create temp file for atomic write — degrading, not writing sidecar"
  exit 0
fi
if ! printf '%s\n' "$METER_JSON" > "$_meter_tmp" 2>/dev/null; then
  rm -f "$_meter_tmp" 2>/dev/null
  warn "context status: could not write temp meter file"
  exit 0
fi
if ! mv -f "$_meter_tmp" "$METER_PATH" 2>/dev/null; then
  rm -f "$_meter_tmp" 2>/dev/null
  warn "context status: could not rename temp meter file into place"
  exit 0
fi

if [ "$JSON_OUT" = "true" ]; then
  printf '%s\n' "$METER_JSON"
fi

exit 0
