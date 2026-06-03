#!/usr/bin/env bash
# eidolons trace — read the ECL trace/telemetry that was previously write-only
# ═══════════════════════════════════════════════════════════════════════════
# Roadmap #4: ECL envelopes carry a `trace` block + context_delta.token_budget /
# tokens_used, but NOTHING consumed them — they were write-only disk provenance
# (the largest standing D3 debt: prime-directives demands telemetry sinks +
# budget-exhaustion control). This verb makes them readable:
#
#   eidolons trace cost <path...> [--budget N]  — per-Eidolon token attribution
#                                                 ledger + budget-exhaustion abort
#   eidolons trace otel <path...>               — emit OpenTelemetry GenAI-convention
#                                                 spans (BUILD the mapping; the
#                                                 backend is yours — pipe to any
#                                                 OTel collector. Never bundled.)
#
# <path> is a junction thread dir (recursed for *.envelope.json) or envelope
# file(s). Deterministic, no LLM. NOTE: token figures are SELF-REPORTED estimates
# (R2-02), not audited spend — treat the ledger as an estimate.
#
# OTel GenAI semantic conventions are [Development]/experimental; the emitted
# attribute set is pinned via --otel-version (default below).

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

OTEL_GENAI_VERSION_DEFAULT="1.30.0"

usage() {
  cat <<EOF
eidolons trace — read ECL hand-off telemetry (token attribution, OTel export)

Usage:
  eidolons trace cost <path...> [--budget N] [--json]
  eidolons trace otel <path...> [--otel-version <ver>]

  <path>   A junction thread dir (recursed for *.envelope.json) or envelope files.

cost     Per-Eidolon token-attribution ledger across the hand-off chain, with an
         optional budget-exhaustion abort (exit 3 when total tokens > --budget).
  --budget N    Abort (exit 3) if the chain's total tokens_used exceeds N.
  --json        Emit the ledger as JSON.

otel     Emit OpenTelemetry GenAI-convention spans (JSON) on stdout — pipe to any
         OTel collector / backend (Langfuse, Datadog, …). The nexus bundles none.
  --otel-version <ver>   Pin the GenAI convention version (default ${OTEL_GENAI_VERSION_DEFAULT}).

Tokens are self-reported estimates, not audited spend.
EOF
}

SUB="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$SUB" in
  -h|--help|"") usage; exit 0 ;;
  cost|otel) ;;
  *) die "Unknown subcommand: $SUB (want: cost | otel). See 'eidolons trace --help'" ;;
esac

BUDGET=""
OUT="text"
OTEL_VERSION="$OTEL_GENAI_VERSION_DEFAULT"
PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget)       BUDGET="${2:-}"; shift 2 ;;
    --json)         OUT="json"; shift ;;
    --otel-version) OTEL_VERSION="${2:-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    -*)             die "Unknown option: $1" ;;
    *)              PATHS+=("$1"); shift ;;
  esac
