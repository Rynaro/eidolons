#!/usr/bin/env bash
# eidolons ledger — append-only local observed-execution ledger (PL-03).
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_EIDOLONS_LEDGER_READ_ONLY=1
. "$SELF_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: eidolons ledger open|record|status|complete|candidate|capture|render [options]

open     --run-id ID [--route PATH]                 create a planned event
record   --run-id ID --type TYPE [--requested JSON] [--observed JSON] [--evidence PATH]
complete --run-id ID --artifact PATH --checker ID --scope TEXT --verdict pass|fail
status   --run-id ID [--json]
candidate --run-id ID --criteria PATH --integration-base REF [--event-id ID]
complete --run-id ID --candidate EVENT_ID --check-id ID --artifact PATH
         --checker LABEL --scope TEXT --verdict pass|fail|cancelled [--event-id ID]
capture  --run-id ID [--event-id ID]                  capture historical projection inputs
render   --run-id ID --event-id CAPTURE [--format json|text|markdown] [--compare PATH]
render   --reference PATH                            canonical capture reference

Writers accept --event-id ID for idempotent retries of identical content.
EIDOLONS_LEDGER_LOCK_TIMEOUT sets a 1..300 second acquisition budget (default 60).
An interrupted owner may leave a recovery-required .append-lock directory.
Never remove it until all writers and their publishing children are quiescent.

Events are committed as individual files by atomic rename.  Requested and
observed state remain separate. Manual labels are self-attested; production
independent acceptance awaits a qualified provenance source. Candidate/status/
completion/render require Python 3 (standard library). Views are historical,
never current acceptance. Raw prompts and tool payloads are absent.
EOF
}

sub="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$sub" in open|record|status|complete|candidate|capture|render) ;; -h|--help|"") usage; exit 0 ;; *) die "Unknown ledger command: $sub" ;; esac
run_id=""; event_id=""; route=""; event_type=""; requested='{}'; observed='{}'; evidence=""; artifact=""; checker=""; scope=""; verdict=""; json=false
criteria=""; integration_base=""; candidate_id=""; check_id=""; format=""; compare=""; reference=""; typed=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) run_id="${2:-}"; shift 2 ;; --route) route="${2:-}"; shift 2 ;;
    --event-id) event_id="${2:-}"; [[ -n "$event_id" ]] || die "--event-id requires a nonempty ID"; shift 2 ;;
    --type) event_type="${2:-}"; shift 2 ;; --requested) requested="${2:-}"; shift 2 ;;
    --observed) observed="${2:-}"; shift 2 ;; --evidence) evidence="${2:-}"; shift 2 ;;
    --artifact) artifact="${2:-}"; shift 2 ;; --checker) checker="${2:-}"; shift 2 ;;
    --scope) scope="${2:-}"; shift 2 ;; --verdict) verdict="${2:-}"; shift 2 ;;
    --criteria) criteria="${2:-}"; shift 2 ;; --integration-base) integration_base="${2:-}"; shift 2 ;;
    --candidate) candidate_id="${2:-}"; shift 2 ;; --check-id) check_id="${2:-}"; shift 2 ;;
    --format) format="${2:-}"; shift 2 ;; --compare) compare="${2:-}"; shift 2 ;;
    --reference) reference="${2:-}"; shift 2 ;;
    --json) json=true; shift ;; *) die "Unknown option: $1" ;;
  esac
done
completion_helper() {
  command -v python3 >/dev/null 2>&1 || die "Completion commands require Python 3; install python3 and retry. Ordinary ledger open/record remain available."
  python3 "$SELF_DIR/ledger_completion.py" "$@"
}
if [[ -n "$reference" ]]; then
  [[ "$sub" == render && -z "$run_id" && -z "$event_id" ]] || die "--reference is exclusive to render without explicit IDs"
  resolved="$(completion_helper reference --file "$reference")" || die "canonical capture reference required"
  run_id="$(printf '%s\n' "$resolved" | jq -er '.run_id')"
  event_id="$(printf '%s\n' "$resolved" | jq -er '.event_id')"
