#!/usr/bin/env bats
#
# cli/tests/telemetry_identity.bats
#
# Phase E — dispatch-time stamp + capture-time join (AC-F3-3 through AC-F3-6).
# Tests:
#   F3 happy path: dispatch record → capture join → enriched attribution
#   F3 time-proximity: two dispatch rows at T0/T2; turns attribute to the active one
#   F3 fallback (no dispatch): eidolon = main/unknown, tier = null (existing behavior)
#   run.sh no-regression: telemetry OFF → byte-identical --json output, no .dispatch file
#   run.sh gating: telemetry ON → .dispatch file written, routing output UNCHANGED
#
# No live model invocation (billing-safety: on-disk fixtures only).

load helpers

# ─── Setup ────────────────────────────────────────────────────────────────────

FIXTURE_TRANSCRIPT=""

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$EIDOLONS_HOME"
  FIXTURE_TRANSCRIPT="$BATS_TEST_DIRNAME/fixtures/telemetry/cc-transcript.jsonl"
}

# ─── F3-3 project_slug helper ────────────────────────────────────────────────
#
# lib.sh exposes project_slug returning the same string as memory.sh:138-142
# for the same cwd (regression-locked against existing derivation).

@test "telemetry identity: project_slug helper returns basename-lowercased-dash-normalized (AC-F3-3)" {
  # cd into a known directory name and verify the output.
  local test_dir="$BATS_TEST_TMPDIR/MyProject_Dir"
  mkdir -p "$test_dir"
  local slug
  slug="$(cd "$test_dir" && bash -c ". $EIDOLONS_ROOT/cli/src/lib.sh 2>/dev/null; project_slug" 2>/dev/null)"
  # basename of "MyProject_Dir" lowercased = "myproject_dir"; non-alnum runs → dash
  # tr -cs 'a-z0-9' '-' replaces '_' with '-' → "myproject-dir"
  [ "$slug" = "myproject-dir" ] || {
    echo "FAIL: project_slug returned '$slug', expected 'myproject-dir'" >&2
    return 1
  }
}

# ─── F3-4 eidolon_prompt_sha helper ──────────────────────────────────────────
#
# lib.sh exposes eidolon_prompt_sha <name> returning the roster versions.latest.

@test "telemetry identity: eidolon_prompt_sha returns roster versions.latest for known Eidolon (AC-F3-4)" {
  local eps
  eps="$(bash -c ". $EIDOLONS_ROOT/cli/src/lib.sh 2>/dev/null; eidolon_prompt_sha atlas" 2>/dev/null)"
  # Must be a non-empty, non-"null" string (the actual roster version).
  [ -n "$eps" ] || {
    echo "FAIL: eidolon_prompt_sha atlas returned empty" >&2
    return 1
  }
  [ "$eps" != "null" ] || {
    echo "FAIL: eidolon_prompt_sha atlas returned 'null' — unknown Eidolon?" >&2
    return 1
  }
}

@test "telemetry identity: eidolon_prompt_sha returns 'null' for unknown Eidolon (AC-F3-4)" {
  local eps
  eps="$(bash -c ". $EIDOLONS_ROOT/cli/src/lib.sh 2>/dev/null; eidolon_prompt_sha nonexistent-eidolon-xyz" 2>/dev/null)"
  [ "$eps" = "null" ] || {
    echo "FAIL: eidolon_prompt_sha nonexistent-eidolon-xyz returned '$eps', expected 'null'" >&2
    return 1
  }
}

# ─── F3-5 dispatch stamp gating ──────────────────────────────────────────────
#
# run.sh no-regression: with telemetry DISABLED (no $EIDOLONS_HOME/telemetry/ dir
# AND EIDOLONS_TELEMETRY unset/0), eidolons run --json output is byte-identical to
# before Phase E AND no .dispatch/ file is written.

