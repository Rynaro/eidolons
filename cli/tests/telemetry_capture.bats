#!/usr/bin/env bats
#
# cli/tests/telemetry_capture.bats
#
# Phase A+C — fixture-first tripwire (AC-F1-1, RED in Phase A; GREEN in Phase C)
# plus additional AC-F1-3/4/5/6 assertions added in Phase C.
# RISK-D1 from spec.md §4.1 / §11.
#
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

# ─── AC-F1-3 idempotency/dedup ────────────────────────────────────────────
#
# GIVEN a day file already containing rows from a transcript,
# WHEN capture re-runs over the SAME transcript,
# THEN no event_id is duplicated.

@test "telemetry capture: re-run over same transcript produces no duplicate event_ids (AC-F1-3)" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"

  # Run capture twice over the same transcript.
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  # Collect all rows from all day files.
  local all_rows_file
  all_rows_file="$BATS_TEST_TMPDIR/all_rows_dedup.jsonl"
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    cat "$day_file" >> "$all_rows_file" 2>/dev/null || true
  done

  [ -f "$all_rows_file" ] || {
    echo "FAIL: no day files found in store — capture produced no rows" >&2
    return 1
  }

  # Assert zero duplicate event_ids.
  local dup_count
  dup_count="$(jq -s 'group_by(.event_id) | map(select(length > 1)) | length' \
    "$all_rows_file" 2>/dev/null || echo "0")"

  [ "$dup_count" -eq 0 ] || {
    echo "FAIL: found $dup_count duplicate event_id group(s) after two capture runs" >&2
    jq -s 'group_by(.event_id) | map(select(length > 1)) | .[].event_id' \
      "$all_rows_file" >&2 || true
    return 1
  }
}

# ─── AC-F1-3 (regression) incremental growth ──────────────────────────────
#
# GIVEN a day file already containing rows from a session's first N turns,
# WHEN capture re-runs over the SAME session GROWN by 2 new turns,
# THEN the 2 new turns ARE appended (no data loss), no event_id is duplicated,
#      and stderr carries no `unbound variable` abort.
#
# Regression guard for the set -u landmine in _append_row_if_new's skip-on-append
# log line (referenced $EVENT_ID/$DAY_FILE instead of the $_event_id/$_day_file
# locals): under set -u that aborted the skip path on the FIRST duplicate, so a
# grown session silently lost every turn after the first already-seen one. The
# same-transcript dedup test (AC-F1-3) passed vacuously because end-state stayed
# correct; only a growing session exposes the data loss.

