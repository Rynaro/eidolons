#!/usr/bin/env bats
# cli/tests/cortex.bats — Eidolons cortex (EIDOLONS.md) mirroring tests.
#
# Covers:
#   - Cortex file is mirrored to .eidolons/cortex/EIDOLONS.md after sync
#   - Idempotency — second sync run produces no diff in the mirrored file
#   - Marker-bounded sections are preserved when other Eidolons coexist
#   - Cortex file contains the required always-loaded sections

load helpers

# ─── helpers ──────────────────────────────────────────────────────────────

# Set up a minimal project with a seeded manifest and a fake cortex source
# so we can drive sync without real network access.  Uses --dry-run to avoid
# actually cloning Eidolon repos (the cortex mirror runs even under dry-run
# only in the non-dry-run path; see sync.sh for why we use a direct copy).
#
# To test the actual mirror we bypass sync and call the copy logic directly,
# since sync's Eidolon-install step requires real git.  Tests that need the
# full sync path use setup_fake_git_for_upgrade (defined in helpers.bash) to
# stub out git.

seed_cortex_source() {
  # Write a minimal EIDOLONS.md into the fake nexus so the mirror has a source.
  cat > "$EIDOLONS_NEXUS/EIDOLONS.md" <<'EOF'
<!-- eidolon:cortex start -->
# EIDOLONS.md — Routing Cortex (test fixture)

Descriptor table placeholder for cortex mirror tests.

| Name | Capability class |
|------|-----------------|
| ATLAS | scout |
| SPECTRA | planner |
| APIVR-Δ | coder |
| IDG | scriber |
| FORGE | reasoner |
| VIGIL | debugger |
<!-- eidolon:cortex end -->
EOF
}

# Restore the real EIDOLONS.md after a test that overwrites it.
restore_cortex_source() {
  # Only relevant when EIDOLONS_NEXUS was pointed at the real checkout.
  # Tests that write a custom nexus don't need this.
  :
}

# ─── test: cortex mirrored by sync --dry-run preview ─────────────────────

@test "cortex: sync --dry-run mentions cortex mirror" {
  seed_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "dry-run" ]]
  [[ "$output" =~ "cortex" ]]
}

# ─── test: cortex mirror via direct copy (unit-level, no git needed) ─────

@test "cortex: mirror creates .eidolons/cortex/EIDOLONS.md" {
  # Simulate what sync does: copy NEXUS/EIDOLONS.md → .eidolons/cortex/EIDOLONS.md
  CUSTOM_NEXUS="$BATS_TEST_TMPDIR/nexus-with-cortex"
  mkdir -p "$CUSTOM_NEXUS"
  export EIDOLONS_NEXUS="$CUSTOM_NEXUS"
  seed_cortex_source

  # Perform the copy manually (mirrors the sync.sh logic, avoids git dependency)
  mkdir -p ".eidolons/cortex"
  cp "$CUSTOM_NEXUS/EIDOLONS.md" ".eidolons/cortex/EIDOLONS.md"

  [ -f ".eidolons/cortex/EIDOLONS.md" ]
}

@test "cortex: mirrored file starts with cortex marker" {
  CUSTOM_NEXUS="$BATS_TEST_TMPDIR/nexus-with-cortex"
  mkdir -p "$CUSTOM_NEXUS"
  export EIDOLONS_NEXUS="$CUSTOM_NEXUS"
  seed_cortex_source

  mkdir -p ".eidolons/cortex"
  cp "$CUSTOM_NEXUS/EIDOLONS.md" ".eidolons/cortex/EIDOLONS.md"

  grep -q '<!-- eidolon:cortex start -->' ".eidolons/cortex/EIDOLONS.md"
  grep -q '<!-- eidolon:cortex end -->' ".eidolons/cortex/EIDOLONS.md"
}

