#!/usr/bin/env bats
#
# cli/tests/telemetry_capture.bats
#
# Phase A — fixture-first RED tripwire for 'eidolons telemetry capture'.
# RISK-D1 from spec.md §4.1 / §11: the fixture + this test MUST be committed
# and RED-verified BEFORE the parser is written (Phase C).
#
# Only AC-F1-1 is asserted here — later ACs arrive in Phase C.
# No live model invocation anywhere (billing-safety: on-disk fixture only).

load helpers

# ─── F1 setup ─────────────────────────────────────────────────────────────────

# Resolve the fixture once; exported so jq expansions inside @test body work.
FIXTURE_TRANSCRIPT=""

setup() {
  # Inherit helpers.bash base setup (EIDOLONS_NEXUS + tmp project dir).
  # helpers.bash setup() already sets EIDOLONS_HOME to $BATS_TEST_TMPDIR/eidolons-home
  # — we shadow that here with a tighter sandbox name to make intent explicit.
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$EIDOLONS_HOME"

  # Resolve absolute path to the committed CC transcript fixture.
  FIXTURE_TRANSCRIPT="$BATS_TEST_DIRNAME/fixtures/telemetry/cc-transcript.jsonl"
}

# ─── AC-F1-1 tripwire ─────────────────────────────────────────────────────────

# RISK-D1 tripwire (written FIRST — must remain RED until Phase C ships the parser).
# GIVEN the committed cc-transcript.jsonl (real schema, synthetic content),
# WHEN a Stop hook event JSON with .transcript_path pointing at it is piped
#      into `eidolons telemetry capture --hook STOP_claude-code --stdin`,
# THEN >= 1 row with .source == "audited" is written to
#      $EIDOLONS_HOME/telemetry/<slug>/<today>.jsonl,
#      and that row's .usage integers + .model match the fixture.
#
# The assertion targets END STATE (rows on disk), NOT exit code — so this test
# fails cleanly with "no rows written" when the parser is absent, rather than
# on exit code (which would be a vacuous failure for the wrong reason).
@test "telemetry capture: produces >=1 audited row from a real-schema CC transcript (AC-F1-1)" {
  # Verify the fixture file is present and readable — if not, the test is broken,
  # not the implementation (explicit fixture-integrity guard per spec §11).
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  # Build the Stop hook event JSON pointing at our fixture.
  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"

  # Invoke the capture verb; ignore exit code — we assert end-state on disk.
  # (The command will fail with "Unknown command: telemetry" until Phase C.)
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  # ── End-state assertion: at least one audited row written ─────────────────

  # The D2 store layout: $EIDOLONS_HOME/telemetry/<project-slug>/<YYYY-MM-DD>.jsonl
  # Glob all day files in the store (slug unknown at test-write-time; use **).
  local row_count
  row_count=0
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    local n
    n="$(jq -s '[.[] | select(.source=="audited")] | length' "$day_file" 2>/dev/null || echo 0)"
    row_count=$((row_count + n))
  done

  # Assert at least one audited row exists.
  [ "$row_count" -ge 1 ] || {
    echo "FAIL: zero audited rows in $EIDOLONS_HOME/telemetry/ — parser not yet implemented (expected RED in Phase A)" >&2
    return 1
  }

  # ── If rows DO exist (Phase C+), also verify usage + model integrity ───────

  # Collect all audited rows across day files into a single jq input stream.
  local all_rows_file
  all_rows_file="$BATS_TEST_TMPDIR/audited_rows.jsonl"
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    jq -c 'select(.source=="audited")' "$day_file" >> "$all_rows_file" 2>/dev/null || true
  done

  # The fixture's first assistant turn: input=1000, output=200, cache_creation=0, cache_read=0,
  # model=claude-opus-4-8. Assert that at least one audited row carries those exact values.
  local matching
  matching="$(jq -s '
    [.[] | select(
      .source == "audited" and
      .model == "claude-opus-4-8" and
      .usage.input_tokens == 1000 and
      .usage.output_tokens == 200 and
      .usage.cache_creation_input_tokens == 0 and
      .usage.cache_read_input_tokens == 0
    )] | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"

  [ "$matching" -ge 1 ] || {
    echo "FAIL: no audited row matched fixture turn-1 token values (input=1000 output=200 model=claude-opus-4-8)" >&2
    echo "Rows found in store:" >&2
    jq -c '{source,model,usage}' "$all_rows_file" >&2 || true
    return 1
  }
}
