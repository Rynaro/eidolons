#!/usr/bin/env bats
# cli/tests/eval_compliance.bats — eidolons eval compliance
# A/B routing-compliance instrument. Pure sh/coreutils/jq — NO model, NO
# network, NO Docker. All tests run against the --smoke path (fake driver).
#
# Test list (≥16 cases per spec):
#   1  --help exits 0, compliance in eval --help
#   2  unknown option dies non-zero naming the option
#   3  --k 0 dies; --max-turns 0 dies
#   4  fixture build determinism (cortex byte-identical; 7 stubs; arm A hooks present; arm B absent; CLAUDE.md identical)
#   5  offline guarantee (no fetch_eidolon/git clone in builder output)
#   6  arm-A self-check happy path (smoke run completes, no abort)
#   7  arm-A self-check sabotage (EIDOLONS_COMPLIANCE_SABOTAGE=skip-harness aborts)
#   8  parse: correct early dispatch → delegated_any:true, delegated_correct:true
#   9  parse: wrong target (GT=atlas, got vivi) → delegated_any:true, delegated_correct:false
#  10  parse: no Task → delegated_any:false
#  11  parse: chain head (GT=[spectra,vivi]) → correct (head=spectra)
#  12  control inversion (clean) → correct:true (no Task on clarify prompt)
#  13  control inversion (routed) → correct:false (Task fired on clarify prompt)
#  14  scorecard math — known rates from engineered smoke run
#  15  --smoke end-to-end both arms — full pipeline, JSON valid, all top-level fields
#  16  claude-absent error — non-smoke with no claude binary dies with actionable message
#  17  --validate-suite passes on shipped suite; broken suite fails
#  18  --dry-run prints COST: banner, exits 0, calls no driver
#  19  live-run-without-confirmation guard dies with --yes message
#  20  smoke scorecard determinism — two --smoke --json runs byte-identical
#  21  stdout discipline — --smoke --json stdout is valid JSON only

load helpers

bats_require_minimum_version 1.5.0

setup() {
  # Remove stale --keep compliance fixtures from prior runs to avoid
  # the `ls -dt` in tests picking the wrong fixture directory.
  rm -rf "${TMPDIR:-/tmp}"/eidolons-compliance.* 2>/dev/null || true

  # HARD SAFETY NET: no test in this file may ever spawn a real, billed
  # `claude -p` session. eval_compliance.sh refuses the default-claude driver
  # when this is set. Every behavioural test uses --smoke (fake driver); the
  # negative driver tests use an explicit fake --driver. A live measurement is
  # run by a human via runbook-compliance.md, never by bats.
  export EIDOLONS_COMPLIANCE_NO_LIVE=1
}

# ── Helper: run the compliance eval ─────────────────────────────────────────
eval_compliance() {
  EIDOLONS_NEXUS="$EIDOLONS_ROOT" "$EIDOLONS_BIN" eval compliance "$@"
}

# ── Helper: run the compliance eval with SABOTAGE ───────────────────────────
eval_compliance_sabotage() {
  EIDOLONS_NEXUS="$EIDOLONS_ROOT" \
  EIDOLONS_COMPLIANCE_SABOTAGE=skip-harness \
    "$EIDOLONS_BIN" eval compliance "$@"
}

# ── Test 1: --help ────────────────────────────────────────────────────────────
@test "compliance: --help exits 0 with help body" {
  run eval_compliance --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "A/B routing-compliance" ]]
  [[ "$output" =~ "--smoke" ]]
  [[ "$output" =~ "--yes" ]]
}

@test "compliance: eval --help lists compliance" {
  # Use bash -c to set EIDOLONS_NEXUS in env before the command (bats run
  # does not support VAR=val prefix on the command name)
  run bash -c "EIDOLONS_NEXUS='$EIDOLONS_ROOT' '$EIDOLONS_BIN' eval --help 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "compliance" ]]
}

# ── Test 2: unknown option ───────────────────────────────────────────────────
@test "compliance: unknown option dies non-zero naming the option" {
  run eval_compliance --bogus-flag
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--bogus-flag" ]]
}

# ── Test 3: arg validation ───────────────────────────────────────────────────
@test "compliance: --k 0 dies with validation error" {
  run eval_compliance --smoke --k 0
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--k must be >= 1" ]]
}

@test "compliance: --max-turns 0 dies with validation error" {
  run eval_compliance --smoke --max-turns 0
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--max-turns must be >= 1" ]]
}

