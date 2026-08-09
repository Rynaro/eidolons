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

@test "eval routing: the recall arm scores 100% (its cases must be able to fail)" {
  # The public test above asserts public ACCURACY; `--suite all` below asserts
  # only the task COUNT. Nothing asserted recall accuracy, so every recall case
  # could go red with the whole repo green — including N-C07..N-C12, which
  # `chain-scout-debug-fix` cites as the evidence for AC-1 and AC-2. Evidence
  # that cannot fail is not evidence.
  #
  # Falsifiable, demonstrated: dropping the trailing `idg` from
  # `scout-diagnose-fix` takes recall to 80/83 while public stays 15/15.
  #
  # Three assertions, each with a DIFFERENT failure mode. Their natures differ
  # and an earlier comment here got this wrong, claiming the whole bar was
  # "derived from the suite file" — lifted from the neighbouring test, which
  # genuinely does read the file. This one did not. Stated precisely:
  #
  #   1. total == the recall arm's length in the suite file — DERIVED. Catches a
  #      runner or loader that silently drops tasks it was handed.
  #   2. total >= 83 — a HARDCODED FLOOR, and deliberately so. `--suite all`
  #      below derives both sides of ITS comparison from the same file, so that
  #      comparison is structurally blind to the file shrinking. This floor is
  #      the only guard in the recall band 49-82; below 49 the union floor at
  #      the end of that test (`_expected >= 68`) also fires. Measured, not
  #      assumed: with this floor deleted, recall 60 is green and recall 40 is
  #      red. Every realistic silent shrink lives in the 49-82 band.
  #
  #      Its coverage, MEASURED rather than asserted: arm 77 RED, 82 RED,
  #      83 green, 84 green, 90 green. So it catches a drop BELOW the floor and
  #      nothing else — grow the arm to 90 and shrink it back to 84 and six
  #      tasks vanish undetected. The floor does NOT rise on its own. Growing
  #      the arm means bumping this number in the same commit; that is the
  #      whole contract, and it is a ratchet, not a derivation.
  #   3. passed == total — ACCURACY, and this one does rise by itself: add a
  #      task and it must pass too.
  _suite="$EIDOLONS_ROOT/evals/routing-suite.yaml"
  _declared="$(yq -r '.suites.recall | length' "$_suite" 2>/dev/null \
               || python3 -c 'import yaml,sys; print(len(yaml.safe_load(open(sys.argv[1]))["suites"]["recall"]))' "$_suite")"
  run eidolons eval routing --suite recall --json
  [ "$status" -eq 0 ]
  _total="$(echo "$output" | jq -r '.total')"
  [ "$_total" = "$_declared" ]
  [ "$_total" -ge 83 ]
  [ "$(echo "$output" | jq -r '.passed')" = "$_total" ]
}

@test "eval routing: --suite all covers public + holdout + recall" {
  run eidolons eval routing --suite all --json
  [ "$status" -eq 0 ]
  # 15 public + 4 holdout + 83 recall (the recall arm has grown; its accuracy is
  # asserted by the test above, its membership here).
  # Derived from the suite file rather than hardcoded, so adding a task updates
  # the expectation with it and this stays a coverage check, not a stale count.
  _expected="$(yq -r '[.suites[][]] | length' "$EIDOLONS_ROOT/evals/routing-suite.yaml" 2>/dev/null \
               || python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(sum(len(v) for v in d["suites"].values()))' "$EIDOLONS_ROOT/evals/routing-suite.yaml")"
  [ "$(echo "$output" | jq -r '.total')" = "$_expected" ]
  [ "$_expected" -ge 68 ]
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
  # the router sends a fix to vivi (default coder), not idg — a mislabelled miss
  [ "$(echo "$output" | jq -r '.passed')" = "0" ]
  [ "$(echo "$output" | jq -r '.failures[0].actual.selected[0]')" = "vivi" ]
}
