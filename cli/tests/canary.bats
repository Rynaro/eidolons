#!/usr/bin/env bats
# cli/tests/canary.bats — CAN-1..CAN-12
#
# Tests for `eidolons canary` (Layer 3 methodology integrity: behavioral smoke).
# All tests run offline: canary-missions.md fixtures are seeded directly into
# $EIDOLONS_HOME/cache/<name>@<version>/ without real network calls.

load helpers

# ─── Fixture helpers ──────────────────────────────────────────────────────────

# Seed an eidolons.lock with atlas@1.7.1 and vigil@1.1.0
seed_canary_lock() {
  cat > eidolons.lock <<'EOF'
generated_at: "2026-05-26T00:00:00Z"
eidolons_cli_version: "1.13.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.7.1"
    resolved: "github:Rynaro/ATLAS@abc1234"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
  - name: vigil
    version: "1.1.0"
    resolved: "github:Rynaro/VIGIL@def5678"
    target: "./.eidolons/vigil"
    hosts_wired: ["claude-code"]
EOF
}

# Seed an eidolons.lock with only atlas@1.7.1
seed_canary_lock_atlas_only() {
  cat > eidolons.lock <<'EOF'
generated_at: "2026-05-26T00:00:00Z"
eidolons_cli_version: "1.13.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.7.1"
    resolved: "github:Rynaro/ATLAS@abc1234"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
}

# Seed an eidolons.lock with spectra@4.5.1 (two missions)
seed_canary_lock_spectra() {
  cat > eidolons.lock <<'EOF'
generated_at: "2026-05-26T00:00:00Z"
eidolons_cli_version: "1.13.0"
nexus_commit: "test"
members:
  - name: spectra
    version: "4.5.1"
    resolved: "github:Rynaro/SPECTRA@abc9999"
    target: "./.eidolons/spectra"
    hosts_wired: ["claude-code"]
EOF
}

# Materialise a fake atlas cache with a canary-missions.md (default mission, 3 MUST criteria)
seed_atlas_cache_with_missions() {
  local cache_dir="$EIDOLONS_HOME/cache/atlas@1.7.1"
  mkdir -p "$cache_dir/.git" "$cache_dir/evals"
  cat > "$cache_dir/evals/canary-missions.md" <<'EOF'
## Mission: default

### Prompt
You are ATLAS. Given the codebase context, perform a structural analysis.
Output a mission brief with findings.

### Expected output shape
A structured document with a Mission Brief heading, FINDING references,
and mentions of the core skill paths.

### Validation criteria
- MUST contain heading: ## Mission Brief
- MUST contain phrase: FINDING-
- MUST mention paths: skills/abstract.md, skills/locate.md, skills/synthesize.md
EOF
}

# Materialise a fake spectra cache with TWO missions
seed_spectra_cache_with_two_missions() {
  local cache_dir="$EIDOLONS_HOME/cache/spectra@4.5.1"
  mkdir -p "$cache_dir/.git" "$cache_dir/evals"
  cat > "$cache_dir/evals/canary-missions.md" <<'EOF'
## Mission: default

### Prompt
You are SPECTRA. Plan the rollout.

### Expected output shape
A planning document.

### Validation criteria
- MUST contain heading: ## Plan

## Mission: cross-skill-load

### Prompt
You are SPECTRA performing cross-skill loading.

### Expected output shape
A cross-skill analysis.

### Validation criteria
- MUST contain heading: ## Cross-Skill Analysis
- SHOULD have token count between 100 and 5000
EOF
}

# Materialise a fake vigil cache WITH a .git dir but WITHOUT missions
seed_vigil_cache_no_missions() {
  local cache_dir="$EIDOLONS_HOME/cache/vigil@1.1.0"
  mkdir -p "$cache_dir/.git"
  # No evals/ directory or canary-missions.md
}