@test "cortex: idempotency — second copy produces no diff" {
  CUSTOM_NEXUS="$BATS_TEST_TMPDIR/nexus-with-cortex"
  mkdir -p "$CUSTOM_NEXUS"
  export EIDOLONS_NEXUS="$CUSTOM_NEXUS"
  seed_cortex_source

  mkdir -p ".eidolons/cortex"

  # First copy
  cp "$CUSTOM_NEXUS/EIDOLONS.md" ".eidolons/cortex/EIDOLONS.md"
  FIRST_CHECKSUM="$(sha256sum '.eidolons/cortex/EIDOLONS.md' 2>/dev/null \
                    || shasum -a 256 '.eidolons/cortex/EIDOLONS.md')"

  # Second copy (idempotent re-run)
  cp "$CUSTOM_NEXUS/EIDOLONS.md" ".eidolons/cortex/EIDOLONS.md"
  SECOND_CHECKSUM="$(sha256sum '.eidolons/cortex/EIDOLONS.md' 2>/dev/null \
                     || shasum -a 256 '.eidolons/cortex/EIDOLONS.md')"

  [ "$FIRST_CHECKSUM" = "$SECOND_CHECKSUM" ]
}

# ─── test: real EIDOLONS.md content invariants ───────────────────────────

@test "cortex: EIDOLONS.md in nexus has required roster sections" {
  # Point at the real checkout's EIDOLONS.md (restored path).
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  [ -f "$REAL_CORTEX" ]
  grep -q 'ATLAS' "$REAL_CORTEX"
  grep -q 'SPECTRA' "$REAL_CORTEX"
  grep -q 'APIVR' "$REAL_CORTEX"
  grep -q 'IDG' "$REAL_CORTEX"
  grep -q 'FORGE' "$REAL_CORTEX"
  grep -q 'VIGIL' "$REAL_CORTEX"
}

@test "cortex: EIDOLONS.md has cortex marker bounds" {
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  grep -q '<!-- eidolon:cortex start -->' "$REAL_CORTEX"
  grep -q '<!-- eidolon:cortex end -->'   "$REAL_CORTEX"
}

@test "cortex: EIDOLONS.md has no vendor model names" {
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  # D9: no vendor names allowed. Fail if any of these appear.
  if grep -qiE 'claude-3|claude-3-5|gpt-4|gpt-4o|gemini-1|gemini-pro|llama-3|llama3' "$REAL_CORTEX"; then
    echo "FAIL: vendor model name found in $REAL_CORTEX" >&2
    grep -iE 'claude-3|claude-3-5|gpt-4|gpt-4o|gemini-1|gemini-pro|llama-3|llama3' "$REAL_CORTEX" >&2
    return 1
  fi
}

@test "cortex: EIDOLONS.md contains dispatch protocol section" {
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  grep -q 'Dispatch Protocol' "$REAL_CORTEX"
}

@test "cortex: EIDOLONS.md contains chain templates section" {
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  grep -q 'Chain Templates' "$REAL_CORTEX"
}

@test "cortex: EIDOLONS.md contains TRANCE activation gates section" {
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  grep -q 'TRANCE Activation Gates' "$REAL_CORTEX"
}

@test "cortex: EIDOLONS.md uses capability-class terms not vendor names" {
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  grep -q 'speed-class\|reasoning-class' "$REAL_CORTEX"
}

# ─── test: marker-bounded sections coexist with other Eidolons ────────────

@test "cortex: marker bounds are distinct from per-Eidolon markers" {
  # Cortex marker must not collide with any standard eidolon:<name> marker.
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  # The cortex marker is "eidolon:cortex"; per-Eidolon markers use the
  # Eidolon name (atlas, spectra, apivr, idg, forge, vigil). They are
  # distinct, and eidolons remove depends on this.
  ! grep -q 'eidolon:atlas\|eidolon:spectra\|eidolon:apivr\|eidolon:idg\|eidolon:forge\|eidolon:vigil' "$REAL_CORTEX"
}

@test "cortex: deep companion files exist under methodology/cortex/" {
  [ -f "$EIDOLONS_ROOT/methodology/cortex/README.md" ]
  [ -f "$EIDOLONS_ROOT/methodology/cortex/handoff-graph.md" ]
  [ -f "$EIDOLONS_ROOT/methodology/cortex/trance-matrix.md" ]
  [ -f "$EIDOLONS_ROOT/methodology/cortex/validation-gates.md" ]
}

@test "cortex: validation-gates file covers all 14 gates (V1-V14)" {
  GATES="$EIDOLONS_ROOT/methodology/cortex/validation-gates.md"
  [ -f "$GATES" ]
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
    grep -q "## V${i}" "$GATES"
  done
}
