#!/usr/bin/env bash
# eidolons ledger — append-only local observed-execution ledger (PL-03).
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: eidolons ledger open|record|status|complete [options]

open     --run-id ID [--route PATH]                 create a planned event
record   --run-id ID --type TYPE [--requested JSON] [--observed JSON] [--evidence PATH]
complete --run-id ID --artifact PATH --checker ID --scope TEXT --verdict pass|fail
status   --run-id ID [--json]

Events are committed as individual files by atomic rename.  Requested and
observed state remain separate; completion requires an independent passing
checker linked to an artifact digest. Raw prompts and tool payloads are absent.
EOF
}

sub="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$sub" in open|record|status|complete) ;; -h|--help|"") usage; exit 0 ;; *) die "Unknown ledger command: $sub" ;; esac
run_id=""; route=""; event_type=""; requested='{}'; observed='{}'; evidence=""; artifact=""; checker=""; scope=""; verdict=""; json=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) run_id="${2:-}"; shift 2 ;; --route) route="${2:-}"; shift 2 ;;
    --type) event_type="${2:-}"; shift 2 ;; --requested) requested="${2:-}"; shift 2 ;;
    --observed) observed="${2:-}"; shift 2 ;; --evidence) evidence="${2:-}"; shift 2 ;;
    --artifact) artifact="${2:-}"; shift 2 ;; --checker) checker="${2:-}"; shift 2 ;;
    --scope) scope="${2:-}"; shift 2 ;; --verdict) verdict="${2:-}"; shift 2 ;;
    --json) json=true; shift ;; *) die "Unknown option: $1" ;;
  esac
done
[[ "$run_id" =~ ^[A-Za-z0-9._-]+$ ]] || die "--run-id must contain only letters, digits, dot, underscore, or dash"
root=".eidolons/.ledger/$run_id"; events="$root/events"; mkdir -p "$events"

commit_event() {
  local type="$1" req="$2" obs="$3" refs="$4" seq id prev payload tmp
  jq -e . >/dev/null <<<"$req" || die "--requested must be JSON"
  jq -e . >/dev/null <<<"$obs" || die "--observed must be JSON"
  jq -e . >/dev/null <<<"$refs" || die "internal evidence JSON invalid"
  seq="$(find "$events" -name '*.json' -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  seq=$((seq + 1)); id="${run_id}-${seq}"
  prev="$(find "$events" -name '*.json' -maxdepth 1 -type f 2>/dev/null | sort | tail -1 | xargs -I{} jq -r '.event_digest // empty' {} 2>/dev/null || true)"
  payload="$(jq -n --arg id "$id" --arg run "$run_id" --arg type "$type" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg prev "$prev" --argjson seq "$seq" --argjson req "$req" --argjson obs "$obs" --argjson refs "$refs" '{schema_version:"1.0",event_id:$id,run_id:$run,sequence:$seq,event_type:$type,timestamp:$ts,previous_event_digest:(if $prev=="" then null else $prev end),requested:$req,observed:$obs,evidence_refs:$refs}')"
  payload="$(printf '%s' "$payload" | jq --arg digest "$(printf '%s' "$payload" | jq -cS . | sha256_file /dev/stdin)" '. + {event_digest:$digest}')"
  tmp="$events/.${id}.$$"; printf '%s\n' "$payload" > "$tmp"; mv "$tmp" "$events/${seq}.json"
}

case "$sub" in
  open)
    [[ -n "$route" && -f "$route" ]] || die "open requires --route PATH to a route artifact"
    [[ ! -e "$events/1.json" ]] || die "run already opened: $run_id"
    route_digest="$(sha256_file "$route")"
    commit_event "planned" "$(jq -n --arg digest "$route_digest" '{route_digest:$digest}')" '{"dispatch":"unobserved","completion":"not-complete"}' "$(jq -n --arg r "$route" '[{kind:"route",ref:$r}]')"
    ;;
  record)
    [[ -n "$event_type" ]] || die "record requires --type"
    refs='[]'; [[ -n "$evidence" ]] && refs="$(jq -n --arg e "$evidence" '[{kind:"evidence",ref:$e}]')"
    commit_event "$event_type" "$requested" "$observed" "$refs"
    ;;
  complete)
    [[ -f "$artifact" ]] || die "complete requires an existing --artifact"
    [[ -n "$checker" && -n "$scope" ]] || die "complete requires --checker and --scope"
    case "$verdict" in pass|fail) ;; *) die "--verdict must be pass or fail" ;; esac
    artifact_digest="$(sha256_file "$artifact")"
    # Same-maker checks cannot claim independent completion.
    independent=true; [[ "$checker" == "${EIDOLONS_LEDGER_MAKER:-}" || -z "$checker" ]] && independent=false
    complete=false; [[ "$verdict" == pass && "$independent" == true ]] && complete=true
    commit_event "checked" '{"completion":"requested"}' "$(jq -n --arg d "$artifact_digest" --arg c "$checker" --arg s "$scope" --arg v "$verdict" --argjson i "$independent" --argjson done "$complete" '{artifact_digest:$d,checker:$c,scope:$s,verdict:$v,independent:$i,completion:(if $done then "independently-verified" else "not-complete" end)}')" "$(jq -n --arg a "$artifact" '[{kind:"artifact",ref:$a}]')"
    ;;
  status)
    [[ -d "$events" ]] || die "unknown run: $run_id"
    result="$(jq -s 'sort_by(.sequence) as $e | ($e | map(select(.event_type=="planned")) | .[0]) as $plan | ($e | map(select(.event_type=="checked" and .observed.completion=="independently-verified")) | last) as $done | {run_id:($e[0].run_id),events:($e|length),requested:($plan.requested // {}),dispatch:([ $e[].observed.dispatch? | select(. != null) ] | last // "unobserved"),completion:(if $done then "independently-verified" else "not-complete" end),reconciliation_required:([ $e[].observed.side_effect? | select(. == "unknown") ] | length > 0)}' "$events"/*.json)"
    if [[ "$json" == true ]]; then printf '%s\n' "$result"; else printf '%s\n' "$result" | jq -r '"run \(.run_id): dispatch=\(.dispatch), completion=\(.completion), events=\(.events), reconciliation_required=\(.reconciliation_required)"'; fi
    ;;
esac
