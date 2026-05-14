#!/usr/bin/env bats
#
# cli/tests/ecl_io_shim.bats — bats coverage for bin/ecl-io-shim (F10-S2)
#
# Spec: .spectra/plans/2026-05-13-ecl-harness.md §5.11, §5.12, STORY F10-S2
#
# These tests exercise both phases of the shim with fixture data.
# No network calls; jq + sha256sum only.
# The parent (CI / eidolons nexus) runs: bats cli/tests/ecl_io_shim.bats
#
# Design:
#   - Each test creates a fresh BATS_TEST_TMPDIR subdir for isolation.
#   - Fixture envelopes are synthesised inline (minimal valid ECL v1.0).
#   - All paths use absolute variables; no relative-path assumptions.

load helpers

# ── Path to the shim under test ───────────────────────────────────────────────
ECL_IO_SHIM="$EIDOLONS_ROOT/bin/ecl-io-shim"

# ── Fixture builders ──────────────────────────────────────────────────────────

# build_fixture_eidolon_dir <dir>
# Creates a minimal /eidolon directory layout for testing.
build_fixture_eidolon_dir() {
  local eidolon_dir="$1"
  mkdir -p "$eidolon_dir/skills/core" "$eidolon_dir/templates" "$eidolon_dir/schemas"
  printf '# atlas\nAtlas methodology agent.\n' > "$eidolon_dir/agent.md"
  printf '1.0\n' > "$eidolon_dir/ECL_VERSION"
  printf '1.1\n' > "$eidolon_dir/EIIS_VERSION"
  # Minimal schema (not used for actual validation in tests)
  printf '{"type":"object"}\n' > "$eidolon_dir/schemas/ecl-envelope.v1.json"
  # One skill file
  printf '# Core Skill\nThis is a core skill.\n' > "$eidolon_dir/skills/core/SKILL.md"
}

# build_fixture_envelope <path> [performative]
# Writes a minimal valid ECL v1.0 envelope JSON to <path>.
build_fixture_envelope() {
  local path="$1"
  local performative="${2:-PROPOSE}"
  local fake_sha
  fake_sha=$(printf 'a%.0s' $(seq 1 64))
  jq -n \
    --arg perf "$performative" \
    --arg sha "$fake_sha" \
    '{
      envelope_version: "1.0",
      message_id: "11111111-1111-4111-8111-111111111111",
      thread_id: "22222222-2222-4222-8222-222222222222",
      parent_id: null,
      from: { eidolon: "spectra", version: "4.3.0" },
      to: { eidolon: "atlas", version: "n/a" },
      performative: $perf,
      objective: "Test objective for ecl-io-shim fixture.",
      artifact: {
        kind: "spec",
        schema_version: "1.0",
        path: "fixture-spec.md",
        sha256: $sha,
        size_bytes: 42
      },
      integrity: {
        method: "sha256",
        value: $sha
      },
      trace: {
        ts: "2026-05-14T00:00:00Z",
        host: "claude-code",
        model: "claude-sonnet-4-6",
        tier: "standard"
      }
    }' > "$path"
}

# build_fixture_reasoning <path> <eidolon_name>
# Writes a minimal valid reasoning.json.
build_fixture_reasoning() {
  local path="$1"
  local eidolon_name="$2"
  jq -n \
    --arg eidolon "$eidolon_name" \
    '{
      schema_version: "1.0",
      eidolon: $eidolon,
      thread_id: "22222222-2222-4222-8222-222222222222",
      parent_id: "11111111-1111-4111-8111-111111111111",
      performative: "INFORM",
      body: "This is the methodology output from the host LLM reasoning step.",
      evidence_anchors: []
    }' > "$path"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

@test "ecl-io-shim: script is executable" {
  [ -x "$ECL_IO_SHIM" ]
}

@test "ecl-io-shim: no JUNCTION_PHASE exits non-zero with clear error" {
  run env -i PATH="$PATH" \
    JUNCTION_INPUT_ENVELOPE="/dev/null" \
    ECL_OUTPUT_DIR="$BATS_TEST_TMPDIR/out" \
    bash "$ECL_IO_SHIM"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "JUNCTION_PHASE" ]]
}

@test "ecl-io-shim: unknown JUNCTION_PHASE exits non-zero" {
  run env -i PATH="$PATH" \
    JUNCTION_PHASE="bogus" \
    JUNCTION_INPUT_ENVELOPE="/dev/null" \
    ECL_OUTPUT_DIR="$BATS_TEST_TMPDIR/out" \
    bash "$ECL_IO_SHIM"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unknown JUNCTION_PHASE" ]]
}

# ── Assemble phase ────────────────────────────────────────────────────────────

