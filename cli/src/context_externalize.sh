#!/usr/bin/env bash
# cli/src/context_externalize.sh — 'eidolons context externalize' (ECM P1, D5)
# ═══════════════════════════════════════════════════════════════════════════
#
# Drives the D5 canonical persist chain (spec §3.3):
#   1. crystalium_plan_checkpoint  — best-effort, current plan state.
#   2. crystalium_commit(episodic) — the identifier manifest: path:line
#      anchors, symbols, decision IDs, failed-approach log, open variables.
#   3. crystalium_ingest(ecl_envelope) — only when --envelope is given
#      (canonical persist path for a hand-off artifact — no commit-fallback
#      branch for THAT artifact; see context_handoff.sh / AC-16).
#
# Reuses lib_memory_probe.sh's docker-transform (FINDING-011/012) for one-shot
# CLI invocations, exactly like 'eidolons memory preflight' / canary --memory.
# [ASSUMPTION carried from D5 / GAP-D5-ingest]: the one-shot crystalium CLI's
# exact `plan-checkpoint` / `ingest` subcommand shape is unconfirmed in-repo
# (only `recall`/`commit`/`forget` are proven, via canary.sh). This script
# attempts the hyphenated verb names as a best-effort extension of the proven
# `commit` shape; any failure degrades per the fail-open contract below —
# it never blocks and never launders a failure into a false success.
#
# Degradation (AC-3): crystalium absent (memory_probe_gated_in fails) -> warn
# once, write the file-floor manifest .eidolons/.context/externalized-<ts>.json,
# continue (exit 0). Same file-floor fallback fires when crystalium IS gated
# in but the commit call itself fails or exceeds the 1.5s timeout (CC2,
# memory_timeout_ms) — belt-and-suspenders: the identifier manifest must
# survive somewhere.
#
# Budget ledger (D3/AC-14): appends ONE line to
# .eidolons/.context/budget-ledger.jsonl on every call, append-only,
# regardless of crystalium gate state — fan-out-5 safe (O_APPEND semantics).
#
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_context.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_memory_probe.sh"

usage() {
  cat <<'EOF'
eidolons context externalize — checkpoint identifiers to crystalium (D5)

Usage: eidolons context externalize [OPTIONS]

Options:
  --summary <s>             Identifier-manifest summary (required content;
                             default: a generic checkpoint sentence)
  --anchor <path:line>       Repeatable: an exact path:line identifier anchor
  --symbol <name>            Repeatable: a symbol name in scope
  --decision <id>            Repeatable: a decision id made this chain
  --failed-approach <text>   Repeatable: an approach already tried and rejected
  --open-var <text>          Repeatable: an open variable / unresolved question
  --envelope <path>          ECL envelope JSON for crystalium_ingest (canonical
                             persist path when crystalium is gated in)
  --scope-project <slug>     Override the crystalium scope-project slug
  --session-id <id>          Session id (recorded on the manifest + ledger)
  --contains-tool-origin     Provenance: T3 content was in scope this chain (Gap G3)
  --json                     Emit a summary verdict as JSON on stdout
  -h, --help                 Show this help

Exit: always 0 (fail-open; crystalium absent or unreachable never blocks).
EOF
}

SUMMARY=""
ANCHORS=()
SYMBOLS=()
DECISIONS=()
FAILED_APPROACHES=()
OPEN_VARS=()
ENVELOPE_PATH=""
SCOPE_PROJECT=""
SESSION_ID=""
CONTAINS_TOOL_ORIGIN=false
JSON_OUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --summary)             SUMMARY="${2:-}"; shift 2 ;;
    --anchor)              ANCHORS+=("${2:-}"); shift 2 ;;
    --symbol)              SYMBOLS+=("${2:-}"); shift 2 ;;
    --decision)            DECISIONS+=("${2:-}"); shift 2 ;;
    --failed-approach)     FAILED_APPROACHES+=("${2:-}"); shift 2 ;;
    --open-var)            OPEN_VARS+=("${2:-}"); shift 2 ;;
    --envelope)            ENVELOPE_PATH="${2:-}"; shift 2 ;;
    --scope-project)       SCOPE_PROJECT="${2:-}"; shift 2 ;;
    --session-id)          SESSION_ID="${2:-}"; shift 2 ;;
    --contains-tool-origin) CONTAINS_TOOL_ORIGIN=true; shift ;;
    --json)                JSON_OUT=true; shift ;;
    -h|--help)             usage; exit 0 ;;
    *)                     printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$SUMMARY" ] || SUMMARY="Eidolons context externalize checkpoint: identifier manifest recorded while cheap (ECM P1 policy operation)."

