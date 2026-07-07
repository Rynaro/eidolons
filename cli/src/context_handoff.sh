#!/usr/bin/env bash
# cli/src/context_handoff.sh — 'eidolons context handoff' (ECM P1 composer, D4)
# ═══════════════════════════════════════════════════════════════════════════
#
# Composes .eidolons/.context/handoff-<ts>.md (D4: 1500-token ADVISORY
# composition target — overflow WARNS + logs size to the policy log, NEVER
# truncates; sections ordered by survival priority: identifiers ->
# failed-approaches -> next-steps -> narrative). Emits the ECL envelope
# sidecar handoff-<ts>.envelope.json (performative INFORM, artifact type
# ecm/handoff-brief@0.1, SHA-256 integrity, thread_id continuity — the
# existing envelope schema, no new performative, CC5).
#
# Persists via crystalium_ingest with a reserved topic_key: session_handoff
# (D5 canonical persist path). AC-16: no commit-fallback branch for THIS
# artifact — ingest succeeds or is skipped; the on-disk brief+envelope pair
# is itself the durable floor either way.
#
# The <=200-token DIGEST is a SEPARATE artifact: successor sessions recall it
# via 'eidolons memory preflight --query "<session_handoff query>"'
# (FINDING-015 — reused verbatim by the SessionStart harness recipe, T-F).
# This script does not print or inject that digest itself.
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
eidolons context handoff — compose a session handoff brief + ECL envelope (D4)

Usage: eidolons context handoff [OPTIONS]

Options:
  --task-state <s>          One-line current task state
  --narrative <s>            Free-text narrative (appended after next-steps)
  --anchor <path:line>       Repeatable: an exact path:line identifier anchor
  --symbol <name>            Repeatable: a symbol name in scope
  --decision <s>             Repeatable: a decision made (+ rationale one-liner)
  --failed-approach <s>      Repeatable: an approach already tried and rejected
  --open-var <s>             Repeatable: an open variable / unresolved question
  --next-step <s>            Repeatable: a concrete next step for the successor
  --thread-id <id>           ECL thread_id (default: derived from session-id or ts)
  --session-id <id>
  --scope-project <slug>     Override the crystalium scope-project slug
  --contains-tool-origin     Gap G3: T3 content was in scope this chain — MUST
                             still surface on default recall (D5 regression, AC-9)
  --json                     Emit a summary verdict as JSON on stdout
  -h, --help                 Show this help

Exit: always 0 (fail-open; crystalium absent/unreachable never blocks — the
on-disk brief + envelope pair is written regardless).
EOF
}

TASK_STATE=""
NARRATIVE=""
ANCHORS=()
SYMBOLS=()
DECISIONS=()
FAILED_APPROACHES=()
OPEN_VARS=()
NEXT_STEPS=()
THREAD_ID=""
SESSION_ID=""
SCOPE_PROJECT=""
CONTAINS_TOOL_ORIGIN=false
JSON_OUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --task-state)          TASK_STATE="${2:-}"; shift 2 ;;
    --narrative)           NARRATIVE="${2:-}"; shift 2 ;;
    --anchor)              ANCHORS+=("${2:-}"); shift 2 ;;
    --symbol)              SYMBOLS+=("${2:-}"); shift 2 ;;
    --decision)            DECISIONS+=("${2:-}"); shift 2 ;;
    --failed-approach)     FAILED_APPROACHES+=("${2:-}"); shift 2 ;;
    --open-var)            OPEN_VARS+=("${2:-}"); shift 2 ;;
    --next-step)           NEXT_STEPS+=("${2:-}"); shift 2 ;;
    --thread-id)           THREAD_ID="${2:-}"; shift 2 ;;
    --session-id)          SESSION_ID="${2:-}"; shift 2 ;;
    --scope-project)       SCOPE_PROJECT="${2:-}"; shift 2 ;;
    --contains-tool-origin) CONTAINS_TOOL_ORIGIN=true; shift ;;
    --json)                JSON_OUT=true; shift ;;
    -h|--help)             usage; exit 0 ;;
    *)                     printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

