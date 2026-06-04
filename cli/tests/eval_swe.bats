#!/usr/bin/env bats
# cli/tests/eval_swe.bats — `eidolons eval swe` SWE-task-solving harness.
# Drives the #9 sandbox loop over a task suite. The bundled suite is a HARNESS
# SELF-TEST (gold-fix reference, deterministic, no model/Docker) — these tests
# verify the orchestration, the honest scope framing, the unresolved/no-silent-cap
# path, the --min CI gate, and the isolation policy. Pure sh/coreutils/git only.

load helpers

# A throwaway suite whose gold_fix does NOT satisfy the test (always unresolved).
_bad_suite() {
  cat > "$1" <<'YAML'
swe_version: "1.0"
tasks:
  - id: never
    description: "fix never satisfies the test"
    setup: |
      git init -q && git config user.email t@e.x && git config user.name t
      echo broken > state.txt
      git add -A && git commit -qm init
    test: "grep -q fixed state.txt"
    gold_fix: |
      echo still-broken > state.txt
YAML
}

@test "eval swe: bundled smoke suite validates" {
  run eidolons eval swe --validate-suite
  [ "$status" -eq 0 ]
  [[ "$output" =~ "suite valid" ]]
}

@test "eval swe: --list shows the task ids" {
  run eidolons eval swe --list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "smoke-greet" ]]
  [[ "$output" =~ "smoke-exit-code" ]]
}

@test "eval swe: smoke suite resolves every task via the gold-fix reference" {
  run eidolons eval swe --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.total')" -ge 2 ]
  [ "$(echo "$output" | jq -r '.resolved')" = "$(echo "$output" | jq -r '.total')" ]
  [ "$(echo "$output" | jq -r '.resolved_rate')" = "1" ]
  [ "$(echo "$output" | jq -r '.mode')" = "smoke" ]
  [ "$(echo "$output" | jq -r '.model_tokens')" = "0" ]
}

@test "eval swe: text output carries the honest scope banner (not a capability claim)" {
  run eidolons eval swe
  [ "$status" -eq 0 ]
  [[ "$output" =~ "HARNESS SELF-TEST" ]]
  [[ "$output" =~ "NOT a model solving unseen tasks" ]]
}

@test "eval swe: an unfixable task is recorded UNRESOLVED (no silent pass)" {
  _bad_suite "$BATS_TEST_TMPDIR/bad.yaml"
  run eidolons eval swe --suite-file "$BATS_TEST_TMPDIR/bad.yaml" --max-attempts 2 --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.resolved')" = "0" ]
  [ "$(echo "$output" | jq -r '.resolved_rate')" = "0" ]
  [ "$(echo "$output" | jq -r '.tasks[0].resolved')" = "false" ]
}

@test "eval swe: --min gates on resolved_rate (pass on smoke, fail on unfixable)" {
  run eidolons eval swe --min 100
  [ "$status" -eq 0 ]
  _bad_suite "$BATS_TEST_TMPDIR/bad.yaml"
  run eidolons eval swe --suite-file "$BATS_TEST_TMPDIR/bad.yaml" --max-attempts 2 --min 100
  [ "$status" -eq 1 ]
}

@test "eval swe: a real --fix-hook without isolation is refused (R8-03)" {
  run eidolons eval swe --fix-hook 'true' --max-attempts 1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "via" || "$output" =~ "isolation" || "$output" =~ "untrusted" ]]
}

@test "eval swe: --validate-suite rejects a malformed suite" {
  printf 'swe_version: "1.0"\ntasks:\n  - id: x\n    setup: "echo hi"\n' > "$BATS_TEST_TMPDIR/no-test.yaml"
  run eidolons eval swe --suite-file "$BATS_TEST_TMPDIR/no-test.yaml" --validate-suite
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing test" || "$output" =~ "invalid" ]]
}

@test "eval swe: smoke mode requires gold_fix (caught by --validate-suite)" {
  printf 'swe_version: "1.0"\ntasks:\n  - id: x\n    setup: "echo hi"\n    test: "true"\n' > "$BATS_TEST_TMPDIR/no-gold.yaml"
  run eidolons eval swe --suite-file "$BATS_TEST_TMPDIR/no-gold.yaml" --validate-suite
  [ "$status" -eq 1 ]
  [[ "$output" =~ "gold_fix" ]]
}

@test "eval: swe is a recognised subcommand + listed in help" {
  run eidolons eval --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "swe" ]]
  run eidolons eval swe --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SWE-task-solving" ]]
}
