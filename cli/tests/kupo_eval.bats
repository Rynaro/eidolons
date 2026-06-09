#!/usr/bin/env bats
# cli/tests/kupo_eval.bats — the Kupo KEEP-cohort eval suite (the executor's
# ship-gate INSTRUMENT). Smoke mode proves the orchestration over Kupo-shaped
# KEEP tasks end-to-end; the behavioral number (a real haiku --fix-hook) is what
# flips Kupo in_construction → shipped and is run/measured out-of-band.

load helpers

SUITE_REL="evals/kupo-keep-suite.yaml"

@test "kupo eval: suite exists and is valid YAML" {
  [ -f "$EIDOLONS_ROOT/$SUITE_REL" ]
  run yq eval '.' "$EIDOLONS_ROOT/$SUITE_REL"
  [ "$status" -eq 0 ]
}

@test "kupo eval: suite passes --validate-suite (smoke mode needs gold_fix per task)" {
  run eidolons eval swe --suite-file "$EIDOLONS_ROOT/$SUITE_REL" --validate-suite
  [ "$status" -eq 0 ]
  [[ "$output" =~ "suite valid" ]]
}

@test "kupo eval: every task id is a KEEP class (keep- prefix) — REFUSE/ESCALATE absent by construction" {
  run bash -c "yq -r '.tasks[].id' '$EIDOLONS_ROOT/$SUITE_REL' | grep -cv '^keep-'"
  [ "$output" = "0" ]
}

@test "kupo eval: smoke run resolves all tasks (orchestration proof)" {
  run eidolons eval swe --suite-file "$EIDOLONS_ROOT/$SUITE_REL" --json
  [ "$status" -eq 0 ]
  total="$(echo "$output" | jq -r '.total')"
  [ "$(echo "$output" | jq -r '.resolved')" = "$total" ]
  [ "$(echo "$output" | jq -r '.resolved_rate')" = "1" ]
}

@test "kupo eval: --min CI gate passes at smoke 100%" {
  run eidolons eval swe --suite-file "$EIDOLONS_ROOT/$SUITE_REL" --min 100
  [ "$status" -eq 0 ]
}
