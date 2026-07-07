#!/usr/bin/env bash
# eidolons run — mechanical routing kernel
# ═══════════════════════════════════════════════════════════════════════════
# Converts the cortex Dispatch Protocol (EIDOLONS.md Steps 1–5) from
# host-LLM-interpreted prose into a DETERMINISTIC, table-driven decision over
# roster/routing.yaml. No LLM, no eval (I-C2), bash 3.2 safe, stderr-disciplined.
#
# Same prompt + same routing data ⇒ same routing artifact (I-C6). The kernel
# mechanically enforces: refusal immutability (a refused intent never dispatches
# to the refuser), tau thresholds, chain selection, and TRANCE-never-default.
#
# Acceptance criteria: methodology/cortex/validation-gates.md V1–V14.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

ROUTING_FILE="$(dirname "$ROSTER_FILE")/routing.yaml"

usage() {
  cat <<EOF
eidolons run — deterministically route a prompt to the correct Eidolon(s)

Usage: eidolons run "<prompt>" [OPTIONS]

Mechanically applies the cortex Dispatch Protocol over roster/routing.yaml
(no LLM): classify → gate → refusal-check → tier → emit routing artifact.

Options:
  --json                 Emit the routing artifact as JSON
  --explain              Show the per-Eidolon score table (to stderr)
  --surface-files N      Declare the surface size (large-surface complexity flag)
  --surface-modules N    Declare module count (large-surface complexity flag)
  --trance               Supply the explicit TRANCE token (stakes flag input)
  --prior-failure        Mark a prior APIVR-Δ Reflect-exhaustion this turn
  --verify <envelope>    Verify an incoming ECL hand-off envelope BEFORE routing
                         (mechanical SHA-256 gate; records the verdict on the
                         artifact). In block mode a failure refuses to route.
  --verify-block         Run the --verify gate in block mode (ECL §6.2.2)
  --hook <host> --post-tool-use
                         ECM P1 meter-refresh hook mode (harness-internal):
                         reads the PostToolUse event JSON on stdin, refreshes
                         .eidolons/.context/meter.json, and injects
                         additionalContext ONLY on a zone transition.
  -h, --help             Show this help

Tiers: 'standard' is always the default. 'trance' is emitted only when a
complexity flag AND a stakes flag both hold (never automatic).

Examples:
  eidolons run "map the auth flow"
  eidolons run "ATLAS, please patch this file"          # → refusal reroute
  eidolons run "design and implement the --json flag"   # → SPECTRA → APIVR-Δ
  eidolons run "map the entire monorepo" --surface-modules 9 --trance
EOF
}

PROMPT=""
OUT="text"
EXPLAIN=0
SURFACE_FILES=0
SURFACE_MODULES=0
TRANCE_TOKEN=false
PRIOR_FAILURE=false
VERIFY_ENVELOPE=""
VERIFY_MODE="${EIDOLONS_ECL_VERIFY_MODE:-warn}"
HOOK_HOST=""
HOOK_SESSION_START=false
HOOK_STDIN=false
HOOK_POST_TOOL_USE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)            OUT="json"; shift ;;
    --explain)         EXPLAIN=1; shift ;;
    --surface-files)   SURFACE_FILES="${2:-0}"; shift 2 ;;
    --surface-modules) SURFACE_MODULES="${2:-0}"; shift 2 ;;
    --trance)          TRANCE_TOKEN=true; shift ;;
    --prior-failure)   PRIOR_FAILURE=true; shift ;;
    --verify)          VERIFY_ENVELOPE="${2:-}"; shift 2 ;;
    --verify-block)    VERIFY_MODE="block"; shift ;;
    --hook)            HOOK_HOST="${2:-}"; shift 2 ;;
    --session-start)   HOOK_SESSION_START=true; shift ;;
    --stdin)           HOOK_STDIN=true; shift ;;
    --post-tool-use)   HOOK_POST_TOOL_USE=true; shift ;;
    -h|--help)         usage; exit 0 ;;
    --)                shift; PROMPT="${PROMPT}${PROMPT:+ }$*"; break ;;
    -*)                die "Unknown option: $1 (see 'eidolons run --help')" ;;
    *)                 PROMPT="${PROMPT}${PROMPT:+ }$1"; shift ;;
  esac
