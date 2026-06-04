#!/usr/bin/env bash
# eidolons eval — the Eidolons evaluation harness
# ═══════════════════════════════════════════════════════════════════════════
# Roadmap #7 (the verdict-flipper): a published, contamination-resistant,
# budget-matched benchmark is the single piece of evidence that lifts the
# project-wide "M confidence, unbenchmarked" cap toward High.
#
#   eidolons eval routing [--suite public|holdout|all] [--validate-suite]
#                         [--min N] [--json] [--verbose]
#
# ROUTING is fully automated because the kernel (`eidolons run`) is DETERMINISTIC
# (I-C6): no LLM, no human, reproducible. The harness NEVER embeds a model and
# NEVER uses an LLM-judge — it grades the kernel's structured output against
# Eidolons-authored GROUND TRUTH (evals/routing-suite.yaml), the same
# print→run→grade-from-file discipline as `canary`. Reports accuracy per category
# alongside COST (routing uses no model tokens → ~0, stated honestly; the column
# is there for the human-in-the-loop quality / MCP recall evals that extend this
# harness later). Determinism ⇒ pass^k == pass^1 here.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

NEXUS_ROOT="$(cd "$(dirname "$ROSTER_FILE")/.." && pwd)"
ROUTING_SUITE="$NEXUS_ROOT/evals/routing-suite.yaml"

usage() {
  cat <<EOF
eidolons eval — measure the Eidolons against labelled ground truth (no LLM)

Usage: eidolons eval <routing|quality|swe> [OPTIONS]

routing   Run the DETERMINISTIC routing benchmark: drive 'eidolons run' against
          evals/routing-suite.yaml and score per-category accuracy + cost.
quality   HUMAN-IN-THE-LOOP contract-conformance quality benchmark (emit a mission,
          run the Eidolon, grade the saved output; pass^k). See
          'eidolons eval quality --help'.
swe       SWE-task-solving harness: drive 'eidolons sandbox loop' over a task
          suite (resolved-rate + pass^k). The bundled suite is a HARNESS
          SELF-TEST; a real number needs an external suite + a model --fix-hook
          + a real --via sandbox. See 'eidolons eval swe --help'.

Options (routing):
  --suite public|holdout|all   Which suite(s) to run (default: public).
  --validate-suite             Run the task-validity checklist on the suite
                               itself (the harness's own self-test) and exit.
  --min N                      Exit 1 if overall accuracy < N percent (CI gate).
  --json                       Emit the scorecard as JSON.
  --verbose                    Print every task's pass/fail.
  -h, --help                   Show this help.

The suite is Eidolons-authored ground truth — not a borrowed/contaminated
leaderboard. A private 'holdout' set is kept separate from 'public'.
EOF
}

SUBCMD="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$SUBCMD" in
  -h|--help|"") usage; exit 0 ;;
  routing) ;;
  quality) exec bash "$SELF_DIR/eval_quality.sh" "$@" ;;
  swe) exec bash "$SELF_DIR/eval_swe.sh" "$@" ;;
  *) die "Unknown subcommand: $SUBCMD (want: routing | quality | swe). See 'eidolons eval --help'" ;;
esac

SUITE_SEL="public"
VALIDATE=false
MIN=""
OUT="text"
VERBOSE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite)          SUITE_SEL="${2:-public}"; shift 2 ;;
    --suite-file)     ROUTING_SUITE="${2:-}"; shift 2 ;;
    --validate-suite) VALIDATE=true; shift ;;
    --min)            MIN="${2:-}"; shift 2 ;;
    --json)           OUT="json"; shift ;;
    --verbose)        VERBOSE=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                die "Unknown option: $1" ;;
  esac
done
case "$SUITE_SEL" in public|holdout|all) ;; *) die "Invalid --suite '$SUITE_SEL' (want public|holdout|all)" ;; esac

[[ -f "$ROUTING_SUITE" ]] || die "Routing suite not found: $ROUTING_SUITE"
SUITE_JSON="$(yaml_to_json "$ROUTING_SUITE")"

