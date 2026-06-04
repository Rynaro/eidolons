#!/usr/bin/env bash
# eidolons eval quality — human-in-the-loop contract-conformance quality benchmark
# ═══════════════════════════════════════════════════════════════════════════
# Same discipline as `canary`: the CLI NEVER embeds a model and NEVER uses an
# LLM-judge. It prints a mission, a human runs the Eidolon in their LLM and saves
# the output, and the CLI grades the saved output against MECHANICAL (grep-based)
# rubric assertions — the Eidolon's own methodology P0 contracts. Reports pass^k
# over k independent human-run samples (R6-F08 reliability metric).
#
#   eidolons eval quality list
#   eidolons eval quality emit  <task-id>
#   eidolons eval quality grade <task-id> <output-file> [<output-file> ...]
#
# HONEST SCOPE: this measures STRUCTURAL / contract-conformance quality, NOT
# rival-comparable task-SOLVING. A SWE-bench/LOCOMO-class head-to-head needs an
# execution sandbox + a clean EXTERNAL suite (roadmap #9 / dossier reversal N1).

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

QUALITY_SUITE="$(cd "$(dirname "$ROSTER_FILE")/.." && pwd)/evals/quality-suite.yaml"

usage() {
  cat <<EOF
eidolons eval quality — human-in-the-loop contract-conformance quality (no LLM-judge)

Usage:
  eidolons eval quality list
  eidolons eval quality emit  <task-id>
  eidolons eval quality grade <task-id> <output-file> [<output-file> ...] [--json]

Flow (same as canary): emit a mission → run the named Eidolon in your LLM and save
the output → grade the saved output against the mechanical rubric. Pass >=2 output
files (independent runs) to grade to get a pass^k reliability score.

Options:
  --suite-file <path>   Use a custom quality suite.
  --json                Machine-readable grade output.

Measures contract-conformance quality (structural), reported as pass^k — NOT a
rival-comparable task-solving number.
EOF
}

MODE="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$MODE" in
  -h|--help|"") usage; exit 0 ;;
  list|emit|grade) ;;
  *) die "Unknown quality mode: $MODE (want list|emit|grade)" ;;
esac

TASK_ID=""
FILES=()
OUT="text"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite-file) QUALITY_SUITE="${2:-}"; shift 2 ;;
    --json)       OUT="json"; shift ;;
    -h|--help)    usage; exit 0 ;;
    -*)           die "Unknown option: $1" ;;
    *)            if [[ -z "$TASK_ID" && "$MODE" != "grade" ]]; then TASK_ID="$1"
                  elif [[ -z "$TASK_ID" ]]; then TASK_ID="$1"
                  else FILES+=("$1"); fi
                  shift ;;
  esac
done

[[ -f "$QUALITY_SUITE" ]] || die "Quality suite not found: $QUALITY_SUITE"
SUITE_JSON="$(yaml_to_json "$QUALITY_SUITE")"

_task() { printf '%s' "$SUITE_JSON" | jq -c --arg id "$1" '.tasks[] | select(.id == $id)'; }

# ── _rubric_match FILE ITEM_JSON → 0 if the output satisfies the item ─────────
_rubric_match() {
  local file="$1" item="$2" kind gflags=""
  kind="$(printf '%s' "$item" | jq -r '.kind')"
  [[ "$(printf '%s' "$item" | jq -r '.ci // false')" == "true" ]] && gflags="-i"
  case "$kind" in
    regex)
      local pat; pat="$(printf '%s' "$item" | jq -r '.pattern')"
      grep -E $gflags -q -- "$pat" "$file" ;;
    contains_any)
      local hit=1 p
      while IFS= read -r p; do grep -F $gflags -q -- "$p" "$file" 2>/dev/null && { hit=0; break; }; done \
        < <(printf '%s' "$item" | jq -r '.patterns[]')
      [[ "$hit" -eq 0 ]] ;;
    contains_all)
      local miss=0 p
      while IFS= read -r p; do grep -F $gflags -q -- "$p" "$file" 2>/dev/null || { miss=1; break; }; done \
        < <(printf '%s' "$item" | jq -r '.patterns[]')
      [[ "$miss" -eq 0 ]] ;;
    min_count)
      local pat n cnt; pat="$(printf '%s' "$item" | jq -r '.pattern')"; n="$(printf '%s' "$item" | jq -r '.n')"
      cnt="$(grep -E $gflags -o -- "$pat" "$file" 2>/dev/null | wc -l | tr -d '[:space:]')"
      [[ "${cnt:-0}" -ge "$n" ]] ;;
    *) return 0 ;;
  esac
}

# ── _grade_file FILE TASK_JSON → {pass, must_fail[], should_incon[]} ──────────
_grade_file() {
  local file="$1" task="$2" must_fail="[]" should_incon="[]" item
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    if ! _rubric_match "$file" "$item"; then
      local must desc; must="$(printf '%s' "$item" | jq -r '.must')"; desc="$(printf '%s' "$item" | jq -r '.desc')"
      if [[ "$must" == "true" ]]; then must_fail="$(printf '%s' "$must_fail" | jq --arg d "$desc" '. + [$d]')"
      else should_incon="$(printf '%s' "$should_incon" | jq --arg d "$desc" '. + [$d]')"; fi
    fi
  done < <(printf '%s' "$task" | jq -c '.rubric[]')
  local pass=false
  [[ "$(printf '%s' "$must_fail" | jq 'length')" -eq 0 ]] && pass=true
  jq -nc --argjson mf "$must_fail" --argjson si "$should_incon" --argjson p "$pass" \
    '{pass:$p, must_fail:$mf, should_incon:$si}'
}

