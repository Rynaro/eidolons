#!/usr/bin/env bash
# eidolons eval baseline — regression diff over the evals/results/ scorecard store
# ═══════════════════════════════════════════════════════════════════════════
# Reads scorecards written by `eidolons eval swe --matrix <arms.json>`
# (schemas/eval-scorecard.schema.json, evals/results/README.md) and diffs the
# two most recent for a given (suite, label) — or the latest vs an explicit
# --against file. jq-only, mechanical: no LLM judge, no re-execution.
#
#   eidolons eval baseline <suite> [--label <l>] [--against <file>] [--json]
#
# Exit codes:
#   0   no regression (resolved_rate did not drop AND no task regressed)
#   5   regression detected
#   1   misuse (bad args, suite/label not found, <2 scorecards to diff)

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

NEXUS_ROOT="$(cd "$(dirname "$ROSTER_FILE")/.." && pwd)"
RESULTS_DIR="${EIDOLONS_EVAL_RESULTS_DIR:-$NEXUS_ROOT/evals/results}"

usage() {
  cat <<EOF
eidolons eval baseline — diff the two most recent evals/results/ scorecards

Usage: eidolons eval baseline <suite> [OPTIONS]

<suite>  Suite identifier — the middle segment of the scorecard filename,
         e.g. "swe-suite" or "kupo-keep-suite" (see evals/results/README.md).

Options:
  --label L      Arm label to diff (the scorecard filename's last segment).
                 If omitted and exactly one label exists in the store for
                 this suite, it is used automatically; if more than one
                 exists, --label is required.
  --against FILE Diff the latest scorecard for (suite,label) against this
                 explicit file instead of the second-most-recent stored one.
  --json         Emit the diff as JSON (default: human text).
  -h, --help     Show this help.

Diffs resolved_rate and pass_k_rate deltas plus a per-task flip table
(newly_resolved / regressed) between the OLD (earlier) and NEW (later)
scorecard. Exits 5 on regression (resolved_rate dropped, or any previously-
resolved task regressed) so it composes as a CI gate; 0 otherwise.
EOF
}

SUITE=""
LABEL=""
AGAINST=""
OUT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)   LABEL="${2:-}"; shift 2 ;;
    --against) AGAINST="${2:-}"; shift 2 ;;
    --json)    OUT="json"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        die "Unknown option: $1 (see 'eidolons eval baseline --help')" ;;
    *)
      if [[ -z "$SUITE" ]]; then SUITE="$1"; else die "Unexpected extra argument: $1"; fi
      shift
      ;;
  esac
done

[[ -n "$SUITE" ]] || { usage >&2; die "eval baseline needs a <suite> argument (see 'eidolons eval baseline --help')"; }
[[ -d "$RESULTS_DIR" ]] || die "no scorecard store found at $RESULTS_DIR — run 'eidolons eval swe --matrix <arms.json>' first"