@test "telemetry capture: grown session appends new turns without loss or dup (AC-F1-3 regression)" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  # First capture: the committed 3-turn fixture.
  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  local rows_after_first
  rows_after_first="$(jq -s '[.[] | select(.source=="audited")] | length' \
    "$EIDOLONS_HOME"/telemetry/*/*.jsonl 2>/dev/null || echo 0)"
  [ "$rows_after_first" -ge 1 ] || {
    echo "BROKEN TEST: first capture produced no rows" >&2
    return 1
  }

  # Build a GROWN transcript: the same session + 2 new assistant turns.
  local sid grown
  sid="$(jq -r 'select(.type=="assistant") | .sessionId' "$FIXTURE_TRANSCRIPT" | head -1)"
  grown="$BATS_TEST_TMPDIR/grown-transcript.jsonl"
  cat "$FIXTURE_TRANSCRIPT" > "$grown"
  jq -cn --arg sid "$sid" '{type:"assistant",isSidechain:false,sessionId:$sid,gitBranch:"feat/telemetry-mlp",cwd:"/Users/synthetic/projects/eidolons",slug:"-Users-synthetic-projects-eidolons",timestamp:"2026-06-13T10:00:30.000Z",uuid:"u-grow-1",parentUuid:"u-prev",userType:"external",entrypoint:"cli",version:"1.0",requestId:"req-g1",message:{role:"assistant",type:"message",id:"m-g1",model:"claude-opus-4-8",content:[{type:"text",text:"grown turn four"}],usage:{input_tokens:700,output_tokens:150,cache_creation_input_tokens:0,cache_read_input_tokens:0}}}' >> "$grown"
  jq -cn --arg sid "$sid" '{type:"assistant",isSidechain:false,sessionId:$sid,gitBranch:"feat/telemetry-mlp",cwd:"/Users/synthetic/projects/eidolons",slug:"-Users-synthetic-projects-eidolons",timestamp:"2026-06-13T10:00:40.000Z",uuid:"u-grow-2",parentUuid:"u-grow-1",userType:"external",entrypoint:"cli",version:"1.0",requestId:"req-g2",message:{role:"assistant",type:"message",id:"m-g2",model:"claude-opus-4-8",content:[{type:"text",text:"grown turn five"}],usage:{input_tokens:800,output_tokens:160,cache_creation_input_tokens:0,cache_read_input_tokens:1000}}}' >> "$grown"

  # Second capture over the grown transcript; capture stderr to assert no abort.
  local grown_event errfile
  grown_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$grown")"
  errfile="$BATS_TEST_TMPDIR/grow-capture.err"
  printf '%s\n' "$grown_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>"$errfile" || true

  # No set -u abort leaked to stderr.
  ! grep -q "unbound variable" "$errfile" || {
    echo "FAIL: capture emitted an 'unbound variable' abort (set -u landmine):" >&2
    cat "$errfile" >&2
    return 1
  }

  # The 2 new turns were appended: 3 assistant + 1 subagent (toolUseResult) + 2 new = 6 audited rows.
  # (P2.2 extended the fixture with a toolUseResult agent line, adding 1 subagent row.)
  local rows_after_grow
  rows_after_grow="$(jq -s '[.[] | select(.source=="audited")] | length' \
    "$EIDOLONS_HOME"/telemetry/*/*.jsonl 2>/dev/null || echo 0)"
  [ "$rows_after_grow" -eq 6 ] || {
    echo "FAIL: expected 6 audited rows after growth (3 assistant + 1 subagent + 2 new), got $rows_after_grow (data loss in skip-on-append)" >&2
    jq -cs '[.[] | select(.source=="audited")] | map({turn_index, in:.usage.input_tokens})' \
      "$EIDOLONS_HOME"/telemetry/*/*.jsonl >&2 || true
    return 1
  }

  # Still no duplicate event_ids.
  local dup_count
  dup_count="$(jq -s 'group_by(.event_id) | map(select(length > 1)) | length' \
    "$EIDOLONS_HOME"/telemetry/*/*.jsonl 2>/dev/null || echo 0)"
  [ "$dup_count" -eq 0 ] || {
    echo "FAIL: $dup_count duplicate event_id group(s) after growth" >&2
    return 1
  }
}

# ─── AC-F1-4 lean row ─────────────────────────────────────────────────────
#
# GIVEN any captured row,
# THEN its serialized length is <4096 bytes and it contains no raw prompt text.

@test "telemetry capture: every row is <4096 bytes and contains no raw prompt text (AC-F1-4)" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"

  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  local found_rows=0
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      found_rows=$((found_rows + 1))
      # Check length < 4096 bytes.
      local row_len
      row_len="${#row}"
      [ "$row_len" -lt 4096 ] || {
        echo "FAIL: row $found_rows is $row_len bytes (>= 4096)" >&2
        return 1
      }
      # Check no raw prompt/response text (fixture content strings are known).
      # The fixture uses text like "hello please implement" and "hello world turn"
      # — those must NOT appear in the row (structured metadata only).
      case "$row" in
        *"hello please implement"* | *"hello world turn"* | *"now delegate"* | *"looks good, wrap up"*)
          echo "FAIL: row contains raw user/assistant content text" >&2
          echo "Row: $row" >&2
          return 1
          ;;
      esac
    done < "$day_file"
  done

  [ "$found_rows" -ge 1 ] || {
    echo "FAIL: no rows found in store — cannot verify lean-row constraint" >&2
    return 1
  }
}

# ─── AC-F1-5 fail-open ───────────────────────────────────────────────────
#
# GIVEN a Stop event with missing/empty .transcript_path,
# WHEN capture runs,
# THEN it exits 0 with no row written and no error.

@test "telemetry capture: missing transcript_path exits 0 with no row written (AC-F1-5)" {
  # Hook event with no transcript_path.
  local hook_event='{"hook_event_name":"Stop"}'

  local status=0
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: capture exited $status (expected 0 for missing transcript_path)" >&2
    return 1
  }

  # Assert no rows written.
  local row_count=0
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    local n
    n="$(wc -l < "$day_file" 2>/dev/null || echo 0)"
    row_count=$((row_count + n))
  done

  [ "$row_count" -eq 0 ] || {
    echo "FAIL: $row_count row(s) were written despite missing transcript_path" >&2
    return 1
  }
}

