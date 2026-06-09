#!/usr/bin/env bash
# eidolons eval swe — SWE-task-solving harness (sandbox-mediated)
# ═══════════════════════════════════════════════════════════════════════════
# The third eval mode (routing = deterministic; quality = human-in-the-loop;
# swe = task-solving). For each task in the suite it materialises a broken repo,
# drives `eidolons sandbox loop` (the #9 bounded edit-run-test engine), and
# records whether the loop reached green within the attempt cap. Aggregates a
# resolved-rate + pass^k.
#
# ⚠️ HONEST SCOPE: the bundled suite is a HARNESS SELF-TEST. In smoke mode the
# fix applied each round is the task's own `gold_fix` reference patch, so a 100%
# resolved-rate proves the ORCHESTRATION (setup → red → fix → green → diff-not-
# apply), NOT that a model solved an unseen task. A real SWE-bench-class number
# needs: an external --suite-file + a model --fix-hook + a real --via sandbox.
# That number — not this smoke — is what moves frontier confidence past 0.70 (R4).
#
# The nexus has NO LLM and builds NO sandbox: it owns the HARNESS (suite format,
# per-task orchestration, aggregation) and DELEGATES the model (--fix-hook) and
# isolation (--via). Adapter, not engine.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

SANDBOX_SH="$SELF_DIR/sandbox.sh"
DEFAULT_SUITE="$EIDOLONS_NEXUS/evals/swe-suite.yaml"
[[ -f "$DEFAULT_SUITE" ]] || DEFAULT_SUITE="$(cd "$SELF_DIR/../.." && pwd)/evals/swe-suite.yaml"

usage() {
  cat <<EOF
eidolons eval swe — SWE-task-solving harness (sandbox-mediated)

Usage: eidolons eval swe [OPTIONS]

Options:
  --suite-file PATH   Suite YAML (default: bundled smoke suite).
  --fix-hook CMD      The edit/LLM step (host's model). Reads
                      \$EIDOLONS_SANDBOX_LAST_OUTPUT and edits the repo. When
                      omitted, each task's gold_fix is used (deterministic SMOKE).
  --via CMD           Sandbox wrapper (docker/gvisor/e2b). Required for a real
                      --fix-hook (untrusted model code) unless --allow-unsafe-host.
  --allow-unsafe-host Run on the bare host (trusted code only; the smoke default).
  --max-attempts N    Per-task bounded cap passed to the loop (default 3).
  --k N               Run each task N times; pass^k = resolved in ALL N (default 1).
  --fanout N          Parallel-sample-and-select: pass --fanout N to the loop
                      (N independent fresh-context candidates, external selection).
  --require-red       Pass --require-red to the loop (the task's test must FAIL
                      on the base tree before any fix attempt).
  --judge-hook CMD    Pass an external diff-review judge to the loop.
  --min N             Exit 1 if resolved_rate < N percent (CI gate).
  --keep              Keep per-task workdirs (default: cleaned up).
  --validate-suite    Self-test the suite shape and exit (no execution).
  --list              List task ids + descriptions and exit.
  --json              Emit the scorecard as JSON.
  -h, --help          Show this help.

Suite task fields (optional, per task): holdout: <cmd> — a SEALED oracle the
fix-hook never sees (held in the loop process only, NEVER materialised into the
task workdir); failing it after a visible pass → final=reward-hacked.
protect: <glob> — anchoring files the fix-hook must not mutate.

SCOPE: the bundled suite is a harness self-test with reference fixes, NOT a
capability benchmark. See 'eidolons sandbox --help' for the loop it drives.
EOF
}

SUITE="$DEFAULT_SUITE"
FIX_HOOK=""
VIA=""
ALLOW_UNSAFE=false
MAX_ATTEMPTS=3
K=1
FANOUT=1
REQUIRE_RED=false
JUDGE_HOOK=""
MIN=""
KEEP=false
VALIDATE=false
LIST=false
OUT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite-file)       SUITE="${2:-}"; shift 2 ;;
    --fix-hook)         FIX_HOOK="${2:-}"; shift 2 ;;
    --via)              VIA="${2:-}"; shift 2 ;;
    --allow-unsafe-host) ALLOW_UNSAFE=true; shift ;;
    --max-attempts)     MAX_ATTEMPTS="${2:-3}"; shift 2 ;;
    --k)                K="${2:-1}"; shift 2 ;;
    --fanout)           FANOUT="${2:-1}"; shift 2 ;;
    --require-red)      REQUIRE_RED=true; shift ;;
    --judge-hook)       JUDGE_HOOK="${2:-}"; shift 2 ;;
    --min)              MIN="${2:-}"; shift 2 ;;
    --keep)             KEEP=true; shift ;;
    --validate-suite)   VALIDATE=true; shift ;;
    --list)             LIST=true; shift ;;
    --json)             OUT="json"; shift ;;
    -h|--help)          usage; exit 0 ;;
    *)                  die "Unknown option: $1 (see 'eidolons eval swe --help')" ;;
  esac