case "$MODE" in
  list)
    if [[ "$OUT" == "json" ]]; then
      printf '%s' "$SUITE_JSON" | jq '[.tasks[] | {id, eidolon}]'
    else
      printf '%squality tasks%s\n' "${BOLD:-}" "${RESET:-}"
      printf '%s' "$SUITE_JSON" | jq -r '.tasks[] | "  \(.id)\t\(.eidolon)"' \
        | while IFS=$'\t' read -r id e; do printf '  %-14s %s\n' "$id" "$e"; done
    fi
    ;;

  emit)
    [[ -n "$TASK_ID" ]] || die "emit needs a <task-id> (see 'eidolons eval quality list')"
    task="$(_task "$TASK_ID")"; [[ -n "$task" ]] || die "no such task: $TASK_ID"
    eid="$(printf '%s' "$task" | jq -r '.eidolon')"
    printf '%s── quality mission %s (run via %s)%s\n\n' "${BOLD:-}" "$TASK_ID" "$eid" "${RESET:-}"
    printf '%s' "$task" | jq -r '.mission'
    printf '\n%sGrading rubric (mechanical; MUST = fail, SHOULD = inconclusive):%s\n' "${UI_DIM:-}" "${RESET:-}"
    printf '%s' "$task" | jq -r '.rubric[] | "  [\(if .must then "MUST " else "SHOULD" end)] \(.desc)"'
    printf '\nRun the mission via %s in your LLM, save the output, then:\n' "$eid"
    printf '  eidolons eval quality grade %s <output-file> [<more runs> ...]\n' "$TASK_ID"
    ;;

  grade)
    [[ -n "$TASK_ID" ]] || die "grade needs a <task-id>"
    [[ ${#FILES[@]} -gt 0 ]] || die "grade needs at least one <output-file>"
    task="$(_task "$TASK_ID")"; [[ -n "$task" ]] || die "no such task: $TASK_ID"
    eid="$(printf '%s' "$task" | jq -r '.eidolon')"
    per_file="[]"
    for f in "${FILES[@]}"; do
      [[ -f "$f" ]] || die "output file not found: $f"
      g="$(_grade_file "$f" "$task")"
      per_file="$(printf '%s' "$per_file" | jq --arg f "$f" --argjson g "$g" '. + [{file:$f} + $g]')"
    done
    K="${#FILES[@]}"
    PASSES="$(printf '%s' "$per_file" | jq '[.[] | select(.pass)] | length')"
    PASS_K=false; [[ "$PASSES" -eq "$K" ]] && PASS_K=true
    # jq division (not awk %.2f) so the value is a clean number, not a preserved
    # "0.50" literal under jq 1.7's number-literal preservation.
    PASS_AT_1="$(jq -n --argjson p "$PASSES" --argjson k "$K" '$p/$k')"

    if [[ "$OUT" == "json" ]]; then
      jq -nc --arg task "$TASK_ID" --arg eid "$eid" --argjson k "$K" --argjson passes "$PASSES" \
        --argjson passk "$PASS_K" --argjson pf "$per_file" \
        '{task:$task, eidolon:$eid, k:$k, passes:$passes, pass_at_1:($passes/$k), pass_k:$passk,
          measures:"contract-conformance (structural), not rival-comparable task-solving", per_file:$pf}'
    else
      printf '%squality grade%s  %s (%s)  —  %s independent run(s)\n' "${BOLD:-}" "${RESET:-}" "$TASK_ID" "$eid" "$K"
      printf '%s' "$per_file" | jq -r '.[] | "\(if .pass then "PASS" else "FAIL" end)\t\(.file)\t\((.must_fail|length))\t\((.should_incon|length))"' \
        | while IFS=$'\t' read -r v f mf si; do
            g="✓"; [[ "$v" == "FAIL" ]] && g="✗"
            printf '  %s %-4s %s  (must-fail=%s, should=%s)\n' "$g" "$v" "$(basename "$f")" "$mf" "$si"
          done
      # surface the MUST failures (the actionable contract violations)
      printf '%s' "$per_file" | jq -r '.[] | select(.must_fail | length > 0) | "    ✗ \(.file | split("/") | last): " + (.must_fail | join("; "))'
      printf '  %s──────────%s\n' "${UI_DIM:-}" "${RESET:-}"
      printf '  pass@1 = %s    pass^%s = %s   %s(contract-conformance, not rival task-solving)%s\n' \
        "$PASS_AT_1" "$K" "$([[ "$PASS_K" == true ]] && echo PASS || echo FAIL)" "${UI_DIM:-}" "${RESET:-}"
    fi
    [[ "$PASS_K" == true ]] && exit 0 || exit 1
    ;;
esac
exit 0
