#!/usr/bin/env bats
# cli/tests/eval_matrix.bats — Wave-5 measurement instruments:
#   - `eidolons eval swe --matrix <arms.json>` (matrix runner + scorecard store)
#   - `eidolons eval baseline <suite>` (regression diff over the store)
#   - evals/hooks/{keep-bare,keep-system}.sh (shellcheck-clean + guard-only)
#
# The matrix/baseline tests NEVER touch the real evals/results/ store — every
# test sets EIDOLONS_EVAL_RESULTS_DIR to an isolated tmp dir (see eval_swe.sh /
# eval_baseline.sh headers). The hook tests NEVER invoke `claude` — they only
# exercise the EIDOLONS_EVAL_MODEL guard and the missing-binary guard, both of
# which return before any model call, mirroring eval_compliance.bats's
# EIDOLONS_COMPLIANCE_NO_LIVE hard safety-net discipline (never spawn a real,
# billed model call in tests).

load helpers

_mx_results_dir() {
  RESULTS_DIR="$BATS_TEST_TMPDIR/results"
  export EIDOLONS_EVAL_RESULTS_DIR="$RESULTS_DIR"
}

_mx_two_arms() {  # $1 = path to write arms.json to
  cat > "$1" <<'JSON'
{
  "arms": [
    {"label": "arm-a", "fix_hook": "true", "env": {}, "control": true},
    {"label": "arm-b", "fix_hook": "true", "env": {"FOO": "bar"}, "control": false}
  ]
}
JSON
}

# jq-only structural check against schemas/eval-scorecard.schema.json's
# required shape (mirrors the rest of the suite's "schema-valid" convention —
# no external JSON-Schema validator dependency; see eval_compliance.bats /
# telemetry_export.bats for the same jq-assertion pattern).
_assert_scorecard_schema_valid() {
  local f="$1"
  [ -f "$f" ]
  run jq -e '
    (.schema_version | type == "string") and
    (.suite | type == "string") and
    (.arm.label | type == "string") and
    (.arm.fix_hook | type == "string") and
    (.arm.control | type == "boolean") and
    (.started_at | type == "string") and
    (.k | type == "number") and
    (.tasks | type == "array") and
    (.tasks | all(.[]; (.id|type=="string") and (.resolved|type=="boolean") and (.passes|type=="number") and (.attempts|type=="number"))) and
    (.resolved_rate | type == "number") and
    (.pass_k_rate | type == "number") and
    (.harness.nexus_version | type == "string") and
    (.harness.smoke | type == "boolean")
  ' "$f"
  [ "$status" -eq 0 ]
}

@test "eval matrix: --smoke over the 2-task swe-suite writes 2 scorecards + 1 matrix summary, all schema-valid" {
  _mx_results_dir
  local arms="$BATS_TEST_TMPDIR/arms.json"
  _mx_two_arms "$arms"

  run eidolons eval swe --matrix "$arms" --smoke --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.schema_version and .suite and .started_at and .arms and .summary' >/dev/null

  local sc_a="$RESULTS_DIR/$(date -u '+%Y-%m-%d')-swe-suite-arm-a.scorecard.json"
  local sc_b="$RESULTS_DIR/$(date -u '+%Y-%m-%d')-swe-suite-arm-b.scorecard.json"
  local mx="$RESULTS_DIR/$(date -u '+%Y-%m-%d')-swe-suite-matrix.json"

  _assert_scorecard_schema_valid "$sc_a"
  _assert_scorecard_schema_valid "$sc_b"
  [ -f "$mx" ]

  # Smoke arms resolve every task via gold_fix (harness self-test, honest scope).
  [ "$(jq -r '.harness.smoke' "$sc_a")" = "true" ]
  [ "$(jq -r '.resolved_rate' "$sc_a")" = "1" ]
  [ "$(jq -r '.arm.control' "$sc_a")" = "true" ]
  [ "$(jq -r '.arm.control' "$sc_b")" = "false" ]
  [ "$(jq -r '.arm.env.FOO' "$sc_b")" = "bar" ]

  # Matrix summary: pairwise vs the control arm, no flips (both arms resolve
  # every task under smoke).
  [ "$(jq -r '.summary.control' "$mx")" = "arm-a" ]
  [ "$(jq -r '.summary.comparisons | length' "$mx")" = "1" ]
  [ "$(jq -r '.summary.comparisons[0].label' "$mx")" = "arm-b" ]
  [ "$(jq -r '.summary.comparisons[0].resolved_rate_delta' "$mx")" = "0" ]
  [ "$(jq -r '.summary.comparisons[0].regressed | length' "$mx")" = "0" ]
}

