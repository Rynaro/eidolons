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

# Absolute path to THIS script, used only by --matrix to re-invoke the whole
# single-arm suite path (untouched) once per arm — mirrors how sandbox.sh's
# --cascade re-invokes itself once per tier (cli/src/sandbox.sh:43).
SELF_FILE="$SELF_DIR/eval_swe.sh"

# Nexus root (normalised), for the scorecard store. EIDOLONS_EVAL_RESULTS_DIR
# overrides the store location wholesale — tests (and anyone who does not
# want to write into a real nexus checkout) MUST set this; production runs
# leave it unset and the store lives at <nexus>/evals/results/ (committed).
NEXUS_ROOT="$(cd "$(dirname "$ROSTER_FILE")/.." && pwd)"
RESULTS_DIR="${EIDOLONS_EVAL_RESULTS_DIR:-$NEXUS_ROOT/evals/results}"

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
  --matrix ARMS.json  Run every arm in ARMS.json (schema:
                      schemas/eval-arms.schema.json) through THIS suite path,
                      unmodified, once per arm — see 'MATRIX MODE' below.
  --smoke             Under --matrix: every arm ignores its fix_hook and uses
                      the suite's gold_fix instead (validates arm/scorecard
                      plumbing without a model). Also honoured stand-alone:
                      forces smoke mode even if --fix-hook is given.
  --no-store          Under --matrix: skip writing scorecards/matrix summary
                      to evals/results/ (default: written).
  -h, --help          Show this help.

Suite task fields (optional, per task): holdout: <cmd> — a SEALED oracle the
fix-hook never sees (held in the loop process only, NEVER materialised into the
task workdir); failing it after a visible pass → final=reward-hacked.
protect: <glob> — anchoring files the fix-hook must not mutate.
description: <text> — exported to the fix-hook as EIDOLONS_EVAL_TASK_BRIEF
(the task-context env var the reference hooks in evals/hooks/ read).

MATRIX MODE (--matrix ARMS.json): for each arm ({label, fix_hook, env,
control} — schemas/eval-arms.schema.json) this re-invokes the EXACT single-
arm path above (all tasks x --k, every other flag on this invocation passed
through unmodified) as a child process, with the arm's env exported and its
fix_hook substituted for --fix-hook. The single-arm path itself is NEVER
restructured — matrix wraps it, the same discipline 'eidolons sandbox loop
--cascade' uses for tier escalation. Every arm's result is written as one
evals/results/<UTC-date>-<suite>-<label>.scorecard.json (schema:
schemas/eval-scorecard.schema.json; --no-store skips this). After all arms
run, a pairwise summary vs the first control:true arm (resolved-rate delta,
pass^k delta, per-task newly-resolved/regressed) is printed and written to
evals/results/<UTC-date>-<suite>-matrix.json. See evals/results/README.md and
'eidolons eval baseline --help' for reading the store back.

SCOPE: the bundled suite is a harness self-test with reference fixes, NOT a
capability benchmark. See 'eidolons sandbox --help' for the loop it drives.
EOF
}

