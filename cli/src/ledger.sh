#!/usr/bin/env bash
# eidolons ledger — append-only local observed-execution ledger (PL-03).
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_EIDOLONS_LEDGER_READ_ONLY=1
. "$SELF_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: eidolons ledger open|record|status|complete [options]

open     --run-id ID [--route PATH]                 create a planned event
record   --run-id ID --type TYPE [--requested JSON] [--observed JSON] [--evidence PATH]
complete --run-id ID --artifact PATH --checker ID --scope TEXT --verdict pass|fail
status   --run-id ID [--json]

Writers accept --event-id ID for idempotent retries of identical content.
EIDOLONS_LEDGER_LOCK_TIMEOUT sets a 1..300 second acquisition budget (default 60).
An interrupted owner may leave a recovery-required .append-lock directory.
Never remove it until all writers and their publishing children are quiescent.

Events are committed as individual files by atomic rename.  Requested and
observed state remain separate; completion requires an independent passing
checker linked to an artifact digest. Raw prompts and tool payloads are absent.
EOF
}

sub="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$sub" in open|record|status|complete) ;; -h|--help|"") usage; exit 0 ;; *) die "Unknown ledger command: $sub" ;; esac
run_id=""; event_id=""; route=""; event_type=""; requested='{}'; observed='{}'; evidence=""; artifact=""; checker=""; scope=""; verdict=""; json=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) run_id="${2:-}"; shift 2 ;; --route) route="${2:-}"; shift 2 ;;
    --event-id) event_id="${2:-}"; [[ -n "$event_id" ]] || die "--event-id requires a nonempty ID"; shift 2 ;;
    --type) event_type="${2:-}"; shift 2 ;; --requested) requested="${2:-}"; shift 2 ;;
    --observed) observed="${2:-}"; shift 2 ;; --evidence) evidence="${2:-}"; shift 2 ;;
    --artifact) artifact="${2:-}"; shift 2 ;; --checker) checker="${2:-}"; shift 2 ;;
    --scope) scope="${2:-}"; shift 2 ;; --verdict) verdict="${2:-}"; shift 2 ;;
    --json) json=true; shift ;; *) die "Unknown option: $1" ;;
  esac
done
[[ "$run_id" =~ ^[A-Za-z0-9._-]+$ ]] || die "--run-id must contain only letters, digits, dot, underscore, or dash"
[[ "$run_id" != . && "$run_id" != .. ]] || die "--run-id cannot be dot or dot-dot"
root=".eidolons/.ledger/$run_id"; events="$root/events"; lock="$root/.append-lock"

# Full v1 prefixes remain the authority; neither counts nor cached digests are
# trusted. Capture one immutable published prefix and verify every member.
history='[]'; count=0; previous=""
journal_sha() {
  local digest
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum)" || return 1
    digest="${digest%% *}"
  else
    digest="$(sha256_file /dev/stdin)" || return 1
  fi
  [[ "$digest" =~ ^[a-f0-9]{64}$ ]] || return 1
  printf '%s\n' "$digest"
}

validate_prefix() {
  local file index stream expected canonical actual
  local files=()
  shopt -s nullglob dotglob
  files=("$events"/*)
  shopt -u nullglob dotglob
  count=${#files[@]}; history='[]'; previous=""
  [[ "$count" -gt 0 ]] || return 0
  for file in "${files[@]}"; do
    [[ -f "$file" && ! -L "$file" && "${file##*/}" =~ ^[1-9][0-9]*\.json$ ]] || die "recovery-required: unexpected journal entry: $file"
  done
  for ((index=1; index<=count; index++)); do
    [[ -f "$events/$index.json" ]] || die "invalid journal: missing numeric sequence $index"
  done
  history="$(jq -es --arg run "$run_id" --argjson count "$count" '
    sort_by(.sequence) as $e |
    if ($e|length) != $count then error("one event per file required")
    elif any($e[]; .schema_version != "1.0") then error("unsupported journal version")
    elif any($e[];
      (type != "object") or
      ((keys - ["schema_version","event_id","run_id","sequence","event_type","timestamp","previous_event_digest","requested","observed","evidence_refs","event_digest"])|length > 0) or
      (.run_id != $run) or (.event_id|type != "string") or (.event_id == "") or
      (.event_type|type != "string") or (.timestamp|type != "string") or
      (.requested|type != "object") or (.observed|type != "object") or
      (.evidence_refs|type != "array") or (.event_digest|type != "string") or
      (.event_digest|test("^[a-f0-9]{64}$")|not)) then error("invalid event shape")
    elif ($e|map(.event_id)|unique|length) != $count then error("duplicate event identity")
    elif any(range(0;$count); . as $i |
      ($e[$i].sequence != ($i+1)) or
      ($e[$i].previous_event_digest != (if $i == 0 then null else $e[$i-1].event_digest end)))
      then error("invalid sequence or predecessor")
    else $e end' "${files[@]}")" || die "invalid journal: published prefix rejected"
  # -cS applies to each payload object, before hashing its mandatory final LF.
  stream="$(printf '%s\n' "$history" | jq -cS '.[] | .event_digest, del(.event_digest)')" || die "invalid journal canonicalization"
  while IFS= read -r expected && IFS= read -r canonical; do
    expected="${expected#\"}"; expected="${expected%\"}"
    actual="$(printf '%s\n' "$canonical" | journal_sha)" || die "journal digest failed"
    [[ "$actual" == "$expected" ]] || die "invalid journal: event digest mismatch"
    previous="$expected"
  done <<< "$stream"
  # A valid sequence in the wrong filename must not be accepted for appending.
  for ((index=1; index<=count; index++)); do
    jq -e --argjson seq "$index" '.sequence == $seq' "$events/$index.json" >/dev/null || die "invalid journal: filename/sequence mismatch"
  done
}