@test "eval matrix: --no-store writes nothing to the results dir" {
  _mx_results_dir
  local arms="$BATS_TEST_TMPDIR/arms.json"
  _mx_two_arms "$arms"

  run eidolons eval swe --matrix "$arms" --smoke --no-store --json
  [ "$status" -eq 0 ]
  [ ! -d "$RESULTS_DIR" ]
}

@test "eval matrix: text output prints the arm table + control comparison" {
  _mx_results_dir
  local arms="$BATS_TEST_TMPDIR/arms.json"
  _mx_two_arms "$arms"

  run eidolons eval swe --matrix "$arms" --smoke
  [ "$status" -eq 0 ]
  [[ "$output" =~ "arm-a" ]]
  [[ "$output" =~ "arm-b" ]]
  [[ "$output" =~ "[control]" ]]
}

@test "eval matrix: an arms file with no control:true arm skips the comparison (warns, still exits 0)" {
  _mx_results_dir
  local arms="$BATS_TEST_TMPDIR/arms.json"
  cat > "$arms" <<'JSON'
{"arms": [{"label": "solo", "fix_hook": "true"}]}
JSON
  run eidolons eval swe --matrix "$arms" --smoke --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.summary.control')" = "null" ]
  [ "$(echo "$output" | jq -r '.summary.comparisons | length')" = "0" ]
}

@test "eval matrix: arms file missing a required field is rejected" {
  _mx_results_dir
  local arms="$BATS_TEST_TMPDIR/bad-arms.json"
  cat > "$arms" <<'JSON'
{"arms": [{"label": "no-hook"}]}
JSON
  run eidolons eval swe --matrix "$arms" --smoke
  [ "$status" -ne 0 ]
  [[ "$output" =~ "missing fix_hook" ]]
}

@test "eval matrix: duplicate arm labels are rejected" {
  _mx_results_dir
  local arms="$BATS_TEST_TMPDIR/dup-arms.json"
  cat > "$arms" <<'JSON'
{"arms": [{"label": "x", "fix_hook": "true"}, {"label": "x", "fix_hook": "true"}]}
JSON
  run eidolons eval swe --matrix "$arms" --smoke
  [ "$status" -ne 0 ]
  [[ "$output" =~ "duplicate arm label" ]]
}

@test "eval: baseline is a recognised subcommand + listed in help" {
  run eidolons eval --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "baseline" ]]
  run eidolons eval baseline --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "baseline" ]]
}

# ─── eval baseline: crafted-fixture exit-0 / exit-5 paths ─────────────────────

_bl_scorecard() {  # $1=path $2=date $3=resolved_t1 $4=resolved_t2 $5=rate
  cat > "$1" <<EOF
{"schema_version":"1.0","suite":"swe-suite","arm":{"label":"arm-a","fix_hook":"true","env":{},"control":true},
 "started_at":"${2}T00:00:00Z","k":1,
 "tasks":[{"id":"t1","resolved":${3},"passes":$([ "${3}" = "true" ] && echo 1 || echo 0),"attempts":1},
          {"id":"t2","resolved":${4},"passes":$([ "${4}" = "true" ] && echo 1 || echo 0),"attempts":1}],
 "resolved_rate":${5},"pass_k_rate":${5},
 "harness":{"nexus_version":"1.0.0","smoke":true}}
EOF
}