@test "assemble: writes prompt-bundle.json to ECL_OUTPUT_DIR; exits 0" {
  local tmpdir="$BATS_TEST_TMPDIR/assemble_basic"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "PROPOSE"

  run env -i PATH="$PATH" \
    JUNCTION_PHASE="assemble" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    bash "$ECL_IO_SHIM"

  [ "$status" -eq 0 ]
  [ -f "$out_dir/prompt-bundle.json" ]
}

@test "assemble: prompt-bundle.json has correct schema_version field" {
  local tmpdir="$BATS_TEST_TMPDIR/assemble_schema"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "REQUEST"

  env -i PATH="$PATH" \
    JUNCTION_PHASE="assemble" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    bash "$ECL_IO_SHIM"

  run jq -r '.schema_version' "$out_dir/prompt-bundle.json"
  [ "$output" = "1.0" ]
}

@test "assemble: prompt-bundle.json has required top-level fields" {
  local tmpdir="$BATS_TEST_TMPDIR/assemble_fields"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "PROPOSE"

  env -i PATH="$PATH" \
    JUNCTION_PHASE="assemble" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    bash "$ECL_IO_SHIM"

  local bundle="$out_dir/prompt-bundle.json"

  run jq -e '.schema_version' "$bundle"
  [ "$status" -eq 0 ]

  run jq -e '.eidolon' "$bundle"
  [ "$status" -eq 0 ]

  run jq -e '.ecl_version' "$bundle"
  [ "$status" -eq 0 ]

  run jq -e '.agent_md' "$bundle"
  [ "$status" -eq 0 ]

  run jq -e '.selected_skills' "$bundle"
  [ "$status" -eq 0 ]

  run jq -e '.input_payload' "$bundle"
  [ "$status" -eq 0 ]

  run jq -e '.response_template' "$bundle"
  [ "$status" -eq 0 ]
}

@test "assemble: prompt-bundle.json selected_skills includes baked skill content" {
  local tmpdir="$BATS_TEST_TMPDIR/assemble_skills"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "PROPOSE"

  env -i PATH="$PATH" \
    JUNCTION_PHASE="assemble" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    bash "$ECL_IO_SHIM"

  run jq -r '.selected_skills | length' "$out_dir/prompt-bundle.json"
  [ "$output" -ge 1 ]
}

@test "assemble: missing input envelope file exits non-zero" {
  local tmpdir="$BATS_TEST_TMPDIR/assemble_missing_envelope"
  local out_dir="$tmpdir/out"
  local eidolon_dir="$tmpdir/eidolon"
  mkdir -p "$out_dir"
  build_fixture_eidolon_dir "$eidolon_dir"

  run env -i PATH="$PATH" \
    JUNCTION_PHASE="assemble" \
    JUNCTION_INPUT_ENVELOPE="$tmpdir/nonexistent.json" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    bash "$ECL_IO_SHIM"
  [ "$status" -ne 0 ]
}

@test "assemble: invalid (non-JSON) envelope exits non-zero" {
  local tmpdir="$BATS_TEST_TMPDIR/assemble_bad_json"
  local out_dir="$tmpdir/out"
  local eidolon_dir="$tmpdir/eidolon"
  mkdir -p "$out_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  printf 'this is not json\n' > "$tmpdir/bad.envelope.json"

  run env -i PATH="$PATH" \
    JUNCTION_PHASE="assemble" \
    JUNCTION_INPUT_ENVELOPE="$tmpdir/bad.envelope.json" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    bash "$ECL_IO_SHIM"
  [ "$status" -ne 0 ]
}

# ── Package phase ─────────────────────────────────────────────────────────────

@test "package: writes *.envelope.json and trace.jsonl to ECL_OUTPUT_DIR; exits 0" {
  local tmpdir="$BATS_TEST_TMPDIR/package_basic"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local in_dir="$tmpdir/in"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir" "$in_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "PROPOSE"
  build_fixture_reasoning "$in_dir/reasoning.json" "atlas"

  run env -i PATH="$PATH" \
    JUNCTION_PHASE="package" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    JUNCTION_IO_IN="$in_dir" \
    bash "$ECL_IO_SHIM"

  [ "$status" -eq 0 ]

  # Exactly one *.envelope.json file must exist
  local count
  count="$(find "$out_dir" -name '*.envelope.json' | wc -l | tr -d ' ')"
  [ "$count" -eq 1 ]

  # trace.jsonl must exist
  [ -f "$out_dir/trace.jsonl" ]
}

@test "package: output envelope has correct required fields" {
  local tmpdir="$BATS_TEST_TMPDIR/package_fields"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local in_dir="$tmpdir/in"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir" "$in_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "PROPOSE"
  build_fixture_reasoning "$in_dir/reasoning.json" "atlas"

  env -i PATH="$PATH" \
    JUNCTION_PHASE="package" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    JUNCTION_IO_IN="$in_dir" \
    bash "$ECL_IO_SHIM"

  local env_file
  env_file="$(find "$out_dir" -name '*.envelope.json' | head -1)"

  # Required top-level fields
  for field in envelope_version message_id thread_id from to performative objective artifact integrity trace; do
    run jq -e --arg f "$field" 'has($f)' "$env_file"
    [ "$status" -eq 0 ]
  done
}