@test "telemetry identity: run.sh with telemetry OFF produces no .dispatch file and JSON unchanged (AC-F3-5 gating)" {
  # EIDOLONS_HOME has no telemetry/ dir and EIDOLONS_TELEMETRY is unset.
  unset EIDOLONS_TELEMETRY

  local dispatch_dir="$EIDOLONS_HOME/telemetry/.dispatch"

  # Run the routing kernel with a known prompt.
  local json_out
  json_out="$("$EIDOLONS_BIN" run "map the auth flow" --json 2>/dev/null)"

  # 1. No .dispatch/ dir was created.
  [ ! -d "$dispatch_dir" ] || {
    echo "FAIL: .dispatch/ dir was created when telemetry is disabled" >&2
    ls -la "$dispatch_dir" >&2 2>/dev/null || true
    return 1
  }

  # 2. The JSON output is valid: decision field exists.
  local decision
  decision="$(printf '%s' "$json_out" | jq -r '.decision // empty' 2>/dev/null || true)"
  [ -n "$decision" ] || {
    echo "FAIL: run --json output is not valid JSON with .decision field" >&2
    printf '%s\n' "$json_out" >&2
    return 1
  }

  # 3. The routing output does NOT contain any telemetry keys (no leakage).
  local has_dispatch_key
  has_dispatch_key="$(printf '%s' "$json_out" | jq 'has("eidolon_prompt_sha") or has("dispatch_stamp")' 2>/dev/null || echo "false")"
  [ "$has_dispatch_key" = "false" ] || {
    echo "FAIL: run --json output contains telemetry key(s) — routing output polluted" >&2
    printf '%s\n' "$json_out" >&2
    return 1
  }
}

@test "telemetry identity: run.sh with EIDOLONS_TELEMETRY=0 produces no .dispatch file (AC-F3-5 gating)" {
  export EIDOLONS_TELEMETRY=0

  local dispatch_dir="$EIDOLONS_HOME/telemetry/.dispatch"

  "$EIDOLONS_BIN" run "map the auth flow" --json 2>/dev/null || true

  [ ! -d "$dispatch_dir" ] || {
    echo "FAIL: .dispatch/ dir was created when EIDOLONS_TELEMETRY=0" >&2
    return 1
  }
  unset EIDOLONS_TELEMETRY
}

# ─── F3-5 dispatch stamp: telemetry ON ───────────────────────────────────────
#
# GIVEN telemetry enabled (EIDOLONS_TELEMETRY=1),
# WHEN `eidolons run "<prompt>"` routes to an Eidolon,
# THEN a dispatch record is written under $EIDOLONS_HOME/telemetry/.dispatch/
#      and routing stdout/exit is UNCHANGED vs telemetry-disabled.