done

# ── Hook: session-start mode (no prompt required) ──────────────────────────
if [[ -n "$HOOK_HOST" && "$HOOK_SESSION_START" == "true" ]]; then
  export HOOK_HOST HOOK_MODE="session_start" HOOK_EVENT_NAME="SessionStart"
  export ARTIFACT_JSON="" PROMPT HOOK_STDIN_INPUT=""
  bash "$SELF_DIR/harness_hook.sh"
  exit 0
fi

# ── Hook: PostToolUse mode (ECM P1, T-F) — meter refresh; inject only on a
# zone transition (evidence C6). No prompt required; reads the tool-call
# event JSON on stdin and hands it to harness_hook.sh untouched. ─────────────
if [[ -n "$HOOK_HOST" && "$HOOK_POST_TOOL_USE" == "true" ]]; then
  _ptu_stdin="$(cat 2>/dev/null || true)"
  export HOOK_HOST HOOK_MODE="post_tool_use" HOOK_EVENT_NAME="PostToolUse"
  export ARTIFACT_JSON="" PROMPT="" HOOK_STDIN_INPUT="$_ptu_stdin"
  bash "$SELF_DIR/harness_hook.sh"
  exit 0
fi

# ── Hook: stdin mode — read prompt from event JSON on stdin ───────────────
HOOK_STDIN_INPUT=""
if [[ -n "$HOOK_HOST" && "$HOOK_STDIN" == "true" ]]; then
  HOOK_STDIN_INPUT="$(cat 2>/dev/null || true)"
  if command -v jq >/dev/null 2>&1 && [[ -n "$HOOK_STDIN_INPUT" ]]; then
    _stdin_prompt="$(printf '%s' "$HOOK_STDIN_INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)"
    if [[ -n "$_stdin_prompt" ]]; then
      PROMPT="$_stdin_prompt"
    fi
  fi
  # R21 / #16952 kernel backstop: skip routing when the extracted prompt is a
  # task-completion notification. Defense-in-depth — primary guard is the UPS shim;
  # this protects a directly-invoked kernel call. Conservative, fail-open heuristic.
  case "$PROMPT" in
    "Agent "*" completed"*) exit 0 ;;
    *"<task-notification>"*) exit 0 ;;
  esac
fi

if [[ -z "${PROMPT// }" ]]; then
  if [[ -n "$HOOK_HOST" ]]; then
    # Hook mode with no prompt — silently exit 0 (fail-open).
    exit 0
  fi
  die "No prompt given. Usage: eidolons run \"<prompt>\""
fi

[[ -f "$ROUTING_FILE" ]] || die "Routing data not found: $ROUTING_FILE"

# ── ECL verification pre-step (roadmap #2) ────────────────────────────────────
# When --verify <envelope> is given, mechanically verify the incoming hand-off
# BEFORE routing. In block mode a tamper/integrity failure refuses to route at
# all (ECL §6.2.2 enforced at the orchestration layer); in warn mode the verdict
# is recorded on the artifact but routing proceeds.
VERIFY_VERDICT=""
if [[ -n "$VERIFY_ENVELOPE" ]]; then
  # `|| _vrc=$?` keeps `set -e` from exiting on a block-mode failure (exit 3)
  # before we can act on the verdict.
  _vrc=0
  _vjson="$(bash "$SELF_DIR/verify_envelope.sh" "$VERIFY_ENVELOPE" --mode "$VERIFY_MODE" --json 2>/dev/null)" || _vrc=$?
  VERIFY_VERDICT="$(printf '%s' "$_vjson" | jq -r '.verdict // "error"' 2>/dev/null || echo "error")"
  if [[ "$_vrc" -eq 3 ]]; then
    # Exit 3 mirrors the verify gate's "blocked" code (not die's generic 1).
    warn "ecl verify blocked [$VERIFY_VERDICT]: refusing to route a hand-off that fails integrity ($VERIFY_ENVELOPE). Correct the upstream artifact or re-run in warn mode."
    exit 3
  fi