@test "package: output envelope integrity.value matches SHA-256 of payload body" {
  local tmpdir="$BATS_TEST_TMPDIR/package_sha"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local in_dir="$tmpdir/in"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir" "$in_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "PROPOSE"
  build_fixture_reasoning "$in_dir/reasoning.json" "atlas"

  env -i PATH="$PATH" \
    JUNCTION_PHASE="package" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    JUNCTION_IO_IN="$in_dir" \
    bash "$ECL_IO_SHIM"

  local env_file payload_file
  env_file="$(find "$out_dir" -name '*.envelope.json' | head -1)"
  local artifact_path integrity_value computed_sha
  artifact_path="$(jq -r '.artifact.path' "$env_file")"
  integrity_value="$(jq -r '.integrity.value' "$env_file")"
  payload_file="$out_dir/$artifact_path"

  [ -f "$payload_file" ]
  computed_sha="$(sha256sum "$payload_file" | awk '{print $1}')"
  [ "$integrity_value" = "$computed_sha" ]
}

@test "package: output envelope integrity.value matches artifact.sha256" {
  local tmpdir="$BATS_TEST_TMPDIR/package_sha_match"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local in_dir="$tmpdir/in"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir" "$in_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "PROPOSE"
  build_fixture_reasoning "$in_dir/reasoning.json" "atlas"

  env -i PATH="$PATH" \
    JUNCTION_PHASE="package" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    JUNCTION_IO_IN="$in_dir" \
    bash "$ECL_IO_SHIM"

  local env_file
  env_file="$(find "$out_dir" -name '*.envelope.json' | head -1)"
  local artifact_sha integrity_value
  artifact_sha="$(jq -r '.artifact.sha256' "$env_file")"
  integrity_value="$(jq -r '.integrity.value' "$env_file")"
  [ "$artifact_sha" = "$integrity_value" ]
}

@test "package: trace.jsonl contains a valid JSON line with phase=package" {
  local tmpdir="$BATS_TEST_TMPDIR/package_trace"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local in_dir="$tmpdir/in"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir" "$in_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "PROPOSE"
  build_fixture_reasoning "$in_dir/reasoning.json" "atlas"

  env -i PATH="$PATH" \
    JUNCTION_PHASE="package" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    JUNCTION_IO_IN="$in_dir" \
    bash "$ECL_IO_SHIM"

  local trace_file="$out_dir/trace.jsonl"
  [ -f "$trace_file" ]

  # Each line must parse as JSON
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s' "$line" | jq empty
  done < "$trace_file"

  # At least one line must have phase=package
  run grep -c '"phase":"package"' "$trace_file"
  [ "$output" -ge 1 ]
}

@test "package: missing reasoning.json exits non-zero" {
  local tmpdir="$BATS_TEST_TMPDIR/package_missing_reasoning"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local in_dir="$tmpdir/in"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir" "$in_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "PROPOSE"
  # No reasoning.json

  run env -i PATH="$PATH" \
    JUNCTION_PHASE="package" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    JUNCTION_IO_IN="$in_dir" \
    bash "$ECL_IO_SHIM"
  [ "$status" -ne 0 ]
}

@test "package: output envelope performative matches reasoning.json performative" {
  local tmpdir="$BATS_TEST_TMPDIR/package_performative"
  local eidolon_dir="$tmpdir/eidolon"
  local out_dir="$tmpdir/out"
  local in_dir="$tmpdir/in"
  local envelope_file="$tmpdir/input.envelope.json"
  mkdir -p "$out_dir" "$in_dir"
  build_fixture_eidolon_dir "$eidolon_dir"
  build_fixture_envelope "$envelope_file" "REQUEST"

  # reasoning.json with INFORM performative
  jq -n '{
    schema_version: "1.0",
    eidolon: "atlas",
    thread_id: "22222222-2222-4222-8222-222222222222",
    parent_id: "11111111-1111-4111-8111-111111111111",
    performative: "INFORM",
    body: "Fixture methodology output.",
    evidence_anchors: []
  }' > "$in_dir/reasoning.json"

  env -i PATH="$PATH" \
    JUNCTION_PHASE="package" \
    JUNCTION_INPUT_ENVELOPE="$envelope_file" \
    ECL_OUTPUT_DIR="$out_dir" \
    EIDOLON_DIR="$eidolon_dir" \
    JUNCTION_IO_IN="$in_dir" \
    bash "$ECL_IO_SHIM"

  local env_file
  env_file="$(find "$out_dir" -name '*.envelope.json' | head -1)"
  run jq -r '.performative' "$env_file"
  [ "$output" = "INFORM" ]
}
