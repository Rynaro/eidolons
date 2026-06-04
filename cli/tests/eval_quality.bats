#!/usr/bin/env bats
# cli/tests/eval_quality.bats — human-in-the-loop quality eval (roadmap N1 instrument).
# The CLI never embeds a model / LLM-judge: it grades a saved Eidolon output
# against mechanical grep rubrics and reports pass^k. Measures contract-
# conformance quality, NOT rival-comparable task-solving.

load helpers

# A FORGE output that SATISFIES the Q-FORGE-1 contract.
_good_forge() {
  cat > "$1" <<'EOF'
# Reasoning report: monorepo vs polyrepo
Hypothesis 1: a monorepo simplifies cross-service refactors.
Option 2: polyrepo isolates blast radius and release cadence.
Alternative 3: a hybrid with a shared core library.
Verdict: I recommend polyrepo for this team.
Reversal conditions: this would change if the team drops below 3 services; revisit if CI cost dominates.
EOF
}
# A FORGE output that VIOLATES the contract (no hypotheses, no reversal).
_bad_forge() { printf 'Just use a monorepo, it is simpler.\n' > "$1"; }

@test "eval quality: --help exits 0" {
  run eidolons eval quality --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "contract-conformance" ]]
}

@test "eval quality: unknown mode errors" {
  run eidolons eval quality bogus
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unknown quality mode" ]]
}

@test "eval quality list: lists the shipped tasks (one per Eidolon)" {
  run eidolons eval quality list --json
  [ "$status" -eq 0 ]
  # the shipped suite covers all six methodology Eidolons
  for e in atlas spectra apivr idg forge vigil; do
    [ "$(echo "$output" | jq -r --arg e "$e" '[.[] | select(.eidolon==$e)] | length')" -ge 1 ]
  done
}

@test "eval quality emit: prints the mission + rubric for a task" {
  run eidolons eval quality emit Q-FORGE-1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "monorepo" ]]
  [[ "$output" =~ "MUST" ]]
}

@test "eval quality emit: unknown task errors" {
  run eidolons eval quality emit Q-NOPE
  [ "$status" -ne 0 ]
}

@test "eval quality grade: a conformant output passes (exit 0)" {
  _good_forge "$BATS_TEST_TMPDIR/g.md"
  run eidolons eval quality grade Q-FORGE-1 "$BATS_TEST_TMPDIR/g.md" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.pass_k')" = "true" ]
  [ "$(echo "$output" | jq -r '.passes')" = "1" ]
}

@test "eval quality grade: a non-conformant output fails (exit 1) with the MUST violations" {
  _bad_forge "$BATS_TEST_TMPDIR/b.md"
  run eidolons eval quality grade Q-FORGE-1 "$BATS_TEST_TMPDIR/b.md"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "FAIL" ]]
  [[ "$output" =~ "hypotheses" || "$output" =~ "reversal" ]]
}

@test "eval quality grade: pass^k over k runs — one bad run fails the whole (R6-F08)" {
  _good_forge "$BATS_TEST_TMPDIR/g.md"
  _bad_forge "$BATS_TEST_TMPDIR/b.md"
  run eidolons eval quality grade Q-FORGE-1 "$BATS_TEST_TMPDIR/g.md" "$BATS_TEST_TMPDIR/b.md" --json
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.k')" = "2" ]
  [ "$(echo "$output" | jq -r '.pass_k')" = "false" ]
  [ "$(echo "$output" | jq -r '.pass_at_1')" = "0.5" ]
}

@test "eval quality grade: pass^k=true when all k runs conform" {
  _good_forge "$BATS_TEST_TMPDIR/g1.md"
  _good_forge "$BATS_TEST_TMPDIR/g2.md"
  run eidolons eval quality grade Q-FORGE-1 "$BATS_TEST_TMPDIR/g1.md" "$BATS_TEST_TMPDIR/g2.md" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.pass_k')" = "true" ]
  [ "$(echo "$output" | jq -r '.pass_at_1')" = "1" ]
}

@test "eval quality grade: missing output file errors" {
  run eidolons eval quality grade Q-FORGE-1 /no/such/file.md
  [ "$status" -ne 0 ]
}

@test "eval quality grade: regex rubric — ATLAS needs a path:line anchor" {
  good="$BATS_TEST_TMPDIR/atlas_good.md"
  bad="$BATS_TEST_TMPDIR/atlas_bad.md"
  printf 'Auth is enforced in src/middleware/auth.py:42 (confidence: H). DECISION_TARGET: hook into src/router.py.\n' > "$good"
  printf 'Auth is enforced somewhere in the middleware. It should hook into the router.\n' > "$bad"
  run eidolons eval quality grade Q-ATLAS-1 "$good"
  [ "$status" -eq 0 ]
  run eidolons eval quality grade Q-ATLAS-1 "$bad"
  [ "$status" -eq 1 ]
}

@test "eval quality grade: the honest scope is labelled (not rival task-solving)" {
  _good_forge "$BATS_TEST_TMPDIR/g.md"
  run eidolons eval quality grade Q-FORGE-1 "$BATS_TEST_TMPDIR/g.md" --json
  [[ "$(echo "$output" | jq -r '.measures')" =~ "not rival-comparable" ]]
}