owned=false; owner=""; interrupted=0
cleanup_owner() {
  local result=$? actual_owner
  # Foreground publisher commands have completed before Bash executes EXIT.
  # Ignore further catchable signals while removing only our own metadata.
  trap '' HUP INT TERM
  if [[ "$owned" == true && -f "$lock/owner" && ! -L "$lock/owner" ]]; then
    actual_owner="$(cat "$lock/owner")" || return "$result"
    if [[ "$actual_owner" == "$owner" ]]; then
      rm -f "$lock/event" "$lock/owner"
      rmdir "$lock" 2>/dev/null || true
    fi
  fi
  return "$result"
}

check_interrupted() {
  [[ "$interrupted" -eq 0 ]] || exit "$interrupted"
}

acquire_owner() {
  local timeout="${EIDOLONS_LEDGER_LOCK_TIMEOUT:-60}" started
  [[ "$timeout" =~ ^[1-9][0-9]{0,2}$ ]] && [[ "$timeout" -le 300 ]] || die "EIDOLONS_LEDGER_LOCK_TIMEOUT must be an integer from 1 to 300"
  mkdir -p "$events"
  trap cleanup_owner EXIT
  # Signal handlers only mark interruption. In particular, the foreground mv
  # child must finish before we exit and release ownership. SIGKILL leaves the
  # lock in place even if the publishing child outlives this shell.
  trap 'interrupted=129' HUP
  trap 'interrupted=130' INT
  trap 'interrupted=143' TERM
  started=$SECONDS
  until mkdir "$lock" 2>/dev/null; do
    check_interrupted
    [[ $((SECONDS-started)) -lt "$timeout" ]] || die "recovery-required: append ownership unavailable for $run_id; establish writer quiescence before manual recovery"
    sleep 0.1
  done
  # Death before metadata publication deliberately leaves ambiguous ownership.
  owner="$(printf 'pid=%s\ntoken=%s-%s-%s' "$$" "$$" "$RANDOM" "$RANDOM")"
  printf '%s\n' "$owner" > "$lock/owner"
  owned=true
  check_interrupted
}

commit_event() {
  local type="$1" req="$2" obs="$3" refs="$4" seq id payload existing content timestamp digest
  jq -es 'length == 1 and (.[0]|type == "object")' >/dev/null <<<"$req" || die "--requested must be one JSON object"
  jq -es 'length == 1 and (.[0]|type == "object")' >/dev/null <<<"$obs" || die "--observed must be one JSON object"
  jq -es 'length == 1 and (.[0]|type == "array")' >/dev/null <<<"$refs" || die "internal evidence JSON invalid"
  acquire_owner
  validate_prefix
  check_interrupted
  content="$(jq -cnS --arg type "$type" --argjson req "$req" --argjson obs "$obs" --argjson refs "$refs" '{event_type:$type,requested:$req,observed:$obs,evidence_refs:$refs}')" || die "journal content construction failed"
  if [[ -n "$event_id" ]]; then
    existing="$(printf '%s\n' "$history" | jq -cS --arg id "$event_id" '.[] | select(.event_id == $id) | {event_type,requested,observed,evidence_refs}')" || die "journal identity lookup failed"
    if [[ -n "$existing" ]]; then
      [[ "$existing" == "$content" ]] || die "event identity conflict: $event_id"
      return 0
    fi
  fi
  [[ "$sub" != open || "$count" -eq 0 ]] || die "run already opened: $run_id"
  seq=$((count + 1)); id="${event_id:-${run_id}-${seq}}"
  # A supplied identity can overlap a future generated default; never duplicate it.
  existing="$(printf '%s\n' "$history" | jq -r --arg id "$id" 'any(.[]; .event_id == $id)')" || die "journal identity lookup failed"
  if [[ "$existing" == true ]]; then
    die "event identity conflict: $id; supply a distinct --event-id"
  fi
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || die "journal timestamp failed"
  payload="$(jq -n --arg id "$id" --arg run "$run_id" --arg type "$type" --arg ts "$timestamp" --arg prev "$previous" --argjson seq "$seq" --argjson req "$req" --argjson obs "$obs" --argjson refs "$refs" '{schema_version:"1.0",event_id:$id,run_id:$run,sequence:$seq,event_type:$type,timestamp:$ts,previous_event_digest:(if $prev=="" then null else $prev end),requested:$req,observed:$obs,evidence_refs:$refs}')" || die "journal event construction failed"
  # Command substitutions inside jq arguments hide their exit status. Check
  # hashing separately before constructing or publishing the signed event.
  digest="$(printf '%s' "$payload" | jq -cS . | journal_sha)" || die "journal digest failed"
  [[ "$digest" =~ ^[a-f0-9]{64}$ ]] || die "journal digest invalid"
  payload="$(printf '%s' "$payload" | jq --arg digest "$digest" '. + {event_digest:$digest}')" || die "journal event construction failed"
  printf '%s\n' "$payload" > "$lock/event"
  check_interrupted
  [[ ! -e "$events/$seq.json" ]] || die "invalid journal: publication target already exists"
  mv "$lock/event" "$events/$seq.json"
  check_interrupted
}