fi

ROUTING_JSON="$(yaml_to_json "$ROUTING_FILE")"

# Read the project manifest's host_tier declaration (S1.7 / G1).
# Default null (conservative) when the field is absent or the manifest is missing.
_HOST_TIER=null
if [[ -f "$PROJECT_MANIFEST" ]]; then
  _HOST_TIER="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null \
    | jq -r '.host_tier // "null"' 2>/dev/null || echo "null")"
  # Normalise the string "null" that jq emits for missing fields to a JSON null.
  if [[ "$_HOST_TIER" = "null" ]]; then
    _HOST_TIER=null
  else
    _HOST_TIER="\"${_HOST_TIER}\""
  fi
fi

# Lowercase the prompt for deterministic, case-insensitive matching (bash 3.2:
# use tr, not ${var,,}).
PROMPT_LC="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')"

CTX_JSON="$(jq -n \
  --argjson sf "${SURFACE_FILES:-0}" \
  --argjson sm "${SURFACE_MODULES:-0}" \
  --argjson tt "$TRANCE_TOKEN" \
  --argjson pf "$PRIOR_FAILURE" \
  --argjson ht "${_HOST_TIER}" \
  '{surface_files:$sf, surface_modules:$sm, trance_token:$tt, prior_failure:$pf, host_tier:$ht}')"