# ── --validate-suite: the harness's own task-validity self-test (R6-F07) ──────
if [[ "$VALIDATE" == true ]]; then
  ROSTER_NAMES="$(roster_list_names | jq -R . | jq -s .)"
  DEFECTS="$(printf '%s' "$SUITE_JSON" | jq -r --argjson roster "$ROSTER_NAMES" '
    [ .suites | to_entries[] as $e | $e.value[] | . + {suite: $e.key} ] as $tasks
    | [
        ( ([$tasks[].id]|length) - ([$tasks[].id]|unique|length) | select(. > 0) | "duplicate task ids" ),
        ( [$tasks[] | {p: .prompt, c: (.ctx // {})}] as $pc
          | ($pc|length) - ($pc|unique|length) | select(. > 0) | "duplicate prompt+ctx tasks" ),
        ( $tasks[] | select((.id // "") == "") | "task missing id" ),
        ( $tasks[] | select((.prompt // "") == "") | "\(.id): empty prompt" ),
        ( $tasks[] | select((.category // "") == "") | "\(.id): missing category" ),
        ( $tasks[] | select((.expect | type) != "object") | "\(.id): missing/invalid expect" ),
        ( $tasks[] | select((.expect | type) == "object") | select(.expect.decision != null)
          | .id as $id | .expect.decision as $d
          | select(["dispatch","chain","refusal_reroute","clarify"] | index($d) | not)
          | "\($id): invalid decision \($d)" ),
        ( $tasks[] | select((.expect | type) == "object") | select(.expect.tier != null)
          | .id as $id | .expect.tier as $tr
          | select(["standard","trance"] | index($tr) | not)
          | "\($id): invalid tier \($tr)" ),
        ( $tasks[] | .id as $id | (.expect.selected // [])[] as $s
          | select($roster | index($s) | not) | "\($id): selected \($s) not in roster" )
      ] | .[]')"
  if [[ -n "$DEFECTS" ]]; then
    echo "$DEFECTS" | while IFS= read -r d; do warn "suite defect — $d"; done
    die "routing suite failed task-validity self-test"
  fi
  ok "routing suite passed the task-validity self-test ($(printf '%s' "$SUITE_JSON" | jq '[.suites[][]]|length') tasks)"
  exit 0
fi

# ── Run: drive `eidolons run` per task, grade against ground truth ────────────
TASKS="$(printf '%s' "$SUITE_JSON" | jq -c --arg sel "$SUITE_SEL" '
  .suites | to_entries[] | select($sel=="all" or .key==$sel) | .key as $s | .value[] | . + {suite: $s}')"

RESULTS="[]"
while IFS= read -r task; do
  [[ -z "$task" ]] && continue
  prompt="$(printf '%s' "$task" | jq -r '.prompt')"
  flags=()
  sm="$(printf '%s' "$task" | jq -r '.ctx.surface_modules // empty')"; [[ -n "$sm" ]] && flags+=(--surface-modules "$sm")
  sf="$(printf '%s' "$task" | jq -r '.ctx.surface_files // empty')";   [[ -n "$sf" ]] && flags+=(--surface-files "$sf")
  [[ "$(printf '%s' "$task" | jq -r '.ctx.trance // false')" == "true" ]] && flags+=(--trance)
  [[ "$(printf '%s' "$task" | jq -r '.ctx.prior_failure // false')" == "true" ]] && flags+=(--prior-failure)

  # bash 3.2 + set -u safe empty-array expansion.
  artifact="$(bash "$SELF_DIR/run.sh" "$prompt" ${flags[@]+"${flags[@]}"} --json 2>/dev/null || echo '{}')"

  graded="$(jq -nc \
    --argjson task "$task" --argjson a "$artifact" '
    ($task.expect // {}) as $e
    | ( $e | to_entries | map(
        .key as $k | .value as $v
        | if   $k=="selected"          then ($a.selected == $v)
          elif $k=="decision"          then ($a.decision == $v)
          elif $k=="tier"              then ($a.tier == $v)
          elif $k=="refusal_rerouting" then ($a.refusal_rerouting == $v)
          else true end ) | all ) as $pass
    | { id: $task.id, suite: $task.suite, category: ($task.category // "uncategorized"),
        pass: $pass,
        expected: $e,
        actual: { decision: $a.decision, selected: $a.selected, tier: $a.tier } }')"
  RESULTS="$(printf '%s' "$RESULTS" | jq --argjson g "$graded" '. + [$g]')"
done <<< "$TASKS"

# ── Score: per-category + overall ─────────────────────────────────────────────
SCORE="$(printf '%s' "$RESULTS" | jq --arg suite "$SUITE_SEL" '
  { suite: $suite,
    total: length,
    passed: ([ .[] | select(.pass) ] | length),
    accuracy_pct: (if length==0 then 0 else (([ .[] | select(.pass) ] | length) * 1000 / length | floor) / 10 end),
    cost_tokens: 0,
    deterministic: true,
    by_category: ( group_by(.category)
                   | map({ category: .[0].category, total: length,
                           passed: ([ .[] | select(.pass) ] | length),
                           accuracy_pct: ((([ .[] | select(.pass) ] | length) * 1000 / length | floor) / 10) })
                   | sort_by(.category) ),
    failures: [ .[] | select(.pass | not) | { id, category, expected, actual } ] }')"

if [[ "$OUT" == "json" ]]; then
  printf '%s\n' "$SCORE"
else
  ACC="$(printf '%s' "$SCORE" | jq -r '.accuracy_pct')"
  PASSED="$(printf '%s' "$SCORE" | jq -r '.passed')"
  TOTAL="$(printf '%s' "$SCORE" | jq -r '.total')"
  printf '%seidolons eval routing%s  suite=%s  (deterministic; pass^k == pass^1)\n' "${BOLD:-}" "${RESET:-}" "$SUITE_SEL"
  printf '%s' "$SCORE" | jq -r '.by_category[] | "\(.category)\t\(.passed)/\(.total)\t\(.accuracy_pct)"' \
    | while IFS=$'\t' read -r cat pt acc; do printf '  %-14s %-8s %5s%%\n' "$cat" "$pt" "$acc"; done
  printf '  %s──────────────%s\n' "${UI_DIM:-}" "${RESET:-}"
  printf '  %-14s %-8s %5s%%   cost=0 tokens (no model)\n' "OVERALL" "$PASSED/$TOTAL" "$ACC"
  if [[ "$VERBOSE" == true ]]; then
    printf '%s' "$SCORE" | jq -r '.failures[] | "  ✗ \(.id) [\(.category)] expected \(.expected) got \(.actual)"'
  fi
  if [[ "$PASSED" != "$TOTAL" ]]; then
    warn "$((TOTAL - PASSED)) routing miss(es) — run with --verbose to see them"
  fi
fi

# ── Optional CI gate ──────────────────────────────────────────────────────────
if [[ -n "$MIN" ]]; then
  ACC="$(printf '%s' "$SCORE" | jq -r '.accuracy_pct')"
  if awk "BEGIN{exit !($ACC < $MIN)}"; then
    [[ "$OUT" == "text" ]] && warn "accuracy ${ACC}% < required ${MIN}%"
    exit 1
  fi
fi
exit 0