# ── Resolve --label when omitted: exactly one distinct label for this suite ──
if [[ -z "$LABEL" ]]; then
  labels=""
  for f in "$RESULTS_DIR"/*"-${SUITE}-"*.scorecard.json; do
    [[ -f "$f" ]] || continue
    bn="$(basename "$f" .scorecard.json)"
    lbl="${bn#??????????-${SUITE}-}"
    [[ -n "$lbl" && "$lbl" != "$bn" ]] && labels="${labels}${lbl}"$'\n'
  done
  labels="$(printf '%s' "$labels" | sort -u | grep -v '^$' || true)"
  n_labels="$(printf '%s\n' "$labels" | grep -c . || true)"
  if [[ "$n_labels" -eq 0 ]]; then
    die "no scorecards found for suite '$SUITE' in $RESULTS_DIR"
  elif [[ "$n_labels" -gt 1 ]]; then
    die "multiple arm labels found for suite '$SUITE' in $RESULTS_DIR: $(printf '%s' "$labels" | tr '\n' ' ') — pass --label <l>"
  fi
  LABEL="$labels"
fi

# ── Gather matching scorecards, newest first (date-prefixed filenames sort
# chronologically as strings) ────────────────────────────────────────────────
files=""
for f in "$RESULTS_DIR"/*"-${SUITE}-${LABEL}.scorecard.json"; do
  [[ -f "$f" ]] && files="${files}${f}"$'\n'
done
files="$(printf '%s' "$files" | grep -v '^$' | sort -r || true)"
n_files="$(printf '%s\n' "$files" | grep -c . || true)"
[[ -z "$files" ]] && n_files=0

NEW_FILE=""
OLD_FILE=""
if [[ -n "$AGAINST" ]]; then
  [[ -f "$AGAINST" ]] || die "--against file not found: $AGAINST"
  [[ "$n_files" -ge 1 ]] || die "no scorecards found for suite='$SUITE' label='$LABEL' in $RESULTS_DIR"
  NEW_FILE="$(printf '%s\n' "$files" | sed -n '1p')"
  OLD_FILE="$AGAINST"
else
  [[ "$n_files" -ge 2 ]] || die "need >= 2 scorecards for suite='$SUITE' label='$LABEL' to diff (found $n_files) — run 'eidolons eval swe --matrix' again on a later day, or pass --against <file>"
  NEW_FILE="$(printf '%s\n' "$files" | sed -n '1p')"
  OLD_FILE="$(printf '%s\n' "$files" | sed -n '2p')"
fi

new_json="$(jq -c '.' "$NEW_FILE" 2>/dev/null)" || die "could not parse scorecard JSON: $NEW_FILE"
old_json="$(jq -c '.' "$OLD_FILE" 2>/dev/null)" || die "could not parse scorecard JSON: $OLD_FILE"

DIFF_JQ="$(cat <<'JQEOF'
($old.tasks | map({(.id): .resolved}) | add // {}) as $om
| ($new.tasks | map({(.id): .resolved}) | add // {}) as $nm
| {
    suite: $new.suite,
    label: $new.arm.label,
    old_file: $oldf,
    new_file: $newf,
    old_started_at: $old.started_at,
    new_started_at: $new.started_at,
    resolved_rate_delta: ($new.resolved_rate - $old.resolved_rate),
    pass_k_rate_delta: ($new.pass_k_rate - $old.pass_k_rate),
    newly_resolved: [ ($nm | keys[]) as $id | select((($om[$id]) // false) == false and (($nm[$id]) // false) == true) | $id ],
    regressed:      [ ($om | keys[]) as $id | select((($om[$id]) // false) == true  and (($nm[$id]) // false) == false) | $id ]
  }
JQEOF
)"
diff_doc="$(jq -nc --argjson old "$old_json" --argjson new "$new_json" \
  --arg oldf "$OLD_FILE" --arg newf "$NEW_FILE" "$DIFF_JQ")"

regressed_n="$(printf '%s' "$diff_doc" | jq -r '.regressed | length')"
rate_delta="$(printf '%s' "$diff_doc" | jq -r '.resolved_rate_delta')"
is_regression=false
awk "BEGIN{exit !($rate_delta < 0)}" && is_regression=true
[[ "$regressed_n" -gt 0 ]] && is_regression=true

if [[ "$OUT" == "json" ]]; then
  printf '%s' "$diff_doc" | jq --argjson reg "$([[ "$is_regression" == true ]] && echo true || echo false)" '. + {regression: $reg}'
else
  printf '%seidolons eval baseline%s  suite=%s  label=%s\n' "${BOLD:-}" "${RESET:-}" "$SUITE" "$LABEL"
  printf '  old: %s (%s)\n' "$(basename "$OLD_FILE")" "$(printf '%s' "$old_json" | jq -r '.started_at')"
  printf '  new: %s (%s)\n' "$(basename "$NEW_FILE")" "$(printf '%s' "$new_json" | jq -r '.started_at')"
  printf '  Δresolved_rate=%s  Δpass_k_rate=%s\n' \
    "$(printf '%s' "$diff_doc" | jq -r '.resolved_rate_delta')" \
    "$(printf '%s' "$diff_doc" | jq -r '.pass_k_rate_delta')"
  printf '  newly_resolved: %s\n' "$(printf '%s' "$diff_doc" | jq -r '.newly_resolved | join(", ")')"
  printf '  regressed:      %s\n' "$(printf '%s' "$diff_doc" | jq -r '.regressed | join(", ")')"
  if [[ "$is_regression" == true ]]; then
    warn "REGRESSION (resolved_rate_delta=${rate_delta}, regressed_tasks=${regressed_n}) — exit 5"
  else
    ok "no regression"
  fi
fi

[[ "$is_regression" == true ]] && exit 5
exit 0