fi
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
  local type="$1" req="$2" obs="$3" refs="$4" seq id payload existing content timestamp digest prepared
  jq -es 'length == 1 and (.[0]|type == "object")' >/dev/null <<<"$req" || die "--requested must be one JSON object"
  jq -es 'length == 1 and (.[0]|type == "object")' >/dev/null <<<"$obs" || die "--observed must be one JSON object"
  jq -es 'length == 1 and (.[0]|type == "array")' >/dev/null <<<"$refs" || die "internal evidence JSON invalid"
  acquire_owner
  validate_prefix
  check_interrupted
  if [[ "$typed" == true ]]; then
    # Snapshot and retry comparison are under the same append ownership. Generate
    # volatile capture metadata only after stable caller/identity comparison.
    prepared="$(printf '%s\n' "$history" | completion_helper prepare --kind "$sub" --request "$req")" || die "typed completion capture failed"
    req="$(printf '%s\n' "$prepared" | jq -ce '.requested')"
    obs="$(printf '%s\n' "$prepared" | jq -ce '.observed')"
    refs="$(printf '%s\n' "$prepared" | jq -ce '.evidence_refs')"
  fi
  content="$(jq -cnS --arg type "$type" --argjson req "$req" --argjson obs "$obs" --argjson refs "$refs" '{event_type:$type,requested:$req,observed:$obs,evidence_refs:$refs}')" || die "journal content construction failed"
  if [[ -n "$event_id" ]]; then
    existing="$(printf '%s\n' "$history" | jq -cS --arg id "$event_id" --argjson typed "$typed" '.[] | select(.event_id == $id) | {event_type,requested,observed:(if $typed then (.observed | del(.capture)) else .observed end),evidence_refs}')" || die "journal identity lookup failed"
    if [[ -n "$existing" ]]; then
      if [[ "$sub" == complete && "$typed" == false && "$type" == checked ]]; then
        # Legacy trust labels were derived, not caller inputs. Compare the stable
        # request and evidence while returning the original event bytes on retry.
        existing="$(printf '%s\n' "$existing" | jq -cS '.observed |= del(.independent,.completion)')" || die "legacy retry comparison failed"
        content="$(printf '%s\n' "$content" | jq -cS '.observed |= del(.independent,.completion)')" || die "legacy retry comparison failed"
      fi
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
  if [[ "$typed" == true ]]; then
    obs="$(printf '%s\n' "$obs" | completion_helper decorate --timestamp "$timestamp")" || die "capture metadata failed"
  fi
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
    command -v python3 >/dev/null 2>&1 || die "Completion commands require Python 3; install python3 and retry"
    [[ -n "$checker" && -n "$scope" ]] || die "complete requires --checker and --scope"
    case "$verdict" in pass|fail|cancelled) ;; *) die "--verdict must be pass, fail, or cancelled" ;; esac
    if [[ -n "$candidate_id" || -n "$check_id" ]]; then
      [[ -n "$candidate_id" && -n "$check_id" ]] || die "typed complete requires --candidate and --check-id"
      typed=true
      requested="$(jq -cn --arg candidate "$candidate_id" --arg check "$check_id" --arg artifact "$artifact" --arg checker "$checker" --arg scope "$scope" --arg verdict "$verdict" '{candidate_event_id:$candidate,check_id:$check,artifact:$artifact,checker:$checker,scope:$scope,verdict:$verdict}')"
      commit_event "completion-check" "$requested" '{}' '[]'
      exit 0
    fi
    [[ -f "$artifact" ]] || die "complete requires an existing --artifact"
    artifact_digest="$(sha256_file "$artifact")" || die "artifact digest failed"
    [[ "$artifact_digest" =~ ^[a-f0-9]{64}$ ]] || die "artifact digest invalid"
    # Same-maker checks cannot claim independent completion.
    independent=false
    complete=false; [[ "$verdict" == pass && "$independent" == true ]] && complete=true
    observed="$(jq -n --arg d "$artifact_digest" --arg c "$checker" --arg s "$scope" --arg v "$verdict" --argjson i "$independent" --argjson done "$complete" '{artifact_digest:$d,checker:$c,scope:$s,verdict:$v,independent:$i,completion:(if $done then "independently-verified" else "not-complete" end)}')" || die "checker observation construction failed"
    refs="$(jq -n --arg a "$artifact" '[{kind:"artifact",ref:$a}]')" || die "artifact evidence construction failed"
    commit_event "checked" '{"completion":"requested"}' "$observed" "$refs"
    ;;
  candidate)
    [[ -n "$criteria" && -n "$integration_base" ]] || die "candidate requires --criteria PATH and --integration-base REF"
    typed=true
    requested="$(jq -cn --arg criteria "$criteria" --arg base "$integration_base" '{criteria:$criteria,integration_base:$base}')"
    commit_event "candidate-captured" "$requested" '{}' '[]'
    ;;
  capture)
    typed=true
    commit_event "projection-captured" '{}' '{}' '[]'
    ;;
  status|render)
    [[ ! -e "$lock" && ! -L "$lock" ]] || die "recovery-required: append ownership is unresolved for $run_id"
    [[ -d "$events" ]] || die "unknown run: $run_id"
    validate_prefix
    [[ "$count" -gt 0 ]] || die "recovery-required: run has no published events: $run_id"
    [[ ! -e "$lock" && ! -L "$lock" ]] || die "recovery-required: append ownership changed during inspection"
    helper_args=("$sub")
    if [[ "$sub" == render ]]; then
      [[ -n "$event_id" ]] || die "render requires a canonical capture --event-id"
      helper_args+=(--event-id "$event_id")
      format="${format:-json}"
    else
      format="${format:-text}"
    fi
    [[ "$json" == false ]] || format=json
    helper_args+=(--format "$format")
    [[ -z "$compare" ]] || helper_args+=(--compare "$compare")
    printf '%s\n' "$history" | completion_helper "${helper_args[@]}"
    ;;
esac
