#!/usr/bin/env bash
# Product Leap opt-in surfaces for capsules, bounded local recall, evidence,
# policy shadowing, and a deliberately disabled ACP negotiation pilot.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$SELF_DIR/lib.sh"
usage(){ echo "Usage: eidolons augment capsule|recall|evidence|policy|acp ..."; }
sub="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$sub" in capsule|recall|evidence|policy|acp) ;; *) usage; exit 2;; esac
root=".eidolons/.product-leap"; mkdir -p "$root"
case "$sub" in
capsule)
  op="${1:-}"; [[ $# -gt 0 ]] && shift || true; case "$op" in export|preview) ;; *) die "capsule export|preview";; esac
  file=""; task=""; checkpoint=""; ledger=""; while [[ $# -gt 0 ]]; do case "$1" in --file) file="${2:-}"; shift 2;; --task-id) task="${2:-}"; shift 2;; --checkpoint) checkpoint="${2:-}"; shift 2;; --ledger) ledger="${2:-}"; shift 2;; *) die "unknown option: $1";; esac; done
  [[ -n "$file" ]] || die "--file required"
  if [[ "$op" == export ]]; then
    [[ "$file" != /* && "$file" != *".."* ]] || die "capsule path must be relative and non-traversing"
    jq -n --arg id "capsule-$(date +%s)-$$" --arg task "$task" --arg cp "$checkpoint" --arg led "$ledger" '{schema_version:"1.0",capsule_id:$id,task_id:$task,authority:{source:"task-contract",operations:["read"]},checkpoint_ref:(if $cp=="" then null else $cp end),ledger_cursor:(if $led=="" then null else $led end),artifacts:[],pending_checks:[],side_effects:[],required_capabilities:[],secrets:"excluded",migration_history:[]}' > "$file.$$.tmp"; mv "$file.$$.tmp" "$file"; echo "$file"
  else
    [[ -f "$file" ]] || die "capsule missing"; jq -e '.schema_version=="1.0" and (.secrets=="excluded") and ([.artifacts[]?.ref? | select(startswith("/") or contains(".."))]|length==0)' "$file" >/dev/null || die "invalid or unsafe capsule"; jq '{capsule_id,task_id,checkpoint_ref,ledger_cursor,required_capabilities,side_effects,compatible:true}' "$file"
  fi;;
recall)
  # Local records only: no record is authority and caps are mechanically enforced.
  op="${1:-}"; [[ $# -gt 0 ]] && shift || true; store="$root/recall.jsonl"; case "$op" in add|list|invalidate) ;; *) die "recall add|list|invalidate";; esac
  if [[ "$op" == add ]]; then origin=""; text=""; while [[ $# -gt 0 ]]; do case "$1" in --origin) origin="${2:-}"; shift 2;; --text) text="${2:-}"; shift 2;; *) die "unknown option";; esac; done; [[ -n "$text" ]] || die "--text required"; jq -n --arg id "recall-$(date +%s)-$$" --arg o "$origin" --arg t "$text" '{schema_version:"1.0",record_id:$id,origin:$o,text:$t,trust:"untrusted",validity:"active",token_estimate:($t|length/4|floor),authority:"none"}' >> "$store"
  elif [[ "$op" == invalidate ]]; then id="${1:-}"; [[ -n "$id" ]] || die "record id required"; jq -s --arg id "$id" 'map(if .record_id==$id then .validity="stale" else . end)[]' "$store" > "$store.$$.tmp"; mv "$store.$$.tmp" "$store"
  else [[ -f "$store" ]] || { echo '[]'; exit 0; }; jq -s '[.[]|select(.validity=="active")]|sort_by(.token_estimate)|.[0:5] | reduce .[] as $r ({records:[],tokens:0}; if (.tokens+$r.token_estimate)<=1200 then .records += [$r + {selection_reason:"bounded-local-recall"}] | .tokens += $r.token_estimate else . end)' "$store"; fi;;
evidence)
  # Replay reports are evidence-only; unknown/infrastructure never passes.
  file="${1:-}"; [[ -f "$file" ]] || die "evidence requires JSON observations file"; jq -e 'type=="array" and all(.[]; (.status|IN("pass","fail","unknown","infrastructure","timeout","authority_violation")))' "$file" >/dev/null || die "invalid evidence status"; jq -s '{schema_version:"1.0",run_id:("eval-"+(now|floor|tostring)),outcomes:.,comparative_conclusion:(if all(.[];.status=="pass") then "eligible-for-review" else "blocked-incomplete-or-failed" end)}' "$file";;
policy)
  candidate="${1:-}"; [[ -f "$candidate" ]] || die "policy requires candidate JSON"; jq -e '(.allowed_parameter_diff|type)=="array" and ([.allowed_parameter_diff[] | select(IN("thresholds","topology")|not)]|length==0) and (.recall_policy // "pinned")=="pinned"' "$candidate" >/dev/null || die "candidate changes a protected policy field"; jq '{mode:"shadow-only",candidate_id,base_policy_digest,allowed_parameter_diff,recall_policy}' "$candidate";;
acp)
  # No listener, no network, no startup dependency. Only explicit compatibility receipt.
  version="${1:-}"; caps="${2:-[]}"; [[ "$version" == "1" ]] || { jq -n --arg v "$version" '{supported:false,reason:"unsupported ACP version",version:$v}'; exit 3; }; jq -e 'type=="array"' <<< "$caps" >/dev/null || die "capabilities must be JSON array"; jq -n --argjson c "$caps" '{supported:true,protocol:"ACP/1",capabilities:$c,unsupported:["session-load","remote-agent"],network:"disabled"}';;
esac