@test "eval baseline: no regression (rate steady, no task flips backward) exits 0" {
  _mx_results_dir
  mkdir -p "$RESULTS_DIR"
  _bl_scorecard "$RESULTS_DIR/2026-06-30-swe-suite-arm-a.scorecard.json" 2026-06-30 true false 0.5
  _bl_scorecard "$RESULTS_DIR/2026-07-01-swe-suite-arm-a.scorecard.json" 2026-07-01 true true 1

  run eidolons eval baseline swe-suite --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.regression')" = "false" ]
  [ "$(echo "$output" | jq -r '.newly_resolved[0]')" = "t2" ]
}

@test "eval baseline: a regressed task (old resolved, new unresolved) exits 5" {
  _mx_results_dir
  mkdir -p "$RESULTS_DIR"
  _bl_scorecard "$RESULTS_DIR/2026-06-30-swe-suite-arm-a.scorecard.json" 2026-06-30 true true 1
  _bl_scorecard "$RESULTS_DIR/2026-07-01-swe-suite-arm-a.scorecard.json" 2026-07-01 true false 0.5

  run eidolons eval baseline swe-suite --json
  [ "$status" -eq 5 ]
  [ "$(echo "$output" | jq -r '.regression')" = "true" ]
  [ "$(echo "$output" | jq -r '.regressed[0]')" = "t2" ]
}

@test "eval baseline: resolved_rate drop with no per-task flip still counts as a regression (exit 5)" {
  _mx_results_dir
  mkdir -p "$RESULTS_DIR"
  _bl_scorecard "$RESULTS_DIR/2026-06-30-swe-suite-arm-a.scorecard.json" 2026-06-30 true true 1
  _bl_scorecard "$RESULTS_DIR/2026-07-01-swe-suite-arm-a.scorecard.json" 2026-07-01 true true 0.9

  run eidolons eval baseline swe-suite
  [ "$status" -eq 5 ]
  [[ "$output" =~ "REGRESSION" ]]
}

@test "eval baseline: --against diffs the latest scorecard vs an explicit file" {
  _mx_results_dir
  mkdir -p "$RESULTS_DIR"
  local against="$BATS_TEST_TMPDIR/external-baseline.scorecard.json"
  _bl_scorecard "$against" 2026-01-01 true false 0.5
  _bl_scorecard "$RESULTS_DIR/2026-07-01-swe-suite-arm-a.scorecard.json" 2026-07-01 true true 1

  run eidolons eval baseline swe-suite --against "$against" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.old_file')" = "$against" ]
}

@test "eval baseline: fewer than 2 scorecards for (suite,label) is a misuse error (exit 1)" {
  _mx_results_dir
  mkdir -p "$RESULTS_DIR"
  _bl_scorecard "$RESULTS_DIR/2026-07-01-swe-suite-arm-a.scorecard.json" 2026-07-01 true true 1

  run eidolons eval baseline swe-suite
  [ "$status" -eq 1 ]
  [[ "$output" =~ "need >= 2 scorecards" ]]
}

@test "eval baseline: multiple labels for a suite requires --label" {
  _mx_results_dir
  mkdir -p "$RESULTS_DIR"
  _bl_scorecard "$RESULTS_DIR/2026-06-30-swe-suite-arm-a.scorecard.json" 2026-06-30 true true 1
  cat > "$RESULTS_DIR/2026-06-30-swe-suite-arm-b.scorecard.json" <<'EOF'
{"schema_version":"1.0","suite":"swe-suite","arm":{"label":"arm-b","fix_hook":"true","env":{},"control":false},
 "started_at":"2026-06-30T00:00:00Z","k":1,
 "tasks":[{"id":"t1","resolved":true,"passes":1,"attempts":1}],
 "resolved_rate":1,"pass_k_rate":1,
 "harness":{"nexus_version":"1.0.0","smoke":true}}
EOF

  run eidolons eval baseline swe-suite
  [ "$status" -eq 1 ]
  [[ "$output" =~ "pass --label" ]]
}