# ── The routing program (deterministic; mirrors EIDOLONS.md Steps 1–5) ─────────
read -r -d '' ROUTE_JQ <<'JQ' || true
# WORD-BOUNDARY match: "map" must NOT match "flowmap", "patch" not "dispatch".
# Trigger/refuse/signal phrases in routing.yaml must be plain words (no regex
# metacharacters); they are matched as \bphrase\b against the lowercased prompt.
def hasword($p; $t): ($p | test("\\b" + $t + "\\b"));
. as $R
| $R.thresholds as $T
| ($R.eidolons | to_entries) as $entries
# Step 1 — classify: count distinct trigger phrases per Eidolon; flag named.
| ($entries | map(
    .key as $nm | .value as $v
    | { name: $nm,
        class: $v.capability_class,
        default_for_class: ($v.default_for_class // null),
        model_tier: ($v.suggested_tier // $v.model_tier // "standard"),
        downstream: ($v.downstream // []),
        refuse: ($v.refuse_verbs // []),
        raw: ([ $v.trigger_verbs[] | select(. as $t | hasword($prompt; $t)) ] | length),
        named: hasword($prompt; $nm) })) as $s0
# base curve + explicit-name bonus
| ($s0 | map(. + {
    base: ((if .raw==0 then 0 elif .raw==1 then 0.8 elif .raw==2 then 0.9 else 0.97 end)
           + (if .named then 0.5 else 0 end))
  })) as $s1
# Step 1b — confidence signals (+ --prior-failure context).
| ([ $R.signals[]
     | select((.match as $m | any($m[]; . as $mp | hasword($prompt; $mp)))
              or (.id == "prior_apivr_failure" and $ctx.prior_failure)) ]) as $fired
| (([ $fired[] | .boost | to_entries[] ]
     | group_by(.key)
     | map({key: .[0].key, value: (map(.value) | add)})
     | from_entries)) as $boost
| ($s1 | map(. + { score: (.base + ($boost[.name] // 0)) })) as $scored
| ($scored | sort_by(-.score)) as $ranked
# default_for_class tiebreak (V15): among members tied at the TOP score (e.g. two
# `coder`s — Vivi as default + APIVR-Δ as the conservative fallback), prefer the
# one whose default_for_class matches its capability class. A NAMED member already
# wins via the +0.5 name bonus, so "APIVR-Δ, implement X" still routes to APIVR-Δ.
# No-op when no member declares default_for_class (the single-coder live roster).
# S1.7 host-gate: when the default_for_class winner declares requires_host_tier
# and the project's host_tier does NOT match it, fall through to the next-ranked
# candidate (the conservative coder). A NAMED member still wins via the name bonus
# (gate only governs the implicit default pick). Default unset → conservative.
| ($ranked[0].score) as $maxscore
| ([ $ranked[] | select(.score == $maxscore) ]) as $tied
| (($tied | map(select(.default_for_class == .class)) | .[0]) // $ranked[0]) as $dflt_top
| ($R.eidolons[$dflt_top.name].requires_host_tier // null) as $rht
| (($rht != null) and ($rht != $ctx.host_tier) and ($dflt_top.named | not)) as $gate_triggered
# S1.7b (Wave-2): when the gate triggers, prefer the winner's DECLARED fallback
# (routing.yaml `fallback: <peer>` — I-C2 DATA, no eval) over the generic
# next-ranked candidate, provided the peer is a known, non-refusing Eidolon.
# Falls back to the pre-existing next-ranked behavior when the key is absent,
# the peer is unknown, or the peer itself would refuse this prompt.
| ($R.eidolons[$dflt_top.name].fallback // null) as $declared_fallback_name
| (if $declared_fallback_name != null
   then ([ $ranked[] | select(.name == $declared_fallback_name) ] | .[0])
   else null end) as $declared_fallback_entry
| ($declared_fallback_entry != null
   and (($declared_fallback_entry.refuse | any(. as $r | hasword($prompt; $r))) | not)) as $declared_fallback_usable
| (if $gate_triggered
   then (if $declared_fallback_usable
         then $declared_fallback_entry
         else ([ $ranked[] | select((.name != $dflt_top.name) and (.score >= ($maxscore * 0.99))) ] | .[0]) // $dflt_top
         end)
   else $dflt_top
   end) as $top
# fallthrough_reason: null when the gate never triggered; "declared-fallback"
# when routed via the winner's declared peer; "host-tier-fallthrough" for the
# pre-existing generic next-ranked behavior (gate triggered, no usable peer).
| (if $gate_triggered
   then (if $declared_fallback_usable then "declared-fallback" else "host-tier-fallthrough" end)
   else null
   end) as $fallthrough_reason
| [ $ranked[] | select(.score >= $T.chain_floor) ] as $contenders
| ([ $contenders[] | .class ] | unique) as $classes
# Step 4 inputs — flags. Stakes = a stakes-marked signal OR explicit TRANCE token.
| (($fired | any(.stakes == true)) or ($ctx.trance_token == true)) as $stakes
| (($ctx.surface_files >= $T.surface_files)
   or ($ctx.surface_modules >= $T.surface_modules)
   or ($ctx.trance_token == true)) as $complexity
# Chain template — only when ≥2 capability classes co-trigger AND a template's
# requires_classes ⊆ present classes (most specific wins); else null.
| (if ($classes | length) >= 2
   then ([ $R.chains[]
           | select([.requires_classes[] | . as $c | ($classes | index($c))] | all)
           | . + {spec: (.requires_classes | length)} ]
         | sort_by(-.spec) | if length > 0 then .[0] else null end)
   else null end) as $chain
# Step 3 — refusal immutability: a NAMED Eidolon that refuses (V11) OR the top
# Eidolon refusing reroutes to the highest-scoring NON-refusing Eidolon.
| ([ $scored[] | select(.named and (.refuse | any(. as $r | hasword($prompt; $r)))) ]
   | if length > 0 then .[0] else null end) as $named_refuser
| ($top.refuse | any(. as $r | hasword($prompt; $r))) as $top_refuses
| (if ($named_refuser != null or $top_refuses)
   then ([ $ranked[] | select((.refuse | any(. as $r | hasword($prompt; $r))) | not) ]
         | if length > 0 then .[0] else null end)
   else null end) as $reroute
| ($named_refuser // $top) as $refuser
# Step 2 — gate + Step 5 — emit. Priority: chain → refusal-reroute → dispatch
# → clarify. Chain only fires when a template actually matched (else a 2-class
# co-trigger falls through to a single dispatch of the strongest).
| (if $chain != null
   then { decision: "chain",
          selected: $chain.steps,
          chain: [ $chain.steps[] as $st | ($R.eidolons[$st]) as $e
                   | {eidolon:$st, role:$e.capability_class, edge_origin:"routing", template:$chain.name} ],
          model_tier_per_step: [ $chain.steps[] as $st
                                  | ($R.eidolons[$st].suggested_tier // $R.eidolons[$st].model_tier // "standard") ],
          degraded_mode_per_step: [ $chain.steps[] as $st | ($R.eidolons[$st].degraded_mode // null) ],
          escalation: ($R.eidolons[$chain.steps[0]].escalation // null),
          fallthrough_reason: null,
          confidence: ([ $contenders[].score ] | min | if . > 1 then 1 else . end),
          clarification_request: null,
          refusal_rerouting: false,
          assumptions: ["chain selected by template '\($chain.name)': " + $chain.when] }
   elif ($reroute != null and $reroute.name != $refuser.name)
   then  # refusal reroute (V11): named/top Eidolon refuses → capable peer
     { decision: "refusal_reroute",
       selected: [$reroute.name],
       chain: [{eidolon:$reroute.name, role:$reroute.class, edge_origin:"routing"}],
       model_tier_per_step: [$reroute.model_tier],
       degraded_mode: ($R.eidolons[$reroute.name].degraded_mode // null),
       escalation: ($R.eidolons[$reroute.name].escalation // null),
       fallthrough_reason: $fallthrough_reason,
       confidence: ($reroute.score | if . > 1 then 1 else . end),
       clarification_request: null,
       refusal_rerouting: true,
       assumptions: ["[DECISION] \($refuser.name) would refuse this intent; rerouted to \($reroute.name)"] }
   elif $top.score >= $T.tau_standard
   then  # single dispatch (V1, V4, V6, V9)
     { decision: "dispatch",
       selected: [$top.name],
       chain: [{eidolon:$top.name, role:$top.class, edge_origin:"routing"}],
       model_tier_per_step: [$top.model_tier],
       degraded_mode: ($R.eidolons[$top.name].degraded_mode // null),
       escalation: ($R.eidolons[$top.name].escalation // null),
       fallthrough_reason: $fallthrough_reason,
       confidence: ($top.score | if . > 1 then 1 else . end),
       clarification_request: null,
       refusal_rerouting: false,
       assumptions: [] }
   else  # abstain (V12)
     { decision: "clarify",
       selected: [],
       chain: [],
       model_tier_per_step: [],
       degraded_mode: null,
       escalation: null,
       fallthrough_reason: $fallthrough_reason,
       confidence: ($top.score | if . > 1 then 1 else . end),
       clarification_request: "No Eidolon scored ≥ \($T.tau_standard). Clarify: (1) read-only or write? (2) which file/area? (3) decision, build, or debug?",
       refusal_rerouting: false,
       assumptions: ["below tau_standard; not dispatching"] }
   end) as $base
# Step 4 — tier. Default standard. TRANCE only when complexity AND stakes hold,
# and never for a clarify/empty selection.
| ($base + {
    tier: (if ($complexity and $stakes and (($base.selected | length) > 0)) then "trance" else "standard" end)
  }) as $withtier
| $withtier
| . + { assumptions: (.assumptions
        + (if .tier == "trance"
           then ["[DECISION] TRANCE tier: complexity flag AND stakes flag both hold; max_parallel=\($T.max_parallel) (C1)"]
           else [] end)) }
# TRANCE model-tier split (Wave-2): model_tier_lead / model_tier_workers come
# from routing.yaml's top-level `trance:` block. Fail-open — an absent block
# omits the fields entirely rather than defaulting them.
| (if (.tier == "trance") and ($R.trance != null)
   then . + { model_tier_lead: $R.trance.lead_tier, model_tier_workers: $R.trance.workers_tier }
   else . end)
| { _scores: ($ranked | map({name, class, score: (.score | if . > 1 then 1 else . end), raw, named})) } + .
JQ

ARTIFACT="$(printf '%s' "$ROUTING_JSON" | jq \
  --arg prompt "$PROMPT_LC" \
  --argjson ctx "$CTX_JSON" \
  "$ROUTE_JQ")"

# Record the incoming-hand-off verification verdict on the artifact (Step 5).
if [[ -n "$VERIFY_ENVELOPE" ]]; then
  ARTIFACT="$(printf '%s' "$ARTIFACT" | jq \
    --arg vv "$VERIFY_VERDICT" --arg vm "$VERIFY_MODE" --arg ve "$VERIFY_ENVELOPE" \
    '. + {incoming_verify: {verdict:$vv, mode:$vm, envelope:$ve}}')"
fi

# ── Phase E — telemetry dispatch-time stamp (AC-F3-5) ────────────────────────
# Gated: only when $EIDOLONS_HOME/telemetry/ dir exists OR EIDOLONS_TELEMETRY=1.
# Side-effect-only: routing stdout / --json / hook-output are BYTE-IDENTICAL
# whether telemetry is on or off.  Best-effort: errors are swallowed so the
# routing kernel never fails due to a telemetry write problem.
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray.
_telemetry_dispatch_stamp() {
  # Gate: telemetry enabled?
  local _tdir="$EIDOLONS_HOME/telemetry"
  if [[ "${EIDOLONS_TELEMETRY:-0}" != "1" && ! -d "$_tdir" ]]; then
    return 0
  fi

  # Extract selected Eidolons and tier from the ARTIFACT.
  local _sel _tier
  _sel="$(printf '%s' "$ARTIFACT" | jq -r '[.chain[].eidolon] | join(",")' 2>/dev/null || true)"
  _tier="$(printf '%s' "$ARTIFACT" | jq -r '.tier // "standard"' 2>/dev/null || true)"
  # Only stamp when at least one Eidolon was selected.
  if [[ -z "$_sel" || "$_sel" == "null" ]]; then
    return 0
  fi

  # Derive session key: prefer session_id from hook stdin; fallback to PID.
  local _sid="$$"
  if [[ -n "$HOOK_STDIN_INPUT" ]] && command -v jq >/dev/null 2>&1; then
    local _sid_from_hook
    _sid_from_hook="$(printf '%s' "$HOOK_STDIN_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
    if [[ -n "$_sid_from_hook" ]]; then
      _sid="$_sid_from_hook"
    fi
  fi

  # Compute objective_hash = sha256 of the original (case-preserved) PROMPT.
  local _obj_hash="null"
  if command -v shasum >/dev/null 2>&1; then
    _obj_hash="$(printf '%s' "$PROMPT" | shasum -a 256 2>/dev/null | awk '{print $1}' || true)"
  elif command -v sha256sum >/dev/null 2>&1; then
    _obj_hash="$(printf '%s' "$PROMPT" | sha256sum 2>/dev/null | awk '{print $1}' || true)"
  fi
  [[ -z "$_obj_hash" ]] && _obj_hash="null"
  # Wrap in JSON string if not null.
  local _obj_hash_json="null"
  if [[ "$_obj_hash" != "null" ]]; then
    _obj_hash_json="\"${_obj_hash}\""
  fi

  # UTC ISO-8601 timestamp.
  local _ts
  _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')"

  # Write one JSONL record per selected Eidolon into the .dispatch/ dir.
  local _dispatch_dir="${_tdir}/.dispatch"
  mkdir -p "$_dispatch_dir" 2>/dev/null || return 0

  # Process each Eidolon in the chain.
  local _old_ifs="$IFS"
  IFS=","
  local _ename
  for _ename in $_sel; do
    IFS="$_old_ifs"
    [[ -z "$_ename" ]] && continue

    # eidolon_prompt_sha: use the lib helper (roster versions.latest).
    local _eps
    _eps="$(eidolon_prompt_sha "$_ename" 2>/dev/null || echo "null")"
    [[ -z "$_eps" ]] && _eps="null"

    # Build JSON value for eidolon_prompt_sha.
    local _eps_json
    if [[ "$_eps" == "null" ]]; then
      _eps_json="null"
    else
      _eps_json="\"${_eps}\""
    fi

    # Build the dispatch row as a JSONL record.
    local _row
    _row="$(jq -nc \
      --arg ts "$_ts" \
      --arg eidolon "$_ename" \
      --argjson eidolon_prompt_sha "$_eps_json" \
      --argjson objective_hash "$_obj_hash_json" \
      --arg tier "$_tier" \
      '{ts:$ts, eidolon:$eidolon, eidolon_prompt_sha:$eidolon_prompt_sha,
        objective_hash:$objective_hash, tier:$tier}' 2>/dev/null || true)"
    if [[ -n "$_row" ]]; then
      printf '%s\n' "$_row" >> "${_dispatch_dir}/${_sid}.jsonl" 2>/dev/null || true
    fi
    IFS=","
  done
  IFS="$_old_ifs"
  return 0
}
# Non-fatal wrapper: swallow any error so routing kernel never fails.
{ _telemetry_dispatch_stamp; } 2>/dev/null || true

# ── Render ────────────────────────────────────────────────────────────────────
if [[ "$EXPLAIN" == "1" ]]; then
  {
    printf '%sscores%s  (prompt: %s)\n' "${BOLD:-}" "${RESET:-}" "$PROMPT"
    printf '%s' "$ARTIFACT" | jq -r '._scores[] | "  \(.name)\t\(.score)\t(raw=\(.raw)\(if .named then ", named" else "" end))"'
  } >&2
fi

# ── Hook mode: delegate to harness_hook.sh for host-dialect JSON ──────────
if [[ -n "$HOOK_HOST" ]]; then
  export HOOK_HOST HOOK_MODE="run" HOOK_EVENT_NAME="UserPromptSubmit"
  export ARTIFACT_JSON="$ARTIFACT" PROMPT HOOK_STDIN_INPUT
  bash "$SELF_DIR/harness_hook.sh"
  exit 0
fi

if [[ "$OUT" == "json" ]]; then
  printf '%s' "$ARTIFACT" | jq 'del(._scores)'
  exit 0
fi

# Human-readable routing card.
DECISION="$(printf '%s' "$ARTIFACT" | jq -r '.decision')"
TIER="$(printf '%s' "$ARTIFACT" | jq -r '.tier')"
CONF="$(printf '%s' "$ARTIFACT" | jq -r '.confidence')"

case "$DECISION" in
  clarify)
    printf '%sclarification needed%s (confidence %s)\n' "${UI_WARN:-}" "${RESET:-}" "$CONF"
    printf '%s' "$ARTIFACT" | jq -r '.clarification_request'
    ;;
  *)
    SEL="$(printf '%s' "$ARTIFACT" | jq -r '.selected | join(" → ")')"
    printf '%sroute%s  %s   %s[%s]%s  confidence %s\n' \
      "${BOLD:-}" "${RESET:-}" "$SEL" "${UI_DIM:-}" "$TIER" "${RESET:-}" "$CONF"
    printf '%s' "$ARTIFACT" | jq -r '.chain[] | "  → \(.eidolon) (\(.role))\(if .template then "  via " + .template else "" end)"'
    printf '%s' "$ARTIFACT" | jq -r '.assumptions[]? | "  · \(.)"'
    ;;
esac
