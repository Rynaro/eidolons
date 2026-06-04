#!/usr/bin/env bats
# cli/tests/eval.bats — the Eidolons eval harness (roadmap #7, the verdict-flipper).
# The ROUTING benchmark is fully automated because `eidolons run` is deterministic:
# no LLM, no human, reproducible. These tests assert the harness measures + grades
# correctly, self-validates its suite, and gates on accuracy.

load helpers

@test "eval: --help exits 0" {
  run eidolons eval --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "labelled ground truth" ]]
}

@test "eval: unknown subcommand errors" {
  run eidolons eval bogus
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unknown subcommand" ]]
}

@test "eval routing: the shipped public suite scores (deterministic, no LLM)" {
  run eidolons eval routing --suite public --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.total')" = "15" ]
  [ "$(echo "$output" | jq -r '.deterministic')" = "true" ]
  [ "$(echo "$output" | jq -r '.cost_tokens')" = "0" ]
  # the deterministic router is accurate on the shipped ground-truth set
  [ "$(echo "$output" | jq -r '.passed')" = "15" ]
}

@test "eval routing: --suite all covers public + holdout" {
  run eidolons eval routing --suite all --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.total')" = "19" ]
}

@test "eval routing: by-category breakdown is present" {
  run eidolons eval routing --json
  [ "$(echo "$output" | jq -r '.by_category | length')" -ge 8 ]
  [ "$(echo "$output" | jq -r '[.by_category[].category] | index("refusal")')" != "null" ]
}

@test "eval routing: determinism — same suite ⇒ byte-identical scorecard (I-C6)" {
  run eidolons eval routing --suite all --json
  first="$output"
  run eidolons eval routing --suite all --json
  [ "$first" = "$output" ]
}

@test "eval routing --validate-suite: the shipped suite passes its own self-test" {
  run eidolons eval routing --validate-suite
  [ "$status" -eq 0 ]
  [[ "$output" =~ "passed the task-validity self-test" ]]
}

@test "eval routing --validate-suite: catches a malformed suite" {
  bad="$BATS_TEST_TMPDIR/bad.yaml"
  cat > "$bad" <<'YML'
eval_version: "1.0"
suites:
  public:
    - id: B-1
      prompt: "do something"
      expect: { decision: teleport, selected: [nonexistent_eidolon] }
YML
  run eidolons eval routing --validate-suite --suite-file "$bad"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "invalid decision" || "$output" =~ "not in roster" || "$output" =~ "missing category" ]]
}

@test "eval routing --validate-suite: catches duplicate task ids" {
  bad="$BATS_TEST_TMPDIR/dup.yaml"
  cat > "$bad" <<'YML'
eval_version: "1.0"
suites:
  public:
    - id: D-1
      category: discovery
      prompt: "map a"
      expect: { decision: dispatch, selected: [atlas] }
    - id: D-1
      category: discovery
      prompt: "map b"
      expect: { decision: dispatch, selected: [atlas] }
YML
  run eidolons eval routing --validate-suite --suite-file "$bad"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "duplicate task ids" ]]
}

@test "eval routing --min: gate passes when accuracy meets the floor" {
  run eidolons eval routing --suite public --min 90
  [ "$status" -eq 0 ]
}

@test "eval routing --min: gate fails (exit 1) when accuracy is below the floor" {
  run eidolons eval routing --suite public --min 101
  [ "$status" -eq 1 ]
}

@test "eval routing: a custom suite with a wrong label is scored as a miss" {
  bad="$BATS_TEST_TMPDIR/miss.yaml"
  cat > "$bad" <<'YML'
eval_version: "1.0"
suites:
  public:
    - id: M-1
      category: bugfix
      prompt: "Fix the off-by-one bug"
      expect: { decision: dispatch, selected: [idg] }
YML
  run eidolons eval routing --suite-file "$bad" --json
  [ "$status" -eq 0 ]
  # the router sends a fix to apivr, not idg — so this mislabelled task is a miss
  [ "$(echo "$output" | jq -r '.passed')" = "0" ]
  [ "$(echo "$output" | jq -r '.failures[0].actual.selected[0]')" = "apivr" ]
}