PROJECT_ROOT="$(pwd)"
SLUG="$(memory_probe_project_slug "$PROJECT_ROOT")"
[ -n "$SCOPE_PROJECT" ] && SLUG="$SCOPE_PROJECT"

_ts="$(context_now_epoch_ts)"
_iso="$(context_now_iso8601)"
SIDECAR_DIR="$(context_sidecar_dir "$PROJECT_ROOT")"

_anchors_json="$(context_json_array "${ANCHORS[@]:-}")"
_symbols_json="$(context_json_array "${SYMBOLS[@]:-}")"
_decisions_json="$(context_json_array "${DECISIONS[@]:-}")"
_failed_json="$(context_json_array "${FAILED_APPROACHES[@]:-}")"
_openvars_json="$(context_json_array "${OPEN_VARS[@]:-}")"

MANIFEST_JSON="$(jq -n \
  --arg ecm_version "0.1" \
  --arg summary "$SUMMARY" \
  --argjson anchors "$_anchors_json" \
  --argjson symbols "$_symbols_json" \
  --argjson decisions "$_decisions_json" \
  --argjson failed_approaches "$_failed_json" \
  --argjson open_vars "$_openvars_json" \
  --argjson contains_tool_origin "$CONTAINS_TOOL_ORIGIN" \
  --arg session_id "$SESSION_ID" \
  --arg created_at "$_iso" \
  '{
    ecm_version: $ecm_version,
    summary: $summary,
    anchors: $anchors,
    symbols: $symbols,
    decisions: $decisions,
    failed_approaches: $failed_approaches,
    open_vars: $open_vars,
    contains_tool_origin: $contains_tool_origin,
    session_id: (if $session_id == "" then null else $session_id end),
    created_at: $created_at
  }')"

_write_file_floor() {
  local reason="$1"
  local path="$SIDECAR_DIR/externalized-${_ts}.json"
  printf '%s' "$MANIFEST_JSON" | jq --arg reason "$reason" '. + {file_floor_reason: $reason}' \
    > "$path" 2>/dev/null || printf '%s\n' "$MANIFEST_JSON" > "$path"
  printf '%s' "$path"
}

GATED_IN=false
COMMIT_OK=false
FILE_FLOOR_PATH=""
INGEST_ATTEMPTED=false
INGEST_OK=false

if memory_probe_gated_in "$PROJECT_ROOT"; then
  GATED_IN=true

  if command -v docker >/dev/null 2>&1; then
    q_summary="$(memory_probe_quote "$SUMMARY")"
    q_slug="$(memory_probe_quote "$SLUG")"
    q_source="$(memory_probe_quote "environment")"
    q_author="$(memory_probe_quote "eidolons-context-externalize")"
    commit_args="commit --layer episodic --summary $q_summary --scope-project $q_slug --source $q_source --author-agent $q_author --format json"

    commit_script="$(mktemp)"
    if memory_probe_build_docker_script "$PROJECT_ROOT" "$commit_args" "$commit_script"; then
      _commit_exit=0
      _commit_out="$(with_timeout "$ECM_MEMORY_TIMEOUT_S" bash "$commit_script" 2>/dev/null)" || _commit_exit=$?
      if [ "$_commit_exit" -eq 0 ] && [ -n "$_commit_out" ]; then
        COMMIT_OK=true
      fi
    fi
    rm -f "$commit_script"

    # ── plan_checkpoint — best-effort, never gates the manifest's fate ────
    # [ASSUMPTION/GAP-D5-ingest]: `plan-checkpoint` CLI shape is unconfirmed.
    _state_json="$(jq -n --arg scope "$SLUG" '{scope: {project: $scope}}' 2>/dev/null || echo '{}')"
    q_state="$(memory_probe_quote "$_state_json")"
    planckpt_args="plan-checkpoint --state $q_state --format json"
    planckpt_script="$(mktemp)"
    if memory_probe_build_docker_script "$PROJECT_ROOT" "$planckpt_args" "$planckpt_script"; then
      with_timeout "$ECM_MEMORY_TIMEOUT_S" bash "$planckpt_script" >/dev/null 2>&1 || true
    fi
    rm -f "$planckpt_script"

    # ── ingest — only when an envelope was supplied (canonical, AC-16) ────
    if [ -n "$ENVELOPE_PATH" ] && [ -f "$ENVELOPE_PATH" ]; then
      INGEST_ATTEMPTED=true
      _envelope_compact="$(jq -c '.' "$ENVELOPE_PATH" 2>/dev/null || cat "$ENVELOPE_PATH")"
      if context_try_ingest "$PROJECT_ROOT" "$_envelope_compact" "$MANIFEST_JSON"; then
        INGEST_OK=true
      fi
    fi
  fi
