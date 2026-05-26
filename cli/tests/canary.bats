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
  # Summary line
  [[ "$output" =~ "with missions" ]]
  [[ "$output" =~ "without" ]]
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