# Materialise a fake atlas cache with a mission containing a SHOULD criterion
seed_atlas_cache_with_should_mission() {
  local cache_dir="$EIDOLONS_HOME/cache/atlas@1.7.1"
  mkdir -p "$cache_dir/.git" "$cache_dir/evals"
  cat > "$cache_dir/evals/canary-missions.md" <<'EOF'
## Mission: default

### Prompt
ATLAS analysis prompt.

### Expected output shape
Brief output.

### Validation criteria
- MUST contain phrase: FINDING-
- SHOULD contain phrase: DEFINITELY-NOT-PRESENT-EVER-RANDOM-9928
EOF
}

# Materialise a fake atlas cache with an unrecognized criterion line
seed_atlas_cache_with_unknown_criterion() {
  local cache_dir="$EIDOLONS_HOME/cache/atlas@1.7.1"
  mkdir -p "$cache_dir/.git" "$cache_dir/evals"
  cat > "$cache_dir/evals/canary-missions.md" <<'EOF'
## Mission: default

### Prompt
ATLAS analysis prompt.

### Expected output shape
Brief output.

### Validation criteria
- MUST contain phrase: FINDING-
- MUST do something weird that is not a recognized verb at all
EOF
}

# ─── Tests ────────────────────────────────────────────────────────────────────

# CAN-1: prompt mode prints prompt + criteria for a cached Eidolon with missions
@test "CAN-1: prompt mode prints mission content for Eidolon with cached missions" {
  seed_canary_lock_atlas_only
  seed_atlas_cache_with_missions
  run eidolons canary atlas
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Mission: default" ]]
  [[ "$output" =~ "Prompt" ]]
  [[ "$output" =~ "Validation criteria" ]]
  [[ "$output" =~ "MUST contain" ]]
}

# CAN-2: prompt mode for Eidolon without evals/canary-missions.md warns and exits 0
@test "CAN-2: prompt mode for Eidolon without canary missions warns and exits 0" {
  seed_canary_lock
  seed_vigil_cache_no_missions
  # Also seed atlas cache so lock is valid but only test vigil
  seed_atlas_cache_with_missions
  run eidolons canary vigil
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Canary missions not available" ]]
}

# CAN-3: prompt mode for unknown name (not in roster) exits 2
@test "CAN-3: prompt mode for unknown Eidolon name exits 2" {
  seed_canary_lock_atlas_only
  run eidolons canary totally-unknown-eidolon-xyz
  [ "$status" -eq 2 ]
  [[ "$output" =~ "not a known Eidolon" ]]
}

# CAN-4: validation mode all-PASS criteria → exit 0
@test "CAN-4: validate mode all MUST criteria PASS exits 0" {
  seed_canary_lock_atlas_only
  seed_atlas_cache_with_missions

  # Create a synthetic output that satisfies all 3 criteria
  local good_file="$BATS_TEST_TMPDIR/good-output.md"
  cat > "$good_file" <<'RESPONSE'
## Mission Brief

This is a comprehensive analysis.
FINDING-1: The codebase structure shows clear separation of concerns.
FINDING-2: The skill loading mechanism is robust.

References:
- skills/abstract.md — abstraction layer
- skills/locate.md — location primitives
- skills/synthesize.md — synthesis routines
RESPONSE

  run eidolons canary atlas --validate "$good_file"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "3 pass, 0 fail, 0 inconclusive" ]]
  [[ "$output" =~ "[PASS]" ]]
}

# CAN-5: validation mode one MUST FAIL → exit 1
@test "CAN-5: validate mode one MUST criterion FAIL exits 1" {
  seed_canary_lock_atlas_only
  seed_atlas_cache_with_missions

  # Create a bad output: missing the ## Mission Brief heading and FINDING- phrase
  local bad_file="$BATS_TEST_TMPDIR/bad-output.md"
  cat > "$bad_file" <<'RESPONSE'
no heading here
no finding token either
RESPONSE

  run eidolons canary atlas --validate "$bad_file"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "[FAIL]" ]]
  [[ "$output" =~ "fail" ]]
}