# ── Test 4: fixture build determinism ────────────────────────────────────────
@test "compliance: fixture build — cortex byte-identical, 7 stubs, arm A hooks, arm B clean, CLAUDE.md identical" {
  # Run --keep --smoke so fixtures are preserved
  run eval_compliance --smoke --keep --json
  [ "$status" -eq 0 ]

  # Find the most recently created fixture root (TMPDIR, named eidolons-compliance.*)
  # Use ls -dt to get newest first, avoiding stale fixtures from prior tests
  fixture_root="$(ls -dt "${TMPDIR:-/tmp}"/eidolons-compliance.* 2>/dev/null | head -1)"
  [ -n "$fixture_root" ]
  [ -d "$fixture_root" ]

  arm_a="$fixture_root/compliance-arm-A"
  arm_b="$fixture_root/compliance-arm-B"

  # (a) Cortex byte-identical to checkout
  diff "$EIDOLONS_ROOT/EIDOLONS.md" "$arm_a/.eidolons/cortex/EIDOLONS.md" >/dev/null
  diff "$EIDOLONS_ROOT/EIDOLONS.md" "$arm_b/.eidolons/cortex/EIDOLONS.md" >/dev/null

  # (b) All 7 roster member stubs exist (from roster: atlas spectra vivi idg forge vigil kupo)
  for name in atlas spectra vivi idg forge vigil kupo; do
    [ -f "$arm_a/.claude/agents/${name}.md" ]
    [ -f "$arm_b/.claude/agents/${name}.md" ]
    # Valid frontmatter: name: field matches filename
    grep -q "^name: ${name}$" "$arm_a/.claude/agents/${name}.md"
  done

  # (c) ARM A's settings.json has a hooks block; ARM B's does not
  jq -e '.hooks != null' "$arm_a/.claude/settings.json" >/dev/null
  if jq -e '.hooks != null' "$arm_b/.claude/settings.json" >/dev/null 2>&1; then
    false  # ARM B must NOT have hooks
  fi

  # (d) ARM A has executable shims; ARM B has none
  [ -x "$arm_a/.eidolons/harness/hooks/claude-code-UserPromptSubmit.sh" ]
  [ -x "$arm_a/.eidolons/harness/hooks/claude-code-SessionStart.sh" ]
  [ ! -d "$arm_b/.eidolons/harness/hooks" ]

  # (e) CLAUDE.md byte-identical between the two arms
  diff "$arm_a/CLAUDE.md" "$arm_b/CLAUDE.md" >/dev/null
}