case "$sub" in
  open)
    [[ -n "$route" && -f "$route" ]] || die "open requires --route PATH to a route artifact"
    route_digest="$(sha256_file "$route")" || die "route digest failed"
    [[ "$route_digest" =~ ^[a-f0-9]{64}$ ]] || die "route digest invalid"
    requested="$(jq -n --arg digest "$route_digest" '{route_digest:$digest}')" || die "route request construction failed"
    refs="$(jq -n --arg r "$route" '[{kind:"route",ref:$r}]')" || die "route evidence construction failed"
    commit_event "planned" "$requested" '{"dispatch":"unobserved","completion":"not-complete"}' "$refs"
    ;;
  record)
    [[ -n "$event_type" ]] || die "record requires --type"
    refs='[]'
    if [[ -n "$evidence" ]]; then
      refs="$(jq -n --arg e "$evidence" '[{kind:"evidence",ref:$e}]')" || die "evidence construction failed"
    fi
    commit_event "$event_type" "$requested" "$observed" "$refs"
    ;;
  complete)
    [[ -f "$artifact" ]] || die "complete requires an existing --artifact"
    [[ -n "$checker" && -n "$scope" ]] || die "complete requires --checker and --scope"
    case "$verdict" in pass|fail) ;; *) die "--verdict must be pass or fail" ;; esac
    artifact_digest="$(sha256_file "$artifact")" || die "artifact digest failed"
    [[ "$artifact_digest" =~ ^[a-f0-9]{64}$ ]] || die "artifact digest invalid"
    # Same-maker checks cannot claim independent completion.
    independent=true; [[ "$checker" == "${EIDOLONS_LEDGER_MAKER:-}" || -z "$checker" ]] && independent=false
    complete=false; [[ "$verdict" == pass && "$independent" == true ]] && complete=true
    observed="$(jq -n --arg d "$artifact_digest" --arg c "$checker" --arg s "$scope" --arg v "$verdict" --argjson i "$independent" --argjson done "$complete" '{artifact_digest:$d,checker:$c,scope:$s,verdict:$v,independent:$i,completion:(if $done then "independently-verified" else "not-complete" end)}')" || die "checker observation construction failed"
    refs="$(jq -n --arg a "$artifact" '[{kind:"artifact",ref:$a}]')" || die "artifact evidence construction failed"
    commit_event "checked" '{"completion":"requested"}' "$observed" "$refs"
    ;;
  status)
    [[ ! -e "$lock" && ! -L "$lock" ]] || die "recovery-required: append ownership is unresolved for $run_id"
    [[ -d "$events" ]] || die "unknown run: $run_id"
    validate_prefix
    [[ "$count" -gt 0 ]] || die "recovery-required: run has no published events: $run_id"
    [[ ! -e "$lock" && ! -L "$lock" ]] || die "recovery-required: append ownership changed during inspection"
    result="$(printf '%s\n' "$history" | jq '. as $e | ($e | map(select(.event_type=="planned")) | .[0]) as $plan | ($e | map(select(.event_type=="checked" and .observed.completion=="independently-verified")) | last) as $done | {run_id:($e[0].run_id),events:($e|length),requested:($plan.requested // {}),dispatch:([ $e[].observed.dispatch? | select(. != null) ] | last // "unobserved"),completion:(if $done then "independently-verified" else "not-complete" end),reconciliation_required:([ $e[].observed.side_effect? | select(. == "unknown") ] | length > 0)}')"
    if [[ "$json" == true ]]; then printf '%s\n' "$result"; else printf '%s\n' "$result" | jq -r '"run \(.run_id): dispatch=\(.dispatch), completion=\(.completion), events=\(.events), reconciliation_required=\(.reconciliation_required)"'; fi
    ;;
esac