# CAN-6: SHOULD failure downgraded to INCONCLUSIVE → exit 0
@test "CAN-6: validate mode SHOULD failure is INCONCLUSIVE, exits 0" {
  seed_canary_lock_atlas_only
  seed_atlas_cache_with_should_mission

  # Create output that satisfies MUST (FINDING-) but not the SHOULD phrase
  local mixed_file="$BATS_TEST_TMPDIR/mixed-output.md"
  cat > "$mixed_file" <<'RESPONSE'
FINDING-1: some finding here
This output does not contain the special should-phrase.
RESPONSE

  run eidolons canary atlas --validate "$mixed_file"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[INCONCLUSIVE]" ]]
  [[ "$output" =~ "SHOULD criterion failed" ]]
  [[ "$output" =~ "0 fail" ]]
}

# CAN-7: validation file empty → all criteria INCONCLUSIVE, exit 0
@test "CAN-7: validate mode with empty file reports INCONCLUSIVE and exits 0" {
  seed_canary_lock_atlas_only
  seed_atlas_cache_with_missions

  local empty_file="$BATS_TEST_TMPDIR/empty-output.md"
  : > "$empty_file"

  run eidolons canary atlas --validate "$empty_file"
  [ "$status" -eq 0 ]
  # stderr should contain the empty-file warning
  [[ "$output" =~ "empty" ]]
}

# CAN-8: --mission selects non-default mission
@test "CAN-8: --mission selects non-default mission content" {
  seed_canary_lock_spectra
  seed_spectra_cache_with_two_missions

  run eidolons canary spectra --mission cross-skill-load
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Mission: cross-skill-load" ]]
  [[ "$output" =~ "Cross-Skill Analysis" ]]
  # Should NOT show the default mission's criteria
  [[ ! "$output" =~ "## Plan" ]]
}

# CAN-9: --mission unknown ID exits 2
@test "CAN-9: --mission with unknown ID exits 2 with available IDs" {
  seed_canary_lock_atlas_only
  seed_atlas_cache_with_missions

  run eidolons canary atlas --mission nonexistent-mission-id
  [ "$status" -eq 2 ]
  [[ "$output" =~ "not found" ]]
  [[ "$output" =~ "Available:" ]]
}

# CAN-10: --list shows have-vs-missing across cached members
@test "CAN-10: --list shows checkmark for mission-present and dot for missing" {
  seed_canary_lock
  seed_atlas_cache_with_missions
  seed_vigil_cache_no_missions

  run eidolons canary --list
  [ "$status" -eq 0 ]
  # atlas should show as having missions (checkmark = UTF-8 U+2713 = e2 9c 93)
  [[ "$output" =~ "atlas@1.7.1" ]]
  # vigil should show as missing (dot = UTF-8 U+00B7 = c2 b7)
  [[ "$output" =~ "vigil@1.1.0" ]]
  # Summary line — three-state format
  [[ "$output" =~ "with parseable missions" ]]
  [[ "$output" =~ "with no file" ]]
}

# CAN-11: --json validation output is valid parseable JSON
@test "CAN-11: --json validate output is parseable JSON with expected schema" {
  seed_canary_lock_atlas_only
  seed_atlas_cache_with_missions

  local good_file="$BATS_TEST_TMPDIR/good-json-output.md"
  cat > "$good_file" <<'RESPONSE'
## Mission Brief

FINDING-1: analysis complete.

skills/abstract.md, skills/locate.md, skills/synthesize.md referenced above.
RESPONSE

  run eidolons canary atlas --validate "$good_file" --json
  [ "$status" -eq 0 ]
  # Must be valid JSON
  echo "$output" | jq -e '.' >/dev/null
  # Expected schema fields
  echo "$output" | jq -e '.summary.pass' >/dev/null
  echo "$output" | jq -e '.criteria[0].result' >/dev/null
  echo "$output" | jq -e '.schema_version' >/dev/null
  local schema_ver
  schema_ver="$(echo "$output" | jq -r '.schema_version')"
  [ "$schema_ver" = "1.0" ]
}