else
  warn "context externalize: crystalium not gated in (.mcp.json + eidolons.mcp.lock) — writing file-floor manifest, continuing"
fi

if [ "$GATED_IN" = "false" ] || [ "$COMMIT_OK" = "false" ]; then
  FILE_FLOOR_PATH="$(_write_file_floor "$( [ "$GATED_IN" = "false" ] && echo "crystalium absent" || echo "crystalium commit unreachable or timed out (${ECM_MEMORY_TIMEOUT_S}s budget)")")"
fi

# ── Budget ledger (D3/AC-14): append-only, unconditional ──────────────────
_meter_path="$(context_meter_path "$PROJECT_ROOT" "$SESSION_ID" 0)"
_spent=null
_ceiling=null
if [ -f "$_meter_path" ]; then
  _spent="$(jq -r '.budget.spent_tokens_est // (.used_tokens_est // "null")' "$_meter_path" 2>/dev/null || echo null)"
  _ceiling="$(jq -r '.budget.ceiling_tokens // "null"' "$_meter_path" 2>/dev/null || echo null)"
fi
[ -n "$_spent" ] || _spent=null
[ -n "$_ceiling" ] || _ceiling=null

LEDGER_LINE="$(jq -nc \
  --arg ts "$_iso" \
  --arg session_id "$SESSION_ID" \
  --argjson spent "$_spent" \
  --argjson ceiling "$_ceiling" \
  --argjson gated_in "$GATED_IN" \
  --argjson commit_ok "$COMMIT_OK" \
  '{ts:$ts, session_id: (if $session_id=="" then null else $session_id end),
     operation:"externalize", spent_tokens_est:$spent, ceiling_tokens:$ceiling,
     crystalium_gated_in:$gated_in, commit_ok:$commit_ok}' 2>/dev/null)"
[ -n "$LEDGER_LINE" ] && printf '%s\n' "$LEDGER_LINE" >> "$SIDECAR_DIR/budget-ledger.jsonl" 2>/dev/null || true

if [ "$JSON_OUT" = "true" ]; then
  jq -n \
    --argjson gated_in "$GATED_IN" \
    --argjson commit_ok "$COMMIT_OK" \
    --arg file_floor_path "$FILE_FLOOR_PATH" \
    --argjson ingest_attempted "$INGEST_ATTEMPTED" \
    --argjson ingest_ok "$INGEST_OK" \
    '{gated_in:$gated_in, commit_ok:$commit_ok,
      file_floor_path: (if $file_floor_path=="" then null else $file_floor_path end),
      ingest_attempted:$ingest_attempted, ingest_ok:$ingest_ok}'
else
  if [ "$COMMIT_OK" = "true" ]; then
    ok "context externalize: committed identifier manifest to crystalium (episodic)"
  elif [ -n "$FILE_FLOOR_PATH" ]; then
    info "context externalize: file-floor manifest written to $FILE_FLOOR_PATH"
  fi
fi

exit 0