@test "telemetry capture: empty transcript_path exits 0 with no row written (AC-F1-5 variant)" {
  local hook_event='{"transcript_path":"","hook_event_name":"Stop"}'

  local status=0
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: capture exited $status for empty transcript_path (expected 0)" >&2
    return 1
  }

  local row_count=0
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    local n
    n="$(wc -l < "$day_file" 2>/dev/null || echo 0)"
    row_count=$((row_count + n))
  done

  [ "$row_count" -eq 0 ] || {
    echo "FAIL: $row_count row(s) written for empty transcript_path" >&2
    return 1
  }
}

@test "telemetry capture: nonexistent transcript_path exits 0 with no row written (AC-F1-5 variant)" {
  local hook_event
  hook_event='{"transcript_path":"/nonexistent/path/no-file.jsonl","hook_event_name":"Stop"}'

  local status=0
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: capture exited $status for nonexistent transcript_path (expected 0)" >&2
    return 1
  }

  local row_count=0
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    local n
    n="$(wc -l < "$day_file" 2>/dev/null || echo 0)"
    row_count=$((row_count + n))
  done

  [ "$row_count" -eq 0 ] || {
    echo "FAIL: $row_count row(s) written for nonexistent transcript_path" >&2
    return 1
  }
}

# ─── AC-F1-6 estimated ladder (non-CC hosts) ─────────────────────────────
#
# GIVEN --hook STOP_codex (no audited adapter),
# WHEN capture runs,
# THEN it exits 0 and NEVER produces a row with source:"audited".

@test "telemetry capture: STOP_codex exits 0 and never produces source:audited rows (AC-F1-6)" {
  # Pipe a hook event that would look like a real transcript path
  # (pointing at the fixture), but using STOP_codex — should never produce audited.
  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"

  local status=0
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_codex --stdin \
    2>/dev/null || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: capture exited $status for STOP_codex (expected 0)" >&2
    return 1
  }

  # Assert no audited rows exist.
  local audited_count=0
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    local n
    n="$(jq -s '[.[] | select(.source=="audited")] | length' "$day_file" 2>/dev/null || echo 0)"
    audited_count=$((audited_count + n))
  done

  [ "$audited_count" -eq 0 ] || {
    echo "FAIL: STOP_codex produced $audited_count audited row(s) — must never tag audited" >&2
    return 1
  }
}

# ─── P2.2 — Subagent capture tripwire (fixture-first, RISK-D1 class) ─────────
#
# GIVEN the committed cc-transcript.jsonl extended with a type:"user" line
# carrying a toolUseResult.agentType field (real shape from CC 2.x),
# WHEN telemetry capture fires,
# THEN a row with is_sidechain:true, attribution.eidolon=="vivi",
#      model=="claude-sonnet-4-6", and the 4-field usage (650000/112075/25000/25000)
#      is written to the store.
#
# This test is written BEFORE the toolUseResult projection exists in telemetry.sh.
# It MUST be RED initially (confirmed before projection shipped).

@test "telemetry capture P2.2: produces is_sidechain:true row for toolUseResult agent dispatch (tripwire)" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"

  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  # Collect all rows from the store.
  local all_rows_file
  all_rows_file="$BATS_TEST_TMPDIR/subagent_rows.jsonl"
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    cat "$day_file" >> "$all_rows_file" 2>/dev/null || true
  done

  [ -f "$all_rows_file" ] || {
    echo "FAIL: no store rows written — subagent projection not yet implemented" >&2
    return 1
  }

  # Assert: at least one row with is_sidechain:true AND eidolon=="vivi".
  local sidechain_vivi
  sidechain_vivi="$(jq -s '
    [.[] | select(.source == "audited" and .attribution.is_sidechain == true and .attribution.eidolon == "vivi")] | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"

  [ "$sidechain_vivi" -ge 1 ] || {
    echo "FAIL: no audited row with is_sidechain:true and eidolon:vivi found — toolUseResult projection missing" >&2
    jq -cs '[.[] | {source,is_sidechain:.attribution.is_sidechain,eidolon:.attribution.eidolon}]' \
      "$all_rows_file" >&2 || true
    return 1
  }
}