# CAN-12: unrecognized criterion line reported INCONCLUSIVE, not FAIL
@test "CAN-12: unrecognized criterion verb reported as INCONCLUSIVE, not FAIL" {
  seed_canary_lock_atlas_only
  seed_atlas_cache_with_unknown_criterion

  local output_file="$BATS_TEST_TMPDIR/some-output.md"
  cat > "$output_file" <<'RESPONSE'
FINDING-1: something was found
RESPONSE

  run eidolons canary atlas --validate "$output_file"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[INCONCLUSIVE]" ]]
  [[ "$output" =~ "unrecognized criterion" ]]
  # The MUST contain phrase: FINDING- should still PASS
  [[ "$output" =~ "[PASS]" ]]
}

# ─── Legacy-format fixture ────────────────────────────────────────────────────

# Materialise a fake atlas cache with a canary-missions.md that has NO v1.13.0
# DSL headings (legacy/non-DSL format — file exists but 0 missions parse).
seed_atlas_cache_legacy_format() {
  local cache_dir="$EIDOLONS_HOME/cache/atlas@1.7.1"
  mkdir -p "$cache_dir/.git" "$cache_dir/evals"
  cat > "$cache_dir/evals/canary-missions.md" <<'EOF'
# Canary Missions (legacy)

This file is present but does not use the v1.13.0 DSL format.
There are no "## Mission: <id>" headings here.

Some legacy test descriptions that the old format used.
EOF
}

# CAN-13: list mode shows ⚠ when file exists but 0 DSL missions parse
@test "CAN-13: --list shows warning symbol when file exists but 0 DSL missions parse" {
  seed_canary_lock_atlas_only
  seed_atlas_cache_legacy_format

  run eidolons canary --list
  [ "$status" -eq 0 ]
  # Must contain the atlas entry
  [[ "$output" =~ "atlas@1.7.1" ]]
  # Must show the warning message for legacy format (no ✓, no ·)
  [[ "$output" =~ "file present, 0 missions in v1.13.0 DSL format" ]]
  # Must NOT show the parseable-missions message
  [[ ! "$output" =~ "mission(s):" ]]
}

# CAN-14: list mode summary line reflects three counts (parseable / legacy / missing)
@test "CAN-14: --list summary line reflects three counts" {
  # Lock has atlas@1.7.1 (legacy format) and vigil@1.1.0 (no file)
  seed_canary_lock
  seed_atlas_cache_legacy_format
  seed_vigil_cache_no_missions

  run eidolons canary --list
  [ "$status" -eq 0 ]
  # Summary must show all three state labels
  [[ "$output" =~ "with parseable missions" ]]
  [[ "$output" =~ "with file-only (legacy format)" ]]
  [[ "$output" =~ "with no file" ]]
  # 0 parseable, 1 legacy, 1 missing
  [[ "$output" =~ "0 with parseable missions" ]]
  [[ "$output" =~ "1 with file-only (legacy format)" ]]
  [[ "$output" =~ "1 with no file" ]]
}

# ─── CAN-15..CAN-19: --memory mode (crystalium recall-only liveness probe) ────
#
# Mirrors memory.bats' fake-docker-on-PATH pattern (memory.bats:16-96) and
# doctor_deep.bats' D13 fixtures — --memory reuses the exact same gate +
# docker-args transform (cli/src/lib_memory_probe.sh).

_can_seed_mcp_with_crystalium() {
  cat > .mcp.json <<'JSON'
{
  "mcpServers": {
    "crystalium": {
      "command": "docker",
      "args": [
        "run",
        "--rm",
        "-i",
        "--name",
        "crystalium-can-test",
        "-v",
        "/tmp/crystalium-can-test:/root/.crystalium/can-test",
        "-e",
        "CRYSTALIUM_DATA_DIR=/root/.crystalium/can-test",
        "ghcr.io/rynaro/crystalium@sha256:9f49f98bdb8a6628fec92d554a34680edc32c4034e293512dcc1004486252894",
        "python",
        "-m",
        "crystalium",
        "serve"
      ]
    }
  }
}
JSON
}

