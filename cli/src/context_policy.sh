#!/usr/bin/env bash
# cli/src/context_policy.sh — 'eidolons context policy' (ECM P1 evaluator)
# ═══════════════════════════════════════════════════════════════════════════
#
# Copies run.sh's shape (FINDING-016/017): yaml_to_json roster/context-policy.yaml
# ONCE -> ONE named jq heredoc reading meter.json as the $ctx argjson (analogous
# to run.sh's $CTX_JSON) -> first-match-wins over rows P1-P7. No shell-side
# per-row branching — every conditional lives inside jq.
#
# D3: subagent sessions (--subagent) remap handoff_fresh/wrap_up verdicts to
# finish_and_return (subagents cannot spawn successors), and the P1
# budget-ceiling row is evaluated ONLY in the orchestrator (non-subagent)
# session. zone=unknown always resolves to P7 continue (fail-open, CC2).
#
# Every evaluation appends a signal-snapshot line to
# .eidolons/.context/policy-log.jsonl (spec §4 audit trail) — logged
# unconditionally, independent of --json.
#
# Determinism (AC-2): the --json verdict is a pure function of
# (meter.json, roster/context-policy.yaml, --subagent) — no wall-clock or
# other non-deterministic field is included in it (the policy-log entry
# carries its own timestamp separately).
#
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_context.sh"

usage() {
  cat <<'EOF'
eidolons context policy — evaluate roster/context-policy.yaml over the meter

Usage: eidolons context policy [OPTIONS]

Options:
  --meter <path>   Meter JSON to evaluate (default: .eidolons/.context/meter.json,
                    or meter-<session-id>.json when --subagent is set)
  --session-id <id> Session id (used to resolve the default subagent meter path)
  --subagent        Evaluate as a subagent session (D3): skip the P1
                    budget-ceiling row, and remap handoff_fresh/wrap_up
                    verdicts to finish_and_return.
  --policy <path>   Policy file (default: roster/context-policy.yaml, nexus-shipped)
  --json            Emit the verdict as JSON on stdout (default: human line)
  -h, --help        Show this help

Exit: always 0. Missing/unreadable meter.json degrades to zone=unknown -> P7 continue.
EOF
}

METER_PATH=""
SESSION_ID=""
SUBAGENT=0
POLICY_PATH=""
JSON_OUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --meter)       METER_PATH="${2:-}"; shift 2 ;;
    --session-id)  SESSION_ID="${2:-}"; shift 2 ;;
    --subagent)    SUBAGENT=1; shift ;;
    --policy)      POLICY_PATH="${2:-}"; shift 2 ;;
    --json)        JSON_OUT=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

PROJECT_ROOT="$(pwd)"
[ -n "$METER_PATH" ] || METER_PATH="$(context_meter_path "$PROJECT_ROOT" "$SESSION_ID" "$SUBAGENT")"
[ -n "$POLICY_PATH" ] || POLICY_PATH="$(context_policy_file)"

_ctx_json="{}"
if [ -f "$METER_PATH" ]; then
  _ctx_json="$(cat "$METER_PATH" 2>/dev/null || echo '{}')"
  printf '%s' "$_ctx_json" | jq empty >/dev/null 2>&1 || _ctx_json="{}"
fi

if [ ! -f "$POLICY_PATH" ]; then
  warn "context policy: policy file not found ($POLICY_PATH) — degrading to continue"
  _ctx_json='{"zone":"unknown"}'
fi

POLICY_JSON="$(yaml_to_json "$POLICY_PATH" 2>/dev/null || echo '{}')"

# ── The policy program (mirrors run.sh's single-jq-heredoc shape) ─────────
read -r -d '' POLICY_JQ <<'JQ' || true
. as $R
| $R.limits as $L
| $ctx as $m
| ($m.zone // "unknown") as $zone
| ($m.compaction_count // 0) as $cc
| ($m.tool_result_share_est // 0) as $trs
| ($subagent | not) as $eval_budget
| (if $eval_budget then (($m.budget.ceiling_tokens // null) != null) else false end) as $ceiling_set
| (if $ceiling_set then (($m.budget.spent_tokens_est // 0) >= ($m.budget.ceiling_tokens // 0)) else false end) as $spent_gte
| (
    if ($ceiling_set and $spent_gte) then { rule: "P1", operation: "wrap_up" }
    elif ($zone == "critical") then { rule: "P2", operation: "handoff_fresh" }
    elif ($zone == "red" and $cc < ($L.compaction_depth_cap // 2)) then { rule: "P3", operation: "compact" }
    elif ($zone == "red") then { rule: "P4", operation: "handoff_fresh" }
    elif ($zone == "amber" and $trs >= ($L.tool_result_share_prune // 0.40)) then { rule: "P5", operation: "prune_tool_results" }
    elif ($zone == "amber") then { rule: "P6", operation: "externalize" }
    else { rule: "P7", operation: "continue" }
    end
  ) as $decision
| ($decision.operation) as $raw_op
| (if ($subagent and ($raw_op == "handoff_fresh" or $raw_op == "wrap_up"))
   then "finish_and_return"
   else $raw_op
   end) as $final_op
| {
    rule: $decision.rule,
    operation: $final_op,
    raw_operation: $raw_op,
    zone: $zone,
    compaction_count: $cc,
    tool_result_share_est: $trs,
    budget_ceiling_set: $ceiling_set,
    budget_spent_gte_ceiling: $spent_gte,
    subagent: $subagent
  }
JQ

_subagent_bool=false
[ "$SUBAGENT" = "1" ] && _subagent_bool=true

VERDICT="$(printf '%s' "$POLICY_JSON" | jq \
  --argjson ctx "$_ctx_json" \
  --argjson subagent "$_subagent_bool" \
  "$POLICY_JQ" 2>/dev/null)" || VERDICT=""

if [ -z "$VERDICT" ]; then
  warn "context policy: evaluation failed — degrading to continue (fail-open, CC2)"
  VERDICT='{"rule":"P7","operation":"continue","raw_operation":"continue","zone":"unknown","compaction_count":0,"tool_result_share_est":0,"budget_ceiling_set":false,"budget_spent_gte_ceiling":false,"subagent":false}'
fi

# ── Audit trail: append a signal-snapshot line unconditionally ────────────
LOG_DIR="$(context_sidecar_dir "$PROJECT_ROOT")"
LOG_FILE="$LOG_DIR/policy-log.jsonl"
_ts="$(context_now_iso8601)"
_log_line="$(printf '%s' "$VERDICT" | jq -c --arg ts "$_ts" '. + {evaluated_at: $ts}' 2>/dev/null || echo "{}")"
printf '%s\n' "$_log_line" >> "$LOG_FILE" 2>/dev/null || true

if [ "$JSON_OUT" = "true" ]; then
  printf '%s\n' "$VERDICT"
else
  _rule="$(printf '%s' "$VERDICT" | jq -r '.rule' 2>/dev/null || echo '?')"
  _op="$(printf '%s' "$VERDICT" | jq -r '.operation' 2>/dev/null || echo '?')"
  _zone="$(printf '%s' "$VERDICT" | jq -r '.zone' 2>/dev/null || echo '?')"
  printf 'operation: %s  (rule %s, zone %s)\n' "$_op" "$_rule" "$_zone"
fi

exit 0