# ── --matrix: run every arm through the EXISTING single-arm path below,
# unmodified, as a child process (wrap-don't-touch, mirrors --cascade). ──────
_run_matrix() {
  [[ -f "$MATRIX" ]] || die "Matrix arms file not found: $MATRIX"
  local arms_json
  arms_json="$(jq -c '.' "$MATRIX" 2>/dev/null)" || die "Could not parse arms JSON: $MATRIX"
  local n_arms
  n_arms="$(printf '%s' "$arms_json" | jq '(.arms // []) | length' 2>/dev/null || echo 0)"
  [[ "$n_arms" -ge 1 ]] 2>/dev/null || die "arms file must declare >=1 arm under .arms[] (schemas/eval-arms.schema.json): $MATRIX"

  local shape_problems
  shape_problems="$(printf '%s' "$arms_json" | jq -r '
    [ .arms | to_entries[] | .key as $i | .value as $a |
        (if ($a.label // "") == "" then "arms[\($i)]: missing label" else empty end),
        (if ($a.fix_hook // "") == "" then "arms[\($i)]: missing fix_hook" else empty end)
    ] as $field_problems
    | ( [.arms[].label] | group_by(.) | map(select(length>1)) | map("duplicate arm label: \(.[0])") ) as $dup_problems
    | ($field_problems + $dup_problems) | .[]' 2>/dev/null | grep -v '^$' || true)"
  if [[ -n "$shape_problems" ]]; then
    warn "arms file invalid:"
    printf '%s\n' "$shape_problems" | sed 's/^/  - /' >&2
    die "eval swe --matrix: arms file failed validation: $MATRIX"
  fi

  local suite_label started_at run_date nexus_ver control_label
  suite_label="$(basename "$SUITE" .yaml)"
  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "1970-01-01T00:00:00Z")"
  run_date="$(date -u '+%Y-%m-%d' 2>/dev/null || echo "1970-01-01")"
  nexus_ver="$(read_nexus_version 2>/dev/null || echo "0.0.0-dev")"
  control_label="$(printf '%s' "$arms_json" | jq -r '[.arms[] | select(.control == true)][0].label // ""')"

  [[ "$NO_STORE" == true ]] || mkdir -p "$RESULTS_DIR"

  local matrix_arms_out labels
  matrix_arms_out="[]"
  labels="$(printf '%s' "$arms_json" | jq -r '.arms[].label')"
  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    local arm arm_fix_hook arm_control env_keys
    arm="$(printf '%s' "$arms_json" | jq -c --arg l "$label" '.arms[] | select(.label == $l)')"
    arm_fix_hook="$(printf '%s' "$arm" | jq -r '.fix_hook')"
    arm_control="$(printf '%s' "$arm" | jq -r '.control // false')"
    env_keys="$(printf '%s' "$arm" | jq -r '(.env // {}) | keys[]')"

    local child_args=(--suite-file "$SUITE" --max-attempts "$MAX_ATTEMPTS" --k "$K" --fanout "$FANOUT")
    [[ "$REQUIRE_RED" == true ]]  && child_args+=(--require-red)
    [[ -n "$JUDGE_HOOK" ]]        && child_args+=(--judge-hook "$JUDGE_HOOK")
    [[ -n "$VIA" ]]               && child_args+=(--via "$VIA")
    [[ "$ALLOW_UNSAFE" == true ]] && child_args+=(--allow-unsafe-host)
    # Under --smoke every arm ignores its fix_hook (omit --fix-hook entirely
    # so the child's own smoke-detection — MODE=smoke unless --fix-hook is
    # given — engages identically to a plain no-flags run).
    # Absolutize repo-relative hook paths: the loop invokes the hook from the
    # ephemeral per-attempt workdir, where a relative path (e.g.
    # evals/hooks/keep-bare.sh) resolves to nothing → exit 127 and a silent
    # UNRESOLVED arm (observed live, 2026-07-03). Command-string hooks
    # (containing spaces / not a file) pass through untouched.
    if [[ "$arm_fix_hook" != /* && -f "$arm_fix_hook" ]]; then
      arm_fix_hook="$PWD/$arm_fix_hook"
    fi
    [[ "$SMOKE_FLAG" != true ]] && child_args+=(--fix-hook "$arm_fix_hook")
    child_args+=(--json)

    local env_assign=()
    if [[ -n "$env_keys" ]]; then
      local ek ev
      while IFS= read -r ek; do
        [[ -z "$ek" ]] && continue
        ev="$(printf '%s' "$arm" | jq -r --arg k "$ek" '.env[$k]')"
        env_assign+=("$ek=$ev")
      done <<< "$env_keys"
    fi

    [[ "$OUT" != "json" ]] && say "matrix: running arm '$label'..."
    local child_json rc=0
    child_json="$(env "${env_assign[@]+"${env_assign[@]}"}" bash "$SELF_FILE" "${child_args[@]}")" || rc=$?
    [[ "$rc" -eq 0 ]] || die "matrix: arm '$label' invocation failed (exit $rc) — see stderr above"

    local smoke_actual sc
    smoke_actual="$(printf '%s' "$child_json" | jq -r '.mode == "smoke"')"
    sc="$(printf '%s' "$child_json" | jq -c \
      --arg schema "1.0" --arg suite "$suite_label" --arg label "$label" \
      --arg fix_hook "$arm_fix_hook" --argjson env "$(printf '%s' "$arm" | jq -c '.env // {}')" \
      --argjson control "$([[ "$arm_control" == "true" ]] && echo true || echo false)" \
      --arg started "$started_at" --argjson k "$K" --arg nexus_ver "$nexus_ver" \
      --argjson smoke "$([[ "$smoke_actual" == "true" ]] && echo true || echo false)" \
      '{
        schema_version: $schema,
        suite: $suite,
        arm: {label:$label, fix_hook:$fix_hook, env:$env, control:$control},
        started_at: $started,
        k: $k,
        tasks: [ .tasks[] | {id:.id, resolved:.resolved, passes:.resolved_runs, attempts:.k} ],
        resolved_rate: .resolved_rate,
        pass_k_rate: .pass_k,
        harness: {nexus_version:$nexus_ver, smoke:$smoke}
      }')"

    if [[ "$NO_STORE" != true ]]; then
      local outfile="$RESULTS_DIR/${run_date}-${suite_label}-${label}.scorecard.json"
      printf '%s\n' "$sc" | jq '.' > "$outfile"
      [[ "$OUT" != "json" ]] && info "matrix: wrote $outfile"
    fi
    matrix_arms_out="$(printf '%s' "$matrix_arms_out" | jq -c --argjson s "$sc" '. + [$s]')"
  done <<< "$labels"

  # ── Pairwise summary vs the first control:true arm ─────────────────────────
  local summary
  if [[ -n "$control_label" ]]; then
    local cmp_jq
    cmp_jq="$(cat <<'JQEOF'
(map(select(.arm.label == $ctrl))[0]) as $c
| map(select(.arm.label != $ctrl)) as $others
| {
    control: $ctrl,
    comparisons: [
      $others[] as $o
      | ($o.tasks | map({(.id): .resolved}) | add // {}) as $om
      | ($c.tasks  | map({(.id): .resolved}) | add // {}) as $cm
      | {
          label: $o.arm.label,
          resolved_rate_delta: ($o.resolved_rate - $c.resolved_rate),
          pass_k_rate_delta: ($o.pass_k_rate - $c.pass_k_rate),
          newly_resolved: [ ($om | keys[]) as $id | select((($cm[$id]) // false) == false and (($om[$id]) // false) == true) | $id ],
          regressed:      [ ($cm | keys[]) as $id | select((($cm[$id]) // false) == true  and (($om[$id]) // false) == false) | $id ]
        }
    ]
  }
JQEOF
)"
    summary="$(printf '%s' "$matrix_arms_out" | jq -c --arg ctrl "$control_label" "$cmp_jq")"
  else
    summary='{"control":null,"comparisons":[],"note":"no arm marked control:true — no pairwise comparison computed"}'
    [[ "$OUT" != "json" ]] && warn "matrix: no arm has control:true — skipping pairwise comparison"
  fi

  local matrix_doc
  matrix_doc="$(jq -nc --arg schema "1.0" --arg suite "$suite_label" --arg started "$started_at" \
    --argjson arms "$matrix_arms_out" --argjson summary "$summary" \
    '{schema_version:$schema, suite:$suite, started_at:$started, arms:[$arms[].arm], summary:$summary}')"

  if [[ "$NO_STORE" != true ]]; then
    local matrix_file="$RESULTS_DIR/${run_date}-${suite_label}-matrix.json"
    printf '%s\n' "$matrix_doc" | jq '.' > "$matrix_file"
    [[ "$OUT" != "json" ]] && info "matrix: wrote $matrix_file"
  fi

  if [[ "$OUT" == "json" ]]; then
    printf '%s\n' "$matrix_doc"
  else
    echo ""
    printf '%seval swe matrix summary%s  suite=%s  arms=%s\n' "${BOLD:-}" "${RESET:-}" "$suite_label" "$n_arms"
    printf '%s' "$matrix_arms_out" | jq -r '.[] | [.arm.label, (.resolved_rate|tostring), (.pass_k_rate|tostring), (.arm.control|tostring)] | @tsv' \
      | while IFS=$'\t' read -r lbl rr pk ctrl; do
          tag=""; [[ "$ctrl" == "true" ]] && tag="  [control]"
          printf '  %-20s resolved_rate=%-8s pass_k_rate=%-8s%s\n' "$lbl" "$rr" "$pk" "$tag"
        done
    if [[ -n "$control_label" ]]; then
      printf '%s' "$summary" | jq -r --arg ctrl "$control_label" \
        '.comparisons[] | "  \(.label) vs \($ctrl): Δresolved_rate=\(.resolved_rate_delta)  Δpass_k=\(.pass_k_rate_delta)  newly_resolved=\(.newly_resolved|length)  regressed=\(.regressed|length)"'
    fi
  fi
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
MATRIX=""
SMOKE_FLAG=false
NO_STORE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite-file)       SUITE="${2:-}"; shift 2 ;;
    --fix-hook)         FIX_HOOK="${2:-}"
                        # Absolutize repo-relative hook FILES (see matrix note).
                        if [[ "$FIX_HOOK" != /* && -f "$FIX_HOOK" ]]; then FIX_HOOK="$PWD/$FIX_HOOK"; fi
                        shift 2 ;;
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
    --matrix)           MATRIX="${2:-}"; shift 2 ;;
    --smoke)            SMOKE_FLAG=true; shift ;;
    --no-store)         NO_STORE=true; shift ;;
    -h|--help)          usage; exit 0 ;;
    *)                  die "Unknown option: $1 (see 'eidolons eval swe --help')" ;;
  esac
done

[[ -f "$SUITE" ]] || die "Suite file not found: $SUITE"
[[ "$MAX_ATTEMPTS" -ge 1 ]] 2>/dev/null || die "--max-attempts must be >= 1"
[[ "$K" -ge 1 ]] 2>/dev/null || die "--k must be >= 1"
[[ "$FANOUT" -ge 1 ]] 2>/dev/null || die "--fanout must be >= 1"
suite_json="$(yaml_to_json "$SUITE")" || die "Could not parse suite YAML: $SUITE"

# --smoke (stand-alone, i.e. without --matrix) forces smoke mode even if
# --fix-hook was also given — matches the honest-scope framing everywhere
# else in this file: an explicit ask for smoke always wins.
[[ "$SMOKE_FLAG" == true ]] && FIX_HOOK=""

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

# ── --matrix: dispatch to the matrix wrapper and stop. The single-arm path
# below (isolation policy through the final scorecard emit) is REACHED ONLY
# per-arm, as a fresh child-process invocation of this same script with
# --matrix absent — it never executes directly in a --matrix parent run. ────
if [[ -n "$MATRIX" ]]; then
  _run_matrix
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
  # Task context for the fix-hook: exported (not passed on argv) so any
  # --fix-hook — including the reference hooks in evals/hooks/ — can read the
  # task's own description without the suite format growing a new plumbing
  # path per hook. sandbox.sh's `bash -c "$hook"` inherits this process's
  # exported environment, so no change to sandbox.sh is needed.
  export EIDOLONS_EVAL_TASK_BRIEF="$(printf '%s' "$task" | jq -r '.description // ""')"
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