_can_seed_mcp_lock_with_crystalium() {
  cat > eidolons.mcp.lock <<'LOCK'
generated_at: "2026-06-11T00:00:00Z"
eidolons_cli_version: "1.36.0"
catalogue_version: "1.2"
mcps:
  - name: crystalium
    kind: oci-image
    version: "1.3.0"
    source:
      image: "ghcr.io/rynaro/crystalium"
    integrity:
      algo: oci-digest
      value: "sha256:9f49f98bdb8a6628fec92d554a34680edc32c4034e293512dcc1004486252894"
    target: ".mcp.json"
    installed_at: "2026-06-11T00:00:00Z"
LOCK
}

# Fake docker that answers a `... crystalium recall ...` invocation only
# (--memory never invokes the `doctor` subcommand — that's D13's job).
# Controlled by FAKE_DOCKER_RECALL_OUTPUT / FAKE_DOCKER_RECALL_EXIT.
_can_setup_fake_docker() {
  local fake_bin="$BATS_TEST_TMPDIR/can-fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'DSHIM'
#!/usr/bin/env bash
ARGV="$*"
case "$ARGV" in
  *" recall "*)
    OUT="$FAKE_DOCKER_RECALL_OUTPUT"
    if [ -z "$OUT" ]; then
      OUT='{"records":[],"slot_breakdown":{},"total_tokens":0,"evicted_count":0}'
    fi
    printf '%s\n' "$OUT"
    exit "${FAKE_DOCKER_RECALL_EXIT:-0}"
    ;;
esac
exit 1
DSHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
}

@test "CAN-15: --memory SKIP — crystalium not gated in (no .mcp.json)" {
  run eidolons canary --memory
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SKIP — crystalium not gated in" ]]
}

@test "CAN-16: --memory SKIP — .mcp.json has crystalium but eidolons.mcp.lock does not" {
  _can_seed_mcp_with_crystalium
  # No eidolons.mcp.lock written at all.
  run eidolons canary --memory
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SKIP — crystalium not gated in" ]]
}

@test "CAN-17: --memory PASS — crystalium gated in, stubbed docker returns records" {
  _can_seed_mcp_with_crystalium
  _can_seed_mcp_lock_with_crystalium
  _can_setup_fake_docker
  export FAKE_DOCKER_RECALL_OUTPUT='{"records":[{"id":"c1","layer":"semantic","trust_tier":"T1","summary":"x","validation_state":"valid","importance":0.5,"last_access":"2026-06-11T00:00:00Z","content_ref":null,"score":0.9}],"slot_breakdown":{"semantic":1},"total_tokens":10,"evicted_count":0}'

  run eidolons canary --memory
  [ "$status" -eq 0 ]
  [[ "$output" =~ "PASS — crystalium reachable; probe recall returned 1 record(s)" ]]
  # Must state what was and wasn't checked (recall-only liveness, not a
  # write->recall round trip).
  [[ "$output" =~ "recall-only liveness probe" ]]
  [[ "$output" =~ "does NOT check" ]]
}

@test "CAN-18: --memory INCONCLUSIVE — crystalium reachable but 0 records returned" {
  _can_seed_mcp_with_crystalium
  _can_seed_mcp_lock_with_crystalium
  _can_setup_fake_docker
  export FAKE_DOCKER_RECALL_OUTPUT='{"records":[],"slot_breakdown":{},"total_tokens":0,"evicted_count":0}'

  run eidolons canary --memory
  [ "$status" -eq 0 ]
  [[ "$output" =~ "INCONCLUSIVE — crystalium reachable; 0 records returned by probe recall" ]]
}

@test "CAN-19: --memory FAIL — docker unreachable exits 1" {
  _can_seed_mcp_with_crystalium
  _can_seed_mcp_lock_with_crystalium
  _can_setup_fake_docker
  export FAKE_DOCKER_RECALL_EXIT=1

  run eidolons canary --memory
  [ "$status" -eq 1 ]
  [[ "$output" =~ "FAIL — crystalium unreachable for probe" ]]
}