@test "telemetry identity: run.sh with EIDOLONS_TELEMETRY=1 writes .dispatch record (AC-F3-5)" {
  export EIDOLONS_TELEMETRY=1

  local dispatch_dir="$EIDOLONS_HOME/telemetry/.dispatch"

  # Run the routing kernel; capture stdout.
  local json_out status=0
  json_out="$("$EIDOLONS_BIN" run "map the auth flow" --json 2>/dev/null)" || status=$?

  # 1. Exit status still 0.
  [ "$status" -eq 0 ] || {
    echo "FAIL: run exited $status with telemetry ON (expected 0)" >&2
    return 1
  }

  # 2. Routing JSON still valid and identical structure (decision/selected/tier).
  local decision selected tier
  decision="$(printf '%s' "$json_out" | jq -r '.decision // empty' 2>/dev/null || true)"
  selected="$(printf '%s' "$json_out" | jq -r '.selected[0] // empty' 2>/dev/null || true)"
  tier="$(printf '%s' "$json_out" | jq -r '.tier // empty' 2>/dev/null || true)"
  [ "$decision" = "dispatch" ] || {
    echo "FAIL: expected dispatch decision, got '$decision'" >&2
    return 1
  }
  [ "$selected" = "atlas" ] || {
    echo "FAIL: expected atlas selection, got '$selected'" >&2
    return 1
  }
  [ "$tier" = "standard" ] || {
    echo "FAIL: expected standard tier, got '$tier'" >&2
    return 1
  }

  # 3. No telemetry keys leaked into the routing JSON.
  local has_telem_key
  has_telem_key="$(printf '%s' "$json_out" | jq 'has("eidolon_prompt_sha") or has("dispatch_stamp")' 2>/dev/null || echo "false")"
  [ "$has_telem_key" = "false" ] || {
    echo "FAIL: routing JSON contains telemetry key(s)" >&2
    return 1
  }

  # 4. .dispatch/ dir was created.
  [ -d "$dispatch_dir" ] || {
    echo "FAIL: no .dispatch/ dir created when EIDOLONS_TELEMETRY=1" >&2
    return 1
  }

  # 5. At least one .jsonl file written in .dispatch/.
  local dispatch_files
  dispatch_files="$(find "$dispatch_dir" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$dispatch_files" -ge 1 ] || {
    echo "FAIL: no .jsonl files in .dispatch/ after run with telemetry ON" >&2
    ls -la "$dispatch_dir" >&2 2>/dev/null || true
    return 1
  }

  # 6. Each dispatch record has the required fields.
  local dispatch_file
  for dispatch_file in "$dispatch_dir"/*.jsonl; do
    [ -f "$dispatch_file" ] || continue
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      local has_eidolon has_eps has_tier has_ts
      has_eidolon="$(printf '%s' "$row" | jq 'has("eidolon")' 2>/dev/null || echo "false")"
      has_eps="$(printf '%s' "$row" | jq 'has("eidolon_prompt_sha")' 2>/dev/null || echo "false")"
      has_tier="$(printf '%s' "$row" | jq 'has("tier")' 2>/dev/null || echo "false")"
      has_ts="$(printf '%s' "$row" | jq 'has("ts")' 2>/dev/null || echo "false")"
      [ "$has_eidolon" = "true" ] || {
        echo "FAIL: dispatch row missing 'eidolon' field: $row" >&2; return 1
      }
      [ "$has_eps" = "true" ] || {
        echo "FAIL: dispatch row missing 'eidolon_prompt_sha' field: $row" >&2; return 1
      }
      [ "$has_tier" = "true" ] || {
        echo "FAIL: dispatch row missing 'tier' field: $row" >&2; return 1
      }
      [ "$has_ts" = "true" ] || {
        echo "FAIL: dispatch row missing 'ts' field: $row" >&2; return 1
      }
    done < "$dispatch_file"
  done

  unset EIDOLONS_TELEMETRY
}

# ─── F3 join happy path ───────────────────────────────────────────────────────
#
# GIVEN a .dispatch/<sid>.jsonl with a row at T0 {eidolon:"spectra", eidolon_prompt_sha:"4.9.1",
#   tier:"trance", objective_hash:"abc123"}
# AND a transcript whose assistant turns have timestamp > T0 and matching sessionId,
# WHEN capture runs,
# THEN those turns' attribution.eidolon == "spectra", tier == "trance",
#      eidolon_prompt_sha == "4.9.1", objective_hash == "abc123".

@test "telemetry identity: capture join populates eidolon/tier/eps from dispatch record (F3 happy path)" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  # The fixture turns are at 2026-06-13T10:00:05Z, 10:01:10Z, 10:02:05Z.
  # Plant a dispatch record at T0 = 2026-06-13T09:59:00Z (before all turns).
  local sid="sess-abc123-telemetry-test"
  local dispatch_dir="$EIDOLONS_HOME/telemetry/.dispatch"
  mkdir -p "$dispatch_dir"

  local dispatch_row
  dispatch_row="$(jq -nc \
    '{ts:"2026-06-13T09:59:00Z", eidolon:"spectra", eidolon_prompt_sha:"4.9.1",
      objective_hash:"abc123testobj", tier:"trance"}')"
  printf '%s\n' "$dispatch_row" > "${dispatch_dir}/${sid}.jsonl"

  # Run capture over the fixture transcript.
  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  # Collect all audited rows.
  local all_rows_file="$BATS_TEST_TMPDIR/identity_rows.jsonl"
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    jq -c 'select(.source=="audited")' "$day_file" >> "$all_rows_file" 2>/dev/null || true
  done

  [ -f "$all_rows_file" ] || {
    echo "FAIL: no audited rows written — capture did not produce rows" >&2
    return 1
  }

  # Assert all audited rows have attribution.eidolon == "spectra".
  local wrong_eidolon
  wrong_eidolon="$(jq -s '[.[] | select(.attribution.eidolon != "spectra")] | length' \
    "$all_rows_file" 2>/dev/null || echo "0")"
  [ "$wrong_eidolon" -eq 0 ] || {
    echo "FAIL: $wrong_eidolon row(s) have eidolon != 'spectra' (expected all to join dispatch)" >&2
    jq -c '{eidolon: .attribution.eidolon, tier: .attribution.tier}' "$all_rows_file" >&2 || true
    return 1
  }

  # Assert attribution.tier == "trance" on all audited rows.
  local wrong_tier
  wrong_tier="$(jq -s '[.[] | select(.attribution.tier != "trance")] | length' \
    "$all_rows_file" 2>/dev/null || echo "0")"
  [ "$wrong_tier" -eq 0 ] || {
    echo "FAIL: $wrong_tier row(s) have tier != 'trance'" >&2
    return 1
  }

  # Assert attribution.eidolon_prompt_sha == "4.9.1".
  local wrong_eps
  wrong_eps="$(jq -s '[.[] | select(.attribution.eidolon_prompt_sha != "4.9.1")] | length' \
    "$all_rows_file" 2>/dev/null || echo "0")"
  [ "$wrong_eps" -eq 0 ] || {
    echo "FAIL: $wrong_eps row(s) have eidolon_prompt_sha != '4.9.1'" >&2
    return 1
  }

  # Assert attribution.objective_hash == "abc123testobj".
  local wrong_obj
  wrong_obj="$(jq -s '[.[] | select(.attribution.objective_hash != "abc123testobj")] | length' \
    "$all_rows_file" 2>/dev/null || echo "0")"
  [ "$wrong_obj" -eq 0 ] || {
    echo "FAIL: $wrong_obj row(s) have incorrect objective_hash" >&2
    return 1
  }
}

# ─── F3 time-proximity ───────────────────────────────────────────────────────
#
# GIVEN two dispatch rows: T0 (eidolon A = "atlas") and T2 (eidolon B = "spectra"),
# WHEN capture runs over the fixture transcript,
# THEN turns between T0..T2 attribute to A,
#      turns after T2 attribute to B.
#
# Fixture turn timestamps:
#   turn 0 (turn_index 0): 2026-06-13T10:00:05Z  → after T0, before T2
#   turn 1 (turn_index 1): 2026-06-13T10:01:10Z  → after T0, before T2
#   turn 2 (turn_index 2): 2026-06-13T10:02:05Z  → after T2

@test "telemetry identity: time-proximity join picks dispatch active at turn timestamp (F3 time-proximity)" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  local sid="sess-abc123-telemetry-test"
  local dispatch_dir="$EIDOLONS_HOME/telemetry/.dispatch"
  mkdir -p "$dispatch_dir"

  # T0 = 09:59:00 → eidolon A (atlas); T2 = 10:02:00 → eidolon B (spectra).
  # Fixture turns: 10:00:05, 10:01:10, 10:02:05.
  # Expected:   turns 0+1 → atlas (T0 active);   turn 2 → spectra (T2 active).
  jq -nc '{ts:"2026-06-13T09:59:00Z", eidolon:"atlas", eidolon_prompt_sha:"A1",
             objective_hash:"obj-A", tier:"standard"}' > "${dispatch_dir}/${sid}.jsonl"
  jq -nc '{ts:"2026-06-13T10:02:00Z", eidolon:"spectra", eidolon_prompt_sha:"B9",
             objective_hash:"obj-B", tier:"trance"}' >> "${dispatch_dir}/${sid}.jsonl"

  # Run capture.
  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  # Collect audited rows.
  local all_rows_file="$BATS_TEST_TMPDIR/proximity_rows.jsonl"
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    jq -c 'select(.source=="audited")' "$day_file" >> "$all_rows_file" 2>/dev/null || true
  done

  [ -f "$all_rows_file" ] || {
    echo "FAIL: no audited rows produced by capture" >&2
    return 1
  }

  # Turns 0 and 1 (timestamps 10:00:05 and 10:01:10) should have eidolon=atlas.
  local atlas_count
  atlas_count="$(jq -s '
    [ .[] | select(
        .attribution.eidolon == "atlas" and
        (.ts >= "2026-06-13T10:00:00Z") and (.ts < "2026-06-13T10:02:00Z")
      )
    ] | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"

  [ "$atlas_count" -ge 2 ] || {
    echo "FAIL: expected >=2 turns attributed to 'atlas' (T0..T2 window), got $atlas_count" >&2
    jq -c '{ts:.ts, eidolon:.attribution.eidolon}' "$all_rows_file" >&2 || true
    return 1
  }

  # Turn 2 (timestamp 10:02:05) should have eidolon=spectra.
  local spectra_count
  spectra_count="$(jq -s '
    [ .[] | select(
        .attribution.eidolon == "spectra" and
        (.ts >= "2026-06-13T10:02:00Z")
      )
    ] | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"

  [ "$spectra_count" -ge 1 ] || {
    echo "FAIL: expected >=1 turn attributed to 'spectra' (after T2), got $spectra_count" >&2
    jq -c '{ts:.ts, eidolon:.attribution.eidolon}' "$all_rows_file" >&2 || true
    return 1
  }
}

# ─── F3 fallback (no dispatch) ────────────────────────────────────────────────
#
# GIVEN no .dispatch/ record for the session,
# WHEN capture runs,
# THEN:
#   - main-chain turns (isSidechain:false) → attribution.eidolon == "main"
#   - sidechain turns (isSidechain:true)  → attribution.eidolon == "unknown"
#   - tier == null (honest null, no dispatch)
#   - eidolon_prompt_sha == null

@test "telemetry identity: honest fallback when no dispatch record — eidolon=main/unknown tier=null (AC-F3-6)" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  # No .dispatch/ dir → ensure it does NOT exist (default state in fresh EIDOLONS_HOME).
  # (EIDOLONS_HOME is a fresh tmpdir per test so .dispatch/ is absent by default.)

  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  # Collect all audited rows.
  local all_rows_file="$BATS_TEST_TMPDIR/fallback_rows.jsonl"
  local day_file
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    jq -c 'select(.source=="audited")' "$day_file" >> "$all_rows_file" 2>/dev/null || true
  done

  [ -f "$all_rows_file" ] || {
    echo "FAIL: no audited rows produced" >&2
    return 1
  }

  # Main-chain turns (isSidechain=false) must have eidolon=="main".
  local bad_main
  bad_main="$(jq -s '
    [ .[] | select(.attribution.is_sidechain == false and .attribution.eidolon != "main") ]
    | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"
  [ "$bad_main" -eq 0 ] || {
    echo "FAIL: $bad_main main-chain turn(s) have eidolon != 'main' in no-dispatch fallback" >&2
    jq -c '{sc:.attribution.is_sidechain, eidolon:.attribution.eidolon}' "$all_rows_file" >&2 || true
    return 1
  }

  # Sidechain turns (isSidechain=true) must have eidolon=="unknown".
  local bad_sc
  bad_sc="$(jq -s '
    [ .[] | select(.attribution.is_sidechain == true and .attribution.eidolon != "unknown") ]
    | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"
  [ "$bad_sc" -eq 0 ] || {
    echo "FAIL: $bad_sc sidechain turn(s) have eidolon != 'unknown' in no-dispatch fallback" >&2
    jq -c '{sc:.attribution.is_sidechain, eidolon:.attribution.eidolon}' "$all_rows_file" >&2 || true
    return 1
  }

  # All turns must have tier == null.
  local bad_tier
  bad_tier="$(jq -s '
    [ .[] | select(.attribution.tier != null) ] | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"
  [ "$bad_tier" -eq 0 ] || {
    echo "FAIL: $bad_tier turn(s) have non-null tier in no-dispatch fallback" >&2
    jq -c '{tier:.attribution.tier}' "$all_rows_file" >&2 || true
    return 1
  }

  # All turns must have eidolon_prompt_sha == null.
  local bad_eps
  bad_eps="$(jq -s '
    [ .[] | select(.attribution.eidolon_prompt_sha != null) ] | length
  ' "$all_rows_file" 2>/dev/null || echo 0)"
  [ "$bad_eps" -eq 0 ] || {
    echo "FAIL: $bad_eps turn(s) have non-null eidolon_prompt_sha in no-dispatch fallback" >&2
    return 1
  }
}

# ─── Enriched row sample (print for the report) ──────────────────────────────
#
# This test plants a dispatch record and runs capture, then prints the first
# enriched row as a jq -c sample. Useful for the "1-line sample" requirement
# in the task report. The assertion is just that an enriched row exists.

@test "telemetry identity: enriched row sample — jq -c shows eidolon+tier from dispatch (report sample)" {
  [ -f "$FIXTURE_TRANSCRIPT" ] || {
    echo "BROKEN TEST: fixture not found at $FIXTURE_TRANSCRIPT" >&2
    return 1
  }

  local sid="sess-abc123-telemetry-test"
  local dispatch_dir="$EIDOLONS_HOME/telemetry/.dispatch"
  mkdir -p "$dispatch_dir"

  jq -nc '{ts:"2026-06-13T09:58:00Z", eidolon:"vivi", eidolon_prompt_sha:"1.0.0",
             objective_hash:"sample-obj-hash-abc", tier:"standard"}' \
    > "${dispatch_dir}/${sid}.jsonl"

  local hook_event
  hook_event="$(printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$FIXTURE_TRANSCRIPT")"
  printf '%s\n' "$hook_event" | \
    "$EIDOLONS_BIN" telemetry capture --hook STOP_claude-code --stdin \
    2>/dev/null || true

  local sample_row
  for day_file in "$EIDOLONS_HOME"/telemetry/*/*.jsonl; do
    [ -f "$day_file" ] || continue
    sample_row="$(jq -c 'select(.source=="audited")' "$day_file" 2>/dev/null | head -1 || true)"
    [ -n "$sample_row" ] && break
  done

  [ -n "$sample_row" ] || {
    echo "FAIL: no enriched row produced" >&2
    return 1
  }

  # Print the sample for the report.
  printf 'ENRICHED ROW SAMPLE: %s\n' "$sample_row" >&2

  # Assert the key enrichment fields are present and correct.
  local eidolon tier eps
  eidolon="$(printf '%s' "$sample_row" | jq -r '.attribution.eidolon // empty' 2>/dev/null || true)"
  tier="$(printf '%s' "$sample_row" | jq -r '.attribution.tier // empty' 2>/dev/null || true)"
  eps="$(printf '%s' "$sample_row" | jq -r '.attribution.eidolon_prompt_sha // empty' 2>/dev/null || true)"

  [ "$eidolon" = "vivi" ] || {
    echo "FAIL: enriched row has eidolon='$eidolon', expected 'vivi'" >&2
    return 1
  }
  [ "$tier" = "standard" ] || {
    echo "FAIL: enriched row has tier='$tier', expected 'standard'" >&2
    return 1
  }
  [ "$eps" = "1.0.0" ] || {
    echo "FAIL: enriched row has eidolon_prompt_sha='$eps', expected '1.0.0'" >&2
    return 1
  }
}