@test "telemetry capture P2.2: subagent row carries resolvedModel and all 4 usage fields" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"

  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  local all_rows_file
  all_rows_file="$BATS_TEST_TMPDIR/subagent_model_rows.jsonl"
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    cat "$day_file" >> "$all_rows_file" 2>/dev/null || true
  done

  [ -f "$all_rows_file" ] || {
    echo "FAIL: no store rows written" >&2
    return 1
  }

  # The vivi toolUseResult in fixture: resolvedModel=claude-sonnet-4-6,
  # usage: input=650000, output=112075, cache_creation=25000, cache_read=25000.
  local matching
  matching="$(jq -s '
    [.[] | select(
      .source == "audited" and
      .attribution.is_sidechain == true and
      .attribution.eidolon == "vivi" and
      .model == "claude-sonnet-4-6" and
      .usage.input_tokens == 650000 and
      .usage.output_tokens == 112075 and
      .usage.cache_creation_input_tokens == 25000 and
      .usage.cache_read_input_tokens == 25000
    )] | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"

  [ "$matching" -ge 1 ] || {
    echo "FAIL: no vivi subagent row matched expected model + all 4 usage fields" >&2
    jq -cs '[.[] | select(.attribution.is_sidechain == true) | {source,model,usage,eidolon:.attribution.eidolon}]' \
      "$all_rows_file" >&2 || true
    return 1
  }
}

@test "telemetry capture P2.2: subagent dedup on re-run — agentId is dedup key" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"

  # Run capture twice.
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  # Collect all rows.
  local all_rows_file
  all_rows_file="$BATS_TEST_TMPDIR/dedup_subagent.jsonl"
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    cat "$day_file" >> "$all_rows_file" 2>/dev/null || true
  done

  [ -f "$all_rows_file" ] || {
    echo "FAIL: no rows written" >&2
    return 1
  }

  # Assert zero duplicate event_ids (agentId-based dedup for subagent rows).
  local dup_count
  dup_count="$(jq -s 'group_by(.event_id) | map(select(length > 1)) | length' \
    "$all_rows_file" 2>/dev/null || echo 0)"

  [ "$dup_count" -eq 0 ] || {
    echo "FAIL: $dup_count duplicate event_id group(s) — subagent agentId dedup failed" >&2
    return 1
  }
}

@test "telemetry capture P2.2: main-loop rows unchanged by subagent projection (no-regression)" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"

  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  local all_rows_file
  all_rows_file="$BATS_TEST_TMPDIR/regression_rows.jsonl"
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    cat "$day_file" >> "$all_rows_file" 2>/dev/null || true
  done

  [ -f "$all_rows_file" ] || {
    echo "FAIL: no rows written" >&2
    return 1
  }

  # Original fixture has 3 assistant turns: the main-loop rows must still be there.
  # Turn 1: model=claude-opus-4-8, input=1000, output=200.
  local main_row_1
  main_row_1="$(jq -s '
    [.[] | select(
      .source == "audited" and
      .model == "claude-opus-4-8" and
      .usage.input_tokens == 1000 and
      .usage.output_tokens == 200
    )] | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"

  [ "$main_row_1" -ge 1 ] || {
    echo "FAIL: original main-loop turn-1 row missing (regression in assistant-turn projection)" >&2
    return 1
  }

  # Turn 3: model=claude-sonnet-4-6 (main), input=500, output=100, cache_read=8000.
  local main_row_3
  main_row_3="$(jq -s '
    [.[] | select(
      .source == "audited" and
      .model == "claude-sonnet-4-6" and
      .usage.input_tokens == 500 and
      .usage.output_tokens == 100 and
      .usage.cache_read_input_tokens == 8000 and
      .attribution.is_sidechain == false
    )] | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"

  [ "$main_row_3" -ge 1 ] || {
    echo "FAIL: original main-loop turn-3 row (sonnet, input=500, cache_read=8000) missing" >&2
    jq -cs '[.[] | {source,model,is_sidechain:.attribution.is_sidechain,usage}]' \
      "$all_rows_file" >&2 || true
    return 1
  }
}

# ─── Dual-allowlist: dispatcher + subcommand switch ───────────────────────
#
# Assert that 'eidolons telemetry --help' exits 0 (dispatcher registered)
# and 'eidolons telemetry bogus' exits non-zero (subcommand switch registered).

@test "telemetry: eidolons telemetry --help exits 0 (dispatcher registered)" {
  local status=0
  "$EIDOLONS_BIN" telemetry --help 2>/dev/null || status=$?
  [ "$status" -eq 0 ] || {
    echo "FAIL: 'eidolons telemetry --help' exited $status (expected 0)" >&2
    return 1
  }
}

@test "telemetry: eidolons telemetry bogus exits non-zero (subcommand switch registered)" {
  local status=0
  "$EIDOLONS_BIN" telemetry bogus 2>/dev/null || status=$?
  [ "$status" -ne 0 ] || {
    echo "FAIL: 'eidolons telemetry bogus' exited 0 (expected non-zero)" >&2
    return 1
  }
}