# ─── evals/hooks/*.sh: shellcheck-clean + guard-only (NEVER invoke claude) ─────

@test "hooks: keep-bare.sh and keep-system.sh are shellcheck -x -S error clean" {
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not on PATH"
  run shellcheck -x -S error "$EIDOLONS_ROOT/evals/hooks/keep-bare.sh" "$EIDOLONS_ROOT/evals/hooks/keep-system.sh"
  [ "$status" -eq 0 ]
}

@test "hooks: keep-bare.sh refuses to run without EIDOLONS_EVAL_MODEL (never reaches claude)" {
  run env -u EIDOLONS_EVAL_MODEL bash "$EIDOLONS_ROOT/evals/hooks/keep-bare.sh"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "EIDOLONS_EVAL_MODEL" ]]
}

@test "hooks: keep-system.sh refuses to run without EIDOLONS_EVAL_MODEL (never reaches claude)" {
  run env -u EIDOLONS_EVAL_MODEL bash "$EIDOLONS_ROOT/evals/hooks/keep-system.sh"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "EIDOLONS_EVAL_MODEL" ]]
}

@test "hooks: keep-bare.sh with EIDOLONS_EVAL_MODEL set but no 'claude' binary on PATH never attempts a call" {
  local fakepath
  fakepath="$(dirname "$(command -v bash)")"
  run env -i PATH="$fakepath" EIDOLONS_EVAL_MODEL="haiku" bash "$EIDOLONS_ROOT/evals/hooks/keep-bare.sh"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "claude" ]]
  [[ "$output" =~ "not found on PATH" ]]
}

@test "hooks: keep-system.sh with EIDOLONS_EVAL_MODEL set but no 'claude' binary on PATH never attempts a call" {
  local fakepath
  fakepath="$(dirname "$(command -v bash)")"
  run env -i PATH="$fakepath" EIDOLONS_EVAL_MODEL="haiku" bash "$EIDOLONS_ROOT/evals/hooks/keep-system.sh"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "claude" ]]
  [[ "$output" =~ "not found on PATH" ]]
}

@test "hooks: evals/arms/h-win.json is valid JSON conforming to eval-arms shape" {
  run jq -e '(.arms | length) == 2 and (.arms | map(.label) | index("bare-standard")) and (.arms | map(.label) | index("system-light")) and ([.arms[] | select(.control == true)] | length) == 1' "$EIDOLONS_ROOT/evals/arms/h-win.json"
  [ "$status" -eq 0 ]
}

# ─── relative fix-hook absolutization (H-WIN probe regression, 2026-07-03) ──
# The loop invokes the hook from the ephemeral workdir; a repo-relative hook
# path resolved to nothing (exit 127) and the arm silently scored UNRESOLVED.

@test "matrix: repo-relative fix_hook file is absolutized before reaching the loop" {
  cd "$(mktemp -d)"
  mkdir -p hooks
  cat > hooks/rel-hook.sh <<'H'
#!/usr/bin/env bash
exit 1
H
  chmod +x hooks/rel-hook.sh
  cat > arms.json <<'A'
{"arms":[{"label":"rel","fix_hook":"hooks/rel-hook.sh","env":{},"control":true}]}
A
  # --smoke skips hook use entirely; we only assert the parse-time transform,
  # observable via the scorecard's recorded arm.fix_hook (absolute path).
  export EIDOLONS_EVAL_RESULTS_DIR="$PWD/results"
  run bash "$EIDOLONS_ROOT/cli/src/eval_swe.sh" --matrix arms.json --smoke \
    --suite-file "$EIDOLONS_ROOT/evals/swe-suite.yaml" --k 1
  [ "$status" -eq 0 ]
  card="$(ls "$EIDOLONS_EVAL_RESULTS_DIR"/*-rel.scorecard.json 2>/dev/null | head -1)"
  [ -n "$card" ]
  hookpath="$(jq -r '.arm.fix_hook' "$card")"
  [[ "$hookpath" = /* ]]
}