PROJECT_ROOT="$(pwd)"
SLUG="$(memory_probe_project_slug "$PROJECT_ROOT")"
[ -n "$SCOPE_PROJECT" ] && SLUG="$SCOPE_PROJECT"

_ts="$(context_now_epoch_ts)"
_iso="$(context_now_iso8601)"
SIDECAR_DIR="$(context_sidecar_dir "$PROJECT_ROOT")"

[ -n "$THREAD_ID" ] || THREAD_ID="${SESSION_ID:-handoff-$_ts}"
[ -n "$TASK_STATE" ] || TASK_STATE="(no task-state summary provided)"

# ── Compose the brief (survival-priority order: identifiers -> failed ────
# approaches -> next-steps -> narrative). Never truncated (AC-8).
_md="# Session Handoff Brief

## Identifiers
"
if [ "${#ANCHORS[@]}" -gt 0 ]; then
  for _a in "${ANCHORS[@]}"; do [ -n "$_a" ] && _md="${_md}- anchor: ${_a}
"; done
fi
if [ "${#SYMBOLS[@]}" -gt 0 ]; then
  for _s in "${SYMBOLS[@]}"; do [ -n "$_s" ] && _md="${_md}- symbol: ${_s}
"; done
fi
if [ "${#DECISIONS[@]}" -gt 0 ]; then
  for _d in "${DECISIONS[@]}"; do [ -n "$_d" ] && _md="${_md}- decision: ${_d}
"; done
fi

_md="${_md}
## Failed approaches
"
if [ "${#FAILED_APPROACHES[@]}" -gt 0 ]; then
  for _f in "${FAILED_APPROACHES[@]}"; do [ -n "$_f" ] && _md="${_md}- ${_f}
"; done
else
  _md="${_md}(none recorded)
"
fi

_md="${_md}
## Next steps
"
if [ "${#NEXT_STEPS[@]}" -gt 0 ]; then
  for _n in "${NEXT_STEPS[@]}"; do [ -n "$_n" ] && _md="${_md}- ${_n}
"; done
else
  _md="${_md}(none recorded)
"
fi

_md="${_md}
## Narrative

Task state: ${TASK_STATE}
"
[ -n "$NARRATIVE" ] && _md="${_md}
${NARRATIVE}
"

if [ "${#OPEN_VARS[@]}" -gt 0 ]; then
  _md="${_md}
## Open variables
"
  for _o in "${OPEN_VARS[@]}"; do [ -n "$_o" ] && _md="${_md}- ${_o}
"; done
fi

_md="${_md}
## contains_tool_origin
${CONTAINS_TOOL_ORIGIN}
"

BRIEF_PATH="$SIDECAR_DIR/handoff-${_ts}.md"
printf '%s' "$_md" > "$BRIEF_PATH"

# ── Advisory 1500-token target (D4): log oversize, never truncate (AC-8) ──
_brief_bytes="$(wc -c < "$BRIEF_PATH" 2>/dev/null | tr -d ' ' || echo 0)"
[ -n "$_brief_bytes" ] || _brief_bytes=0
_tokens_est="$(context_bytes_to_tokens "$_brief_bytes")"

_target_tokens=1500
_policy_file="$(context_policy_file)"
if [ -f "$_policy_file" ]; then
  _pt="$(yaml_to_json "$_policy_file" 2>/dev/null | jq -r '.limits.handoff_brief_target_tokens // 1500' 2>/dev/null || echo 1500)"
  case "$_pt" in ''|*[!0-9]*) : ;; *) _target_tokens="$_pt" ;; esac
fi