done
[[ ${#PATHS[@]} -gt 0 ]] || die "No path given. Usage: eidolons trace $SUB <thread-dir|envelope.json...>"

# ── Collect envelope files (thread dir → recurse; file → as-is) ───────────────
ENV_FILES=()
for p in "${PATHS[@]}"; do
  if [[ -d "$p" ]]; then
    while IFS= read -r f; do [[ -n "$f" ]] && ENV_FILES+=("$f"); done < <(find "$p" -name '*.envelope.json' 2>/dev/null | sort)
  elif [[ -f "$p" ]]; then
    ENV_FILES+=("$p")
  else
    warn "trace: path not found: $p"
  fi
done
[[ ${#ENV_FILES[@]} -gt 0 ]] || die "No .envelope.json files found under: ${PATHS[*]}"

# Slurp all envelopes into one JSON array (skip any that aren't valid JSON).
ENV_ARRAY="$(jq -s '[ .[] | select(type=="object") ]' "${ENV_FILES[@]}" 2>/dev/null || echo "[]")"
[[ "$(printf '%s' "$ENV_ARRAY" | jq 'length')" -gt 0 ]] || die "No valid ECL envelopes parsed from: ${PATHS[*]}"

case "$SUB" in
  # ── cost: per-Eidolon token attribution + budget-exhaustion abort ───────────
  cost)
    LEDGER="$(printf '%s' "$ENV_ARRAY" | jq '
      [ .[] | { eidolon: (.from.eidolon // "?"),
                tokens: (.context_delta.tokens_used // 0),
                model: (.trace.model // "?") } ]
      | { by_eidolon: ( group_by(.eidolon)
                        | map({ eidolon: .[0].eidolon,
                                tokens: (map(.tokens) | add),
                                hops: length })
                        | sort_by(-.tokens) ),
          total_tokens: (map(.tokens) | add),
          hops: length }')"
    TOTAL="$(printf '%s' "$LEDGER" | jq -r '.total_tokens')"

    EXCEEDED=false
    if [[ -n "$BUDGET" ]]; then
      if [[ "$TOTAL" -gt "$BUDGET" ]] 2>/dev/null; then EXCEEDED=true; fi
    fi

    if [[ "$OUT" == "json" ]]; then
      printf '%s' "$LEDGER" | jq \
        --argjson budget "${BUDGET:-null}" --argjson exceeded "$EXCEEDED" \
        '. + {budget: $budget, budget_exceeded: $exceeded, note: "self-reported estimates, not audited spend"}'
    else
      printf '%sECL token ledger%s  (%s hops, total %s tokens — estimate)\n' \
        "${BOLD:-}" "${RESET:-}" "$(printf '%s' "$LEDGER" | jq -r '.hops')" "$TOTAL"
      printf '%s' "$LEDGER" | jq -r '.by_eidolon[] | "  \(.eidolon)\t\(.tokens)\t(\(.hops) hop\(if .hops==1 then "" else "s" end))"' \
        | while IFS=$'\t' read -r e t h; do printf '  %-12s %8s  %s\n' "$e" "$t" "$h"; done
      if [[ -n "$BUDGET" ]]; then
        if [[ "$EXCEEDED" == true ]]; then
          warn "budget exhausted: total $TOTAL > budget $BUDGET"
        else
          ok "within budget: total $TOTAL <= budget $BUDGET"
        fi
      fi
    fi
    [[ "$EXCEEDED" == true ]] && exit 3
    exit 0
    ;;

  # ── otel: emit OpenTelemetry GenAI-convention spans ─────────────────────────
  otel)
    printf '%s' "$ENV_ARRAY" | jq \
      --arg otelver "$OTEL_VERSION" \
      '{
        schema: "opentelemetry.gen_ai",
        gen_ai_convention_version: $otelver,
        note: "experimental OTel GenAI conventions; token figures are self-reported estimates",
        spans: [ .[] | {
          trace_id: (.thread_id // "unknown"),
          span_id: (.message_id // "unknown"),
          parent_span_id: (.parent_id // null),
          name: ("invoke_agent " + (.from.eidolon // "?")),
          start_time: (.trace.ts // null),
          attributes: {
            "gen_ai.system": "eidolons",
            "gen_ai.operation.name": "invoke_agent",
            "gen_ai.agent.name": (.from.eidolon // "?"),
            "gen_ai.agent.id": (.from.version // null),
            "gen_ai.request.model": (.trace.model // null),
            "gen_ai.usage.output_tokens": (.context_delta.tokens_used // 0),
            "eidolons.token_budget": (.context_delta.token_budget // null),
            "eidolons.performative": (.performative // null),
            "eidolons.tier": (.trace.tier // null),
            "eidolons.to": (.to.eidolon // null),
            "eidolons.artifact.kind": (.artifact.kind // null),
            "eidolons.host": (.trace.host // null)
          }
        } ]
      }'
    exit 0
    ;;
esac