done

[[ -f "$SUITE" ]] || die "Suite file not found: $SUITE"
[[ "$MAX_ATTEMPTS" -ge 1 ]] 2>/dev/null || die "--max-attempts must be >= 1"
[[ "$K" -ge 1 ]] 2>/dev/null || die "--k must be >= 1"
[[ "$FANOUT" -ge 1 ]] 2>/dev/null || die "--fanout must be >= 1"
suite_json="$(yaml_to_json "$SUITE")" || die "Could not parse suite YAML: $SUITE"

# Mode = smoke (gold_fix reference) unless a real --fix-hook is supplied.
MODE="smoke"; [[ -n "$FIX_HOOK" ]] && MODE="model-driven"

# ── --validate-suite ───────────────────────────────────────────────────────
if [[ "$VALIDATE" == true ]]; then
  problems="$(printf '%s' "$suite_json" | jq -r '
    [ (.swe_version // empty | select(. == null) | "missing swe_version"),
      ( .tasks as $t
        | ($t // []) | to_entries[]
        | .key as $i | .value as $task
        | ( (if ($task.id // "") == "" then "task[\($i)]: missing id" else empty end),
            (if ($task.setup // "") == "" then "task[\($i)]: missing setup" else empty end),
            (if ($task.test // "") == "" then "task[\($i)]: missing test" else empty end) ) ),
      ( [ .tasks[].id ] | group_by(.) | map(select(length>1)) | .[] | "duplicate id: \(.[0])" )
    ] | .[]' 2>/dev/null)"
  # In smoke mode every task must carry a gold_fix (no model to provide the edit).
  if [[ "$MODE" == "smoke" ]]; then
    nogold="$(printf '%s' "$suite_json" | jq -r '.tasks[] | select((.gold_fix // "") == "") | "task \(.id): no gold_fix (required in smoke mode — supply --fix-hook for an external suite)"')"
    [[ -n "$nogold" ]] && problems="$(printf '%s\n%s' "$problems" "$nogold")"
  fi
  problems="$(printf '%s\n' "$problems" | grep -v '^$' || true)"
  if [[ -z "$problems" ]]; then
    if [[ "$OUT" == "json" ]]; then jq -nc '{valid:true, problems:[]}'; else ok "suite valid ($(printf '%s' "$suite_json" | jq '.tasks|length') tasks, mode=$MODE)"; fi
    exit 0
  else
    if [[ "$OUT" == "json" ]]; then
      jq -nc --arg p "$problems" '{valid:false, problems:($p|split("\n")|map(select(length>0)))}'
    else
      warn "suite invalid:"; printf '%s\n' "$problems" | sed 's/^/  - /'
    fi
    exit 1
  fi
fi

# ── --list ─────────────────────────────────────────────────────────────────
if [[ "$LIST" == true ]]; then
  if [[ "$OUT" == "json" ]]; then
    printf '%s' "$suite_json" | jq -c '{tasks:[.tasks[]|{id, description}]}'
  else
    printf '%s' "$suite_json" | jq -r '.tasks[] | "  \(.id)  —  \(.description // "")"'
  fi
  exit 0
fi

# ── Isolation policy (mirrors the sandbox loop's R8-03 refusal) ─────────────
iso_flags=()
if [[ -n "$VIA" ]]; then
  iso_flags=(--via "$VIA")
elif [[ "$ALLOW_UNSAFE" == true ]]; then
  iso_flags=(--allow-unsafe-host)
elif [[ "$MODE" == "smoke" ]]; then
  # Smoke fixes are trusted suite content (gold_fix) — bare host is acceptable.
  iso_flags=(--allow-unsafe-host)
else
  die "a real --fix-hook runs untrusted model code — pass --via '<sandbox-cmd>' or, only for trusted hooks, --allow-unsafe-host"
fi
iso_label="unsafe-host"; [[ -n "$VIA" ]] && iso_label="$VIA"

# ── Run the suite ──────────────────────────────────────────────────────────
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/eidolons-swe.XXXXXX")"
cleanup() { [[ "$KEEP" == false ]] && rm -rf "$WORK_ROOT" 2>/dev/null || true; }
trap cleanup EXIT

[[ "$OUT" != "json" ]] && say "eval swe — running $(printf '%s' "$suite_json" | jq '.tasks|length') task(s), k=$K, mode=$MODE"

results="[]"
task_ids="$(printf '%s' "$suite_json" | jq -r '.tasks[].id')"
while IFS= read -r tid; do
  [[ -z "$tid" ]] && continue
  task="$(printf '%s' "$suite_json" | jq -c --arg id "$tid" '.tasks[] | select(.id == $id)')"
  setup="$(printf '%s' "$task" | jq -r '.setup')"
  test_cmd="$(printf '%s' "$task" | jq -r '.test')"
  hook="$FIX_HOOK"
  [[ -z "$hook" ]] && hook="$(printf '%s' "$task" | jq -r '.gold_fix // ""')"
  # Stage 2: optional per-task sealed holdout + protected anchoring files. The
  # holdout command stays INLINE (loop-process memory only) — it is never
  # written into the task workdir, so the fix-hook cannot read it from disk.
  holdout_cmd="$(printf '%s' "$task" | jq -r '.holdout // ""')"
  protect_glob="$(printf '%s' "$task" | jq -r '.protect // ""')"
  loop_extra=()
  [[ -n "$holdout_cmd" ]]        && loop_extra+=(--holdout "$holdout_cmd")
  [[ -n "$protect_glob" ]]       && loop_extra+=(--protect "$protect_glob")
  [[ "$FANOUT" -gt 1 ]]          && loop_extra+=(--fanout "$FANOUT")
  [[ "$REQUIRE_RED" == true ]]   && loop_extra+=(--require-red)
  [[ -n "$JUDGE_HOOK" ]]         && loop_extra+=(--judge-hook "$JUDGE_HOOK")

  resolved_runs=0
  finals="[]"
  for run in $(seq 1 "$K"); do
    wd="$WORK_ROOT/$tid-$run"
    mkdir -p "$wd"
    # Materialise the broken repo (trusted suite content).
    ( cd "$wd" && bash -c "$setup" ) >/dev/null 2>&1 || true
    # Test script (so pipes / && in the test survive the loop's argv execution).
    printf '#!/bin/sh\n%s\n' "$test_cmd" > "$wd/.swe-test.sh"
    # Drive the #9 bounded edit-run-test loop. Capture the ledger JSON; the loop
    # exits 3 on cap-out, so use `|| rc=$?` (never `( ) || true`, which masks it).
    rc=0
    ledger="$(cd "$wd" && bash "$SANDBOX_SH" loop \
      --tests "sh .swe-test.sh" \
      --fix-hook "$hook" \
      "${iso_flags[@]}" \
      --max-attempts "$MAX_ATTEMPTS" \
      "${loop_extra[@]+"${loop_extra[@]}"}" \
      --out ".sb" \
      --json 2>/dev/null)" || rc=$?
    final="$(printf '%s' "$ledger" | jq -r '.final // "error"' 2>/dev/null || echo error)"
    finals="$(printf '%s' "$finals" | jq -c --arg f "$final" '. + [$f]')"
    [[ "$final" == "passed" ]] && resolved_runs=$((resolved_runs + 1))
  done

  task_resolved=false; [[ "$resolved_runs" -ge 1 ]] && task_resolved=true
  task_all_k=false;   [[ "$resolved_runs" -eq "$K" ]] && task_all_k=true
  results="$(printf '%s' "$results" | jq -c \
    --arg id "$tid" --argjson rr "$resolved_runs" --argjson k "$K" \
    --argjson res "$task_resolved" --argjson allk "$task_all_k" \
    --argjson fin "$finals" \
    '. + [{id:$id, resolved_runs:$rr, k:$k, resolved:$res, resolved_all_k:$allk, finals:$fin}]')"
  [[ "$OUT" != "json" ]] && printf '  %-22s %s (%s/%s runs)\n' "$tid" \
    "$([[ "$task_resolved" == true ]] && echo RESOLVED || echo UNRESOLVED)" "$resolved_runs" "$K"
done <<< "$task_ids"

# ── Aggregate ──────────────────────────────────────────────────────────────
total="$(printf '%s' "$results" | jq 'length')"
resolved="$(printf '%s' "$results" | jq '[.[]|select(.resolved)]|length')"
passk_n="$(printf '%s' "$results" | jq '[.[]|select(.resolved_all_k)]|length')"
rate="$(printf '%s' "$results" | jq -n --argjson r "$resolved" --argjson t "$total" 'if $t==0 then 0 else ($r/$t) end')"
passk="$(printf '%s' "$results" | jq -n --argjson r "$passk_n" --argjson t "$total" 'if $t==0 then 0 else ($r/$t) end')"
scope_note="HARNESS SELF-TEST with reference fixes — NOT a model solving unseen tasks. A real SWE-bench-class number needs an external --suite-file + a model --fix-hook + a real --via sandbox."
[[ "$MODE" == "model-driven" ]] && scope_note="model-driven run via the supplied --fix-hook. resolved_rate is the measured task-solving number for this suite."

finals_summary="$(printf '%s' "$results" | jq -c '[.[].finals[]] | group_by(.) | map({key:.[0], value:length}) | from_entries')"
scorecard="$(jq -nc \
  --arg mode "$MODE" --arg hook "$([[ "$MODE" == smoke ]] && echo 'gold_fix (per-task reference)' || echo "$FIX_HOOK")" \
  --arg iso "$iso_label" --argjson total "$total" --argjson resolved "$resolved" \
  --argjson rate "$rate" --argjson passk "$passk" --argjson k "$K" \
  --argjson fanout "$FANOUT" --argjson finsum "$finals_summary" \
  --arg note "$scope_note" --argjson tasks "$results" \
  '{swe_version:"1.0", mode:$mode, fix_hook:$hook, isolation:$iso,
    total:$total, resolved:$resolved, resolved_rate:$rate, pass_k:$passk, k:$k,
    fanout:$fanout, finals_summary:$finsum,
    model_tokens:(if $mode=="smoke" then 0 else null end),
    scope_note:$note, tasks:$tasks}')"

if [[ "$OUT" == "json" ]]; then
  printf '%s\n' "$scorecard"
else
  echo ""
  printf '%seval swe scorecard%s\n' "${BOLD:-}" "${RESET:-}"
  printf '  mode=%s  isolation=%s  k=%s\n' "$MODE" "$iso_label" "$K"
  printf '  resolved %s/%s   resolved_rate=%s   pass^%s=%s\n' "$resolved" "$total" \
    "$(printf '%s' "$rate" | jq -r '.*100|floor/100')" "$K" "$(printf '%s' "$passk" | jq -r '.*100|floor/100')"
  printf '  %s⚠ %s%s\n' "${YELLOW:-}" "$scope_note" "${RESET:-}"
fi

# ── CI gate ────────────────────────────────────────────────────────────────
if [[ -n "$MIN" ]]; then
  pct="$(printf '%s' "$rate" | jq -n --argjson r "$rate" '($r*100)|floor')"
  if (( pct < MIN )); then
    [[ "$OUT" != "json" ]] && warn "resolved_rate ${pct}% < --min ${MIN}%"
    exit 1
  fi
fi
exit 0