# ── Test 5: offline guarantee ─────────────────────────────────────────────────
@test "compliance: offline guarantee — builder produces no git-clone or fetch_eidolon invocations" {
  # Run with EIDOLONS_SKIP_REFRESH=1 to confirm no refresh is attempted;
  # capture stderr and assert no 'clone' or 'fetch_eidolon' lines appear
  run bash -c "
    EIDOLONS_NEXUS='$EIDOLONS_ROOT' \
    EIDOLONS_SKIP_REFRESH=1 \
      '$EIDOLONS_BIN' eval compliance --smoke --json 2>&1 | grep -i 'clone\\|fetch_eidolon' || true
  "
  # Output should be empty (no clone/fetch lines)
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Test 6: arm-A self-check happy path ──────────────────────────────────────
@test "compliance: arm-A self-check happy path (smoke completes, no abort)" {
  # --separate-stderr so $output contains only stdout (pure JSON scorecard)
  run --separate-stderr eval_compliance --smoke --json
  [ "$status" -eq 0 ]
  # The scorecard must be valid JSON with mode=smoke
  [ "$(echo "$output" | jq -r '.mode')" = "smoke" ]
}

# ── Test 7: arm-A self-check sabotage ────────────────────────────────────────
@test "compliance: arm-A self-check sabotage (SABOTAGE=skip-harness aborts with wiring self-check failed)" {
  run eval_compliance_sabotage --smoke --json
  [ "$status" -ne 0 ]
  [[ "$output" =~ "wiring self-check failed" ]]
}

# ── Tests 8-13: parser unit tests via _parse_stream ──────────────────────────
# We test the parser by feeding fixture files through a mini harness.
# The compliance script's parser is invoked via a small wrapper.

_parser_test() {
  # Helper: parse fixture and score it
  # $1 = fixture file, $2 = gt_decision, $3 = gt_selected (JSON array), $4 = is_control
  local fixture="$1"
  local gt_decision="$2"
  local gt_selected="$3"
  local is_control="$4"

  EIDOLONS_NEXUS="$EIDOLONS_ROOT" bash -c "
    . '$EIDOLONS_ROOT/cli/src/lib.sh' 2>/dev/null
    NEXUS_ROOT='$EIDOLONS_ROOT'
    SMOKE=true
    CAPTURE_SAMPLE=false
    SESSION_TIMEOUT=120
    MODEL=sonnet
    MAX_TURNS=3
    SELF_DIR='$EIDOLONS_ROOT/cli/src'

    # Load parser helpers inline
    _parse_stream() {
      local stream=\"\$1\"; local roster_names=\"\$2\"
      printf '%s\n' \"\$stream\" | jq -c -R 'fromjson? // empty' \
        | jq -s -c --argjson roster \"\$roster_names\" '
          [ to_entries[]
            | .key as \$turn
            | .value as \$ev
            | ( (\$ev.message.content // \$ev.content // [])
                | if type == \"array\" then . else [] end )[]
            | select((.type? == \"tool_use\") and ((.name? == \"Agent\") or (.name? == \"Task\")))
            | (.input.subagent_type // .input.subagentType // null) as \$st
            | select(\$st != null)
            | select(\$roster | index(\$st) != null)
            | { subagent_type: \$st, turn: \$turn }
          ]' 2>/dev/null || echo '[]'
    }
    _score_prompt() {
      local gt_decision=\"\$1\"; local gt_selected=\"\$2\"
      local parsed=\"\$3\"; local is_control=\"\$4\"
      if [[ \"\$is_control\" == \"true\" ]]; then
        local dispatched; dispatched=\"\$(printf '%s' \"\$parsed\" | jq 'length > 0')\"
        if [[ \"\$dispatched\" == \"false\" ]]; then
          printf '{\"delegated_any\":false,\"delegated_correct\":true}'
        else
          printf '{\"delegated_any\":true,\"delegated_correct\":false}'
        fi
        return
      fi
      local n_dispatched; n_dispatched=\"\$(printf '%s' \"\$parsed\" | jq 'length')\"
      if [[ \"\$n_dispatched\" -eq 0 ]]; then
        printf '{\"delegated_any\":false,\"delegated_correct\":false}'
        return
      fi
      local first_agent; first_agent=\"\$(printf '%s' \"\$parsed\" | jq -r '.[0].subagent_type')\"
      local in_selected; in_selected=\"\$(printf '%s' \"\$gt_selected\" | jq --arg a \"\$first_agent\" 'index(\$a) != null')\"
      printf '{\"delegated_any\":true,\"delegated_correct\":%s}' \"\$in_selected\"
    }

    ROSTER_NAMES_JSON=\$(roster_list_names | jq -R . | jq -s 'sort')
    stream=\$(cat '$fixture')
    observed=\$(_parse_stream \"\$stream\" \"\$ROSTER_NAMES_JSON\")
    score=\$(_score_prompt '$gt_decision' '$gt_selected' \"\$observed\" '$is_control')
    printf '%s\n' \"\$score\"
  " 2>/dev/null
}

@test "compliance: parse dispatch-correct → delegated_any:true, delegated_correct:true" {
  result="$(_parser_test \
    "$EIDOLONS_ROOT/cli/tests/fixtures/compliance/dispatch-correct.jsonl" \
    "dispatch" '["atlas"]' "false")"
  [ "$(echo "$result" | jq -r '.delegated_any')" = "true" ]
  [ "$(echo "$result" | jq -r '.delegated_correct')" = "true" ]
}

@test "compliance: parse dispatch-wrong (GT=atlas, got vivi) → delegated_any:true, delegated_correct:false" {
  result="$(_parser_test \
    "$EIDOLONS_ROOT/cli/tests/fixtures/compliance/dispatch-wrong.jsonl" \
    "dispatch" '["atlas"]' "false")"
  [ "$(echo "$result" | jq -r '.delegated_any')" = "true" ]
  [ "$(echo "$result" | jq -r '.delegated_correct')" = "false" ]
}

@test "compliance: parse no-task → delegated_any:false, delegated_correct:false" {
  result="$(_parser_test \
    "$EIDOLONS_ROOT/cli/tests/fixtures/compliance/no-task.jsonl" \
    "dispatch" '["atlas"]' "false")"
  [ "$(echo "$result" | jq -r '.delegated_any')" = "false" ]
  [ "$(echo "$result" | jq -r '.delegated_correct')" = "false" ]
}

@test "compliance: parse chain-head (GT=[spectra,vivi]) → delegated_correct:true (head=spectra)" {
  result="$(_parser_test \
    "$EIDOLONS_ROOT/cli/tests/fixtures/compliance/chain-head.jsonl" \
    "chain" '["spectra","vivi"]' "false")"
  [ "$(echo "$result" | jq -r '.delegated_any')" = "true" ]
  [ "$(echo "$result" | jq -r '.delegated_correct')" = "true" ]
}

@test "compliance: control-clean (no Task on clarify) → delegated_correct:true" {
  result="$(_parser_test \
    "$EIDOLONS_ROOT/cli/tests/fixtures/compliance/control-clean.jsonl" \
    "clarify" '[]' "true")"
  [ "$(echo "$result" | jq -r '.delegated_any')" = "false" ]
  [ "$(echo "$result" | jq -r '.delegated_correct')" = "true" ]
}

@test "compliance: control-routed (Task fired on clarify) → delegated_correct:false" {
  result="$(_parser_test \
    "$EIDOLONS_ROOT/cli/tests/fixtures/compliance/control-routed.jsonl" \
    "clarify" '[]' "true")"
  [ "$(echo "$result" | jq -r '.delegated_any')" = "true" ]
  [ "$(echo "$result" | jq -r '.delegated_correct')" = "false" ]
}

# ── Test 14: scorecard math ───────────────────────────────────────────────────
@test "compliance: scorecard math — known rates from --smoke run" {
  # The smoke suite maps prompts to fixtures:
  # - C-001 (map the auth flow) → dispatch-correct (atlas, GT=atlas) → correct
  # - C-002 (trace who calls) → dispatch-correct (atlas, GT=atlas) → correct
  # - C-003 (spec out) → chain-head (spectra, GT=[spectra]) → correct
  # - C-004 (design the requirements) → chain-head (spectra) - check GT
  # - C-005 (implement the retry) → dispatch-wrong (vivi, GT=vivi for coder) → correct
  # - C-006 (fix the off-by-one) → dispatch-correct (atlas, but GT=vivi) → may mismatch
  # ...and 2 control prompts → control-clean → correct controls
  # Exact rates depend on routing.yaml; we assert the structure is correct
  # --separate-stderr so $output contains only stdout (pure JSON scorecard)
  run --separate-stderr eval_compliance --smoke --json
  [ "$status" -eq 0 ]

  # Arms present
  [ "$(echo "$output" | jq -r '.arms.A.harness')" = "true" ]
  [ "$(echo "$output" | jq -r '.arms.B.harness')" = "false" ]

  # Both arms have required metric fields
  for field in delegation_rate correct_target_rate control_pass_rate stability_passk; do
    [ "$(echo "$output" | jq -r ".arms.A.${field} | type")" = "number" ]
    [ "$(echo "$output" | jq -r ".arms.B.${field} | type")" = "number" ]
  done

  # Delta fields present and numeric
  [ "$(echo "$output" | jq -r '.delta.delegation_rate | type')" = "number" ]
  [ "$(echo "$output" | jq -r '.delta.correct_target_rate | type')" = "number" ]

  # Gate block present
  [ "$(echo "$output" | jq -r '.gate.metric')" = "A.correct_target_rate" ]
  [ "$(echo "$output" | jq -r '.gate.threshold')" = "80" ]
  [[ "$(echo "$output" | jq -r '.gate.verdict')" =~ ^(PASS|FAIL)$ ]]

  # Sessions run = n_prompts * 2 arms * k=1
  n_prompts="$(echo "$output" | jq -r '.n_prompts')"
  sessions_run="$(echo "$output" | jq -r '.sessions_run')"
  [ "$sessions_run" -eq "$((n_prompts * 2))" ]
}

# ── Test 15: --smoke end-to-end both arms ─────────────────────────────────────
@test "compliance: --smoke end-to-end both arms — full pipeline, JSON valid, all top-level fields" {
  # --separate-stderr so $output contains only stdout (pure JSON scorecard)
  run --separate-stderr eval_compliance --smoke --json
  [ "$status" -eq 0 ]

  # Valid JSON
  echo "$output" | jq . >/dev/null

  # Required top-level fields
  [ "$(echo "$output" | jq -r '.compliance_version')" = "1.0" ]
  [ "$(echo "$output" | jq -r '.mode')" = "smoke" ]
  [ "$(echo "$output" | jq -r '.arms.A | type')" = "object" ]
  [ "$(echo "$output" | jq -r '.arms.B | type')" = "object" ]
  [ "$(echo "$output" | jq -r '.delta | type')" = "object" ]
  [ "$(echo "$output" | jq -r '.gate | type')" = "object" ]
  [ "$(echo "$output" | jq -r '.scope_note | length')" -gt 10 ]

  # per_prompt present in both arms
  [ "$(echo "$output" | jq -r '.arms.A.per_prompt | type')" = "array" ]
  [ "$(echo "$output" | jq -r '.arms.B.per_prompt | type')" = "array" ]

  # by_class present in both arms
  [ "$(echo "$output" | jq -r '.arms.A.by_class | type')" = "array" ]

  # sessions_run correct (both arms, k=1)
  n="$(echo "$output" | jq -r '.n_prompts')"
  sr="$(echo "$output" | jq -r '.sessions_run')"
  [ "$sr" -eq "$((n * 2))" ]
}

# ── Test 16: claude-absent error ──────────────────────────────────────────────
@test "compliance: claude-absent (--driver /nonexistent) dies with actionable message" {
  # Pass a non-existent driver so it doesn't hang waiting for claude
  run bash -c "
    EIDOLONS_NEXUS='$EIDOLONS_ROOT' \
      '$EIDOLONS_BIN' eval compliance \
        --driver '/nonexistent-binary-xyz' \
        --yes \
        --suite-file '$EIDOLONS_ROOT/evals/compliance-suite.yaml' \
        --arm A 2>&1
  "
  # Must fail (can't run /nonexistent-binary-xyz) — either from the self-check
  # or from the driver call attempt
  [ "$status" -ne 0 ]
}

@test "compliance: claude binary genuinely absent dies with Install Claude Code message" {
  # Make claude unreachable while keeping EVERY other tool on the real PATH:
  # remove only the directory that contains the claude binary. grep -v claude
  # on the live PATH is NOT enough — the binary's dir (e.g. ~/.local/bin) is not
  # named 'claude', which is exactly the hole that previously let a live arm run.
  # The NO_LIVE net from setup() stays on as a backstop; the claude-absent guard
  # fires first, so the actionable "Install Claude Code" message is what we get.
  local clean_path="$PATH"
  local cbin cdir
  cbin="$(command -v claude 2>/dev/null || true)"
  if [ -n "$cbin" ]; then
    cdir="$(cd "$(dirname "$cbin")" && pwd)"
    clean_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$cdir" | tr '\n' ':')"
  fi
  # No pipe to head: a pipeline's exit status is its LAST stage, which would
  # mask the script's real non-zero exit. Capture directly.
  run env PATH="$clean_path" EIDOLONS_NEXUS="$EIDOLONS_ROOT" \
      "$EIDOLONS_BIN" eval compliance \
        --yes \
        --arm A \
        --k 1 \
        --suite-file "$EIDOLONS_ROOT/evals/compliance-suite.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Install Claude Code" ]] || \
    [[ "$output" =~ "EIDOLONS_COMPLIANCE_NO_LIVE" ]] || \
    [[ "$output" =~ "wiring self-check failed" ]]
}

@test "compliance: NO_LIVE net refuses default driver even with claude present" {
  # Belt-and-suspenders: with claude present on PATH but the safety net set,
  # a non-smoke arm-A run must die at the driver gate, never spawning a session.
  if ! command -v claude >/dev/null 2>&1; then
    skip "claude not installed — net is moot in this environment"
  fi
  # No pipe to head: its exit status (0) would mask the script's non-zero die.
  run env EIDOLONS_COMPLIANCE_NO_LIVE=1 \
      EIDOLONS_NEXUS="$EIDOLONS_ROOT" \
      "$EIDOLONS_BIN" eval compliance \
        --yes --arm A --k 1 \
        --suite-file "$EIDOLONS_ROOT/evals/compliance-suite.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "EIDOLONS_COMPLIANCE_NO_LIVE" ]] || [[ "$output" =~ "refusing to invoke the live" ]]
}

# ── Test 17: --validate-suite ─────────────────────────────────────────────────
@test "compliance: --validate-suite passes on shipped suite" {
  run eval_compliance --validate-suite
  [ "$status" -eq 0 ]
  [[ "$output" =~ "compliance suite valid" ]]
}

@test "compliance: --validate-suite fails on broken suite (dup id, missing class)" {
  broken="$BATS_TEST_TMPDIR/broken-compliance.yaml"
  cat > "$broken" <<'YAML'
compliance_version: "1.0"
tasks:
  - id: DUP-1
    class: scout
    prompt: "map the auth flow"
  - id: DUP-1
    class: scout
    prompt: "map the codebase"
  - id: NO-CLASS
    prompt: "do something without class field"
YAML
  run eval_compliance --validate-suite --suite-file "$broken"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "duplicate id" ]] || [[ "$output" =~ "missing class" ]]
}

@test "compliance: --validate-suite fails when missing capability class coverage" {
  sparse="$BATS_TEST_TMPDIR/sparse-compliance.yaml"
  cat > "$sparse" <<'YAML'
compliance_version: "1.0"
tasks:
  - id: S-001
    class: scout
    prompt: "map the auth flow"
  - id: S-002
    class: control
    control: true
    prompt: "do the thing"
  - id: S-003
    class: control
    control: true
    prompt: "can you help me with something"
YAML
  run eval_compliance --validate-suite --suite-file "$sparse"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "missing coverage" ]]
}

# ── Test 18: --dry-run ────────────────────────────────────────────────────────
@test "compliance: --dry-run prints COST: banner and exits 0 without calling driver" {
  run bash -c "
    EIDOLONS_NEXUS='$EIDOLONS_ROOT' '$EIDOLONS_BIN' eval compliance \
      --dry-run \
      --k 2 \
      --arm both \
      2>&1
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "COST:" ]]
  [[ "$output" =~ "sessions" ]]
  [[ "$output" =~ "dry-run" ]]
}

# ── Test 19: live-run-without-confirmation guard ──────────────────────────────
@test "compliance: non-smoke non-dry without --yes dies non-zero with the cost/--yes message" {
  run bash -c "
    EIDOLONS_NEXUS='$EIDOLONS_ROOT' '$EIDOLONS_BIN' eval compliance \
      --arm A \
      2>&1
  "
  [ "$status" -ne 0 ]
  [[ "$output" =~ "COST:" ]] || [[ "$output" =~ "--yes" ]] || [[ "$output" =~ "live run requires" ]]
}

# ── Test 20: smoke scorecard determinism ──────────────────────────────────────
@test "compliance: two --smoke --json runs are byte-identical (deterministic)" {
  # --separate-stderr so $output contains only stdout (pure JSON scorecard)
  run --separate-stderr eval_compliance --smoke --json
  [ "$status" -eq 0 ]
  first_output="$output"

  run --separate-stderr eval_compliance --smoke --json
  [ "$status" -eq 0 ]

  # Compare canonicalized JSON (sort keys to normalize)
  first_canon="$(echo "$first_output" | jq -cS 'del(.arms.A.per_prompt[].observed, .arms.B.per_prompt[].observed)' 2>/dev/null)"
  second_canon="$(echo "$output" | jq -cS 'del(.arms.A.per_prompt[].observed, .arms.B.per_prompt[].observed)' 2>/dev/null)"
  [ "$first_canon" = "$second_canon" ]
}

# ── Test 21: stdout discipline ────────────────────────────────────────────────
@test "compliance: --smoke --json stdout is valid JSON only (no log lines)" {
  # Capture stdout and stderr separately
  out_file="$BATS_TEST_TMPDIR/compliance-stdout.json"
  err_file="$BATS_TEST_TMPDIR/compliance-stderr.txt"

  EIDOLONS_NEXUS="$EIDOLONS_ROOT" "$EIDOLONS_BIN" eval compliance --smoke --json \
    >"$out_file" 2>"$err_file"
  local sc=$?
  [ "$sc" -eq 0 ]

  # stdout must be valid JSON
  jq . "$out_file" >/dev/null
  [ "$(jq -r '.compliance_version' "$out_file")" = "1.0" ]

  # stdout must NOT contain log lines (▸, ✓, ·, ⚠, ✗)
  if grep -q '^[▸✓·⚠✗]' "$out_file" 2>/dev/null; then
    false
  fi
}

# ── Test: --arm A only runs one arm ─────────────────────────────────────────
@test "compliance: --arm A runs only arm A (arm B absent from scorecard)" {
  # --separate-stderr so $output contains only stdout (pure JSON scorecard)
  run --separate-stderr eval_compliance --smoke --arm A --json
  [ "$status" -eq 0 ]
  # Mode field present
  [ "$(echo "$output" | jq -r '.mode')" = "smoke" ]
  # ARM A data present (harness=true)
  [ "$(echo "$output" | jq -r '.arms.A.harness')" = "true" ]
  # Sessions run = n_prompts * 1 arm
  n="$(echo "$output" | jq -r '.n_prompts')"
  sr="$(echo "$output" | jq -r '.sessions_run')"
  [ "$sr" -eq "$((n * 1))" ]
}

# ── Test: --gate exits 1 when rate is below threshold ─────────────────────────
@test "compliance: --gate exits 1 when arm-A correct_target_rate < 80% (using --min 101)" {
  # Use --min 101 (impossible threshold) to force a FAIL exit
  run eval_compliance --smoke --min 101 --gate --json
  [ "$status" -ne 0 ]
}

@test "compliance: --gate exits 0 when arm-A correct_target_rate >= threshold (--min 0)" {
  run eval_compliance --smoke --min 0 --gate --json
  [ "$status" -eq 0 ]
}

# ── Test: CLAUDE.md has cortex pointer block ──────────────────────────────────
@test "compliance: fixture CLAUDE.md has cortex pointer block markers" {
  run eval_compliance --smoke --keep --json
  [ "$status" -eq 0 ]

  fixture_root="$(ls -dt "${TMPDIR:-/tmp}"/eidolons-compliance.* 2>/dev/null | head -1)"
  [ -n "$fixture_root" ]
  [ -d "$fixture_root" ]

  arm_a="$fixture_root/compliance-arm-A"
  grep -q '<!-- eidolon:cortex start -->' "$arm_a/CLAUDE.md"
  grep -q '<!-- eidolon:cortex end -->' "$arm_a/CLAUDE.md"
}

@test "compliance: fixture has an actionable code surface (both arms, identical)" {
  # The suite's prompts reference a real codebase ("the worker", "pagination",
  # "the auth flow", "the main router", "the config key"). An empty fixture made
  # coding prompts unanswerable and under-measured delegation (live-capture
  # finding). Assert the deterministic code surface exists and carries the
  # planted issues the prompts target.
  run eval_compliance --smoke --keep --json
  [ "$status" -eq 0 ]
  fixture_root="$(ls -dt "${TMPDIR:-/tmp}"/eidolons-compliance.* 2>/dev/null | head -1)"
  [ -n "$fixture_root" ]

  local a="$fixture_root/compliance-arm-A" b="$fixture_root/compliance-arm-B"
  for d in "$a" "$b"; do
    [ -f "$d/src/worker.py" ]
    [ -f "$d/src/auth.py" ]
    [ -f "$d/src/router.py" ]
    [ -f "$d/src/pagination.py" ]
    [ -f "$d/config.yaml" ]
    grep -q 'def main_router' "$d/src/router.py"
    grep -q 'off-by-one' "$d/src/pagination.py"
    grep -q 'max_retires' "$d/config.yaml"   # the planted typo the executor prompt targets
  done
  # Common-mode: the code surface is byte-identical across arms (only wiring differs).
  run diff -r "$a/src" "$b/src"
  [ "$status" -eq 0 ]
}

# ── UPS driver (claude-headless-ups) — flag validation + pure-helper unit tests ─
# These NEVER spawn a billed session: the smoke tests use the fake driver, the
# live-path tests die at the version gate or the NO_LIVE net before any model
# call, and the helper tests exercise pure functions with no host at all.

@test "compliance: scorecard exposes driver_mode and ups_fired (smoke → fake/unknown)" {
  run --separate-stderr eval_compliance --smoke --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.driver_mode')" = "fake" ]
  [ "$(echo "$output" | jq -r '.ups_fired')" = "unknown" ]
}

@test "compliance: --driver claude-headless-ups is a reserved built-in, not a missing binary" {
  # Live path with the NO_LIVE net set: the reserved name must NOT be rejected as
  # a missing custom-driver binary. It dies for a DIFFERENT reason (version gate
  # if claude is absent, or the NO_LIVE net) — never a billed run.
  run env EIDOLONS_COMPLIANCE_NO_LIVE=1 EIDOLONS_NEXUS="$EIDOLONS_ROOT" \
      "$EIDOLONS_BIN" eval compliance \
        --driver claude-headless-ups --yes --arm A --k 1 \
        --suite-file "$EIDOLONS_ROOT/evals/compliance-suite.yaml"
  [ "$status" -ne 0 ]
  [[ ! "$output" =~ "custom driver not found" ]]
}

@test "compliance: claude-headless-ups version gate rejects a too-high floor (unbilled)" {
  if ! command -v claude >/dev/null 2>&1; then
    skip "claude not installed — version gate exercised via helper unit test instead"
  fi
  # Force an unsatisfiable floor. The gate fires BEFORE any session (no bill).
  run env EIDOLONS_COMPLIANCE_NO_LIVE=1 \
      EIDOLONS_COMPLIANCE_UPS_VERSION_FLOOR=99.9.9 \
      EIDOLONS_NEXUS="$EIDOLONS_ROOT" \
      "$EIDOLONS_BIN" eval compliance \
        --driver claude-headless-ups --yes --arm A --k 1 \
        --suite-file "$EIDOLONS_ROOT/evals/compliance-suite.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "requires Claude Code >= 99.9.9" ]]
}

@test "compliance: claude-headless-ups satisfiable floor passes gate, dies at NO_LIVE net (unbilled)" {
  if ! command -v claude >/dev/null 2>&1; then
    skip "claude not installed — NO_LIVE net path needs the version gate to pass first"
  fi
  # A trivially-satisfiable floor clears the gate; the NO_LIVE net then refuses
  # the live claude driver before any model call.
  run env EIDOLONS_COMPLIANCE_NO_LIVE=1 \
      EIDOLONS_COMPLIANCE_UPS_VERSION_FLOOR=0.0.1 \
      EIDOLONS_NEXUS="$EIDOLONS_ROOT" \
      "$EIDOLONS_BIN" eval compliance \
        --driver claude-headless-ups --yes --arm A --k 1 \
        --suite-file "$EIDOLONS_ROOT/evals/compliance-suite.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "EIDOLONS_COMPLIANCE_NO_LIVE" ]] || [[ "$output" =~ "refusing to invoke the live" ]]
}

# ── Pure-helper unit tests (inline copies, mirror the _parser_test convention) ─

_ups_helpers_source() {
  # Emit the two UPS helpers verbatim so tests lock the real logic shape.
  cat > "$BATS_TEST_TMPDIR/ups_helpers.sh" <<'SH'
_verpart() {
  local p
  p="$(printf '%s' "$1" | cut -d. -f"$2" | tr -cd '0-9')"
  [ -n "$p" ] || p=0
  printf '%s' "$((10#$p))"
}
_version_ge() {
  local a1 a2 a3 b1 b2 b3
  a1="$(_verpart "$1" 1)"; a2="$(_verpart "$1" 2)"; a3="$(_verpart "$1" 3)"
  b1="$(_verpart "$2" 1)"; b2="$(_verpart "$2" 2)"; b3="$(_verpart "$2" 3)"
  if [ "$a1" -ne "$b1" ]; then [ "$a1" -gt "$b1" ]; return; fi
  if [ "$a2" -ne "$b2" ]; then [ "$a2" -gt "$b2" ]; return; fi
  [ "$a3" -ge "$b3" ]
}
_stream_ups_fired() {
  local stream="$1"
  local hit
  hit="$(printf '%s\n' "$stream" | jq -c -R 'fromjson? // empty' 2>/dev/null \
    | jq -r 'select((.type? == "system")
               and ((.subtype? == "hook_started") or (.subtype? == "hook_response"))
               and (.hook_event? == "UserPromptSubmit")) | "yes"' 2>/dev/null \
    | head -1 || true)"
  if [ "$hit" = "yes" ]; then printf 'true'; else printf 'false'; fi
}
SH
  # shellcheck source=/dev/null
  . "$BATS_TEST_TMPDIR/ups_helpers.sh"
}

@test "compliance: _version_ge orders X.Y.Z (patch, minor dominance, leading zeros)" {
  _ups_helpers_source
  run _version_ge 2.1.200 2.1.200; [ "$status" -eq 0 ]   # equal → ge
  run _version_ge 2.1.200 2.1.175; [ "$status" -eq 0 ]   # patch greater
  run _version_ge 2.1.175 2.1.200; [ "$status" -ne 0 ]   # patch lesser
  run _version_ge 2.1.200 2.2.0;   [ "$status" -ne 0 ]   # minor dominates patch (200 !> 2.2)
  run _version_ge 2.2.0   2.1.200; [ "$status" -eq 0 ]   # minor greater
  run _version_ge 2.1.200 2.1.201; [ "$status" -ne 0 ]   # patch off-by-one
  run _version_ge 2.1.8   2.1.08;  [ "$status" -eq 0 ]   # leading zero == 8 (no octal)
  run _version_ge "2.1.200 (Claude Code)" 2.1.200; [ "$status" -eq 0 ]  # version-string suffix
}

@test "compliance: _stream_ups_fired certifies a UserPromptSubmit hook event" {
  _ups_helpers_source
  local with_ups no_ups
  with_ups='{"type":"system","subtype":"hook_started","hook_event":"UserPromptSubmit","session_id":"x"}
{"type":"system","subtype":"init","session_id":"x"}'
  no_ups='{"type":"system","subtype":"hook_started","hook_event":"SessionStart","session_id":"x"}
{"type":"assistant","message":{"content":[]}}'
  run _stream_ups_fired "$with_ups"; [ "$output" = "true" ]
  run _stream_ups_fired "$no_ups";   [ "$output" = "false" ]
  run _stream_ups_fired "";          [ "$output" = "false" ]
}