OVERSIZE=false
if [ "$_tokens_est" -gt "$_target_tokens" ]; then
  OVERSIZE=true
  _log_line="$(jq -nc --arg ts "$_iso" --arg path "$BRIEF_PATH" \
    --argjson tokens_est "$_tokens_est" --argjson target "$_target_tokens" \
    '{event:"handoff_brief_oversize", evaluated_at:$ts, path:$path, tokens_est:$tokens_est, target_tokens:$target}' 2>/dev/null || echo '{}')"
  printf '%s\n' "$_log_line" >> "$SIDECAR_DIR/policy-log.jsonl" 2>/dev/null || true
  warn "context handoff: brief exceeds the ${_target_tokens}-token advisory target (est. ${_tokens_est}) — logged, NOT truncated"
fi

# ── ECL envelope sidecar (INFORM, ecm/handoff-brief@0.1, SHA-256) ─────────
_sha="$(context_sha256_file "$BRIEF_PATH")"
ENVELOPE_PATH="$SIDECAR_DIR/handoff-${_ts}.envelope.json"

ENVELOPE_JSON="$(jq -n \
  --arg message_id "msg-context-handoff-${_ts}" \
  --arg thread_id "$THREAD_ID" \
  --arg from_version "${EIDOLONS_VERSION:-n/a}" \
  --arg artifact_path "handoff-${_ts}.md" \
  --arg sha "$_sha" \
  --argjson size_bytes "$_brief_bytes" \
  --arg ts "$_iso" \
  --argjson contains_tool_origin "$CONTAINS_TOOL_ORIGIN" \
  '{
    envelope_version: "1.0",
    message_id: $message_id,
    thread_id: $thread_id,
    parent_id: null,
    from: {eidolon: "eidolons-context-kernel", version: $from_version},
    to: {eidolon: "session_successor", version: "n/a"},
    objective: "Session handoff brief for context-lifecycle succession (ECM P1).",
    performative: "INFORM",
    artifact: {kind: "ecm/handoff-brief@0.1", schema_version: "0.1", path: $artifact_path, sha256: $sha, size_bytes: $size_bytes},
    integrity: {method: "sha256", value: $sha},
    trace: {ts: $ts, host: "claude-code", model: "n/a", tier: "standard"},
    topic_key: "session_handoff",
    contains_tool_origin: $contains_tool_origin
  }')"

printf '%s\n' "$ENVELOPE_JSON" > "$ENVELOPE_PATH"

# ── crystalium_ingest — canonical persist path, NO commit fallback (AC-16) ─
GATED_IN=false
INGEST_ATTEMPTED=false
INGEST_OK=false

if memory_probe_gated_in "$PROJECT_ROOT"; then
  GATED_IN=true
  INGEST_ATTEMPTED=true
  if context_try_ingest "$PROJECT_ROOT" "$ENVELOPE_JSON" "$_md"; then
    INGEST_OK=true
  else
    warn "context handoff: crystalium_ingest unreachable or timed out — brief + envelope remain on disk (file floor); NOT falling back to commit (AC-16)"
  fi
fi

if [ "$JSON_OUT" = "true" ]; then
  jq -n \
    --arg brief_path "$BRIEF_PATH" \
    --arg envelope_path "$ENVELOPE_PATH" \
    --arg sha256 "$_sha" \
    --arg thread_id "$THREAD_ID" \
    --argjson tokens_est "$_tokens_est" \
    --argjson oversize "$OVERSIZE" \
    --argjson gated_in "$GATED_IN" \
    --argjson ingest_attempted "$INGEST_ATTEMPTED" \
    --argjson ingest_ok "$INGEST_OK" \
    --argjson contains_tool_origin "$CONTAINS_TOOL_ORIGIN" \
    '{brief_path:$brief_path, envelope_path:$envelope_path, sha256:$sha256,
      thread_id:$thread_id, tokens_est:$tokens_est, oversize:$oversize,
      gated_in:$gated_in, ingest_attempted:$ingest_attempted, ingest_ok:$ingest_ok,
      contains_tool_origin:$contains_tool_origin}'
else
  ok "context handoff: brief written to $BRIEF_PATH (sha256 ${_sha})"
fi

exit 0
