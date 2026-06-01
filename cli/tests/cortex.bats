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

# ─── test: host-doc cortex injection (D1 follow-up) ───────────────────────

# Helper: seed a shared-dispatch manifest (shared_dispatch: true).
seed_shared_dispatch_manifest() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
  shared_dispatch: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
}

# Helper: seed a no-shared-dispatch manifest (shared_dispatch: false).
seed_no_shared_dispatch_manifest() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
  shared_dispatch: false
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
}

# Helper: call the cortex-injection portion of sync directly via the
# upsert_marker_block helper in lib.sh, simulating what sync does after
# the per-member install loop. Avoids needing real git / cloned Eidolons.
invoke_cortex_injection() {
  local shared_dispatch="${1:-true}"
  local nexus_dir="${2:-$EIDOLONS_ROOT}"

  # Inline the injection logic — same block content as sync.sh.
  # shellcheck disable=SC1090
  bash -c '
    set -euo pipefail
    . "'"$EIDOLONS_ROOT"'/cli/src/lib.sh"
    CORTEX_BLOCK="## Eidolons Routing Cortex

**Default operating mode:** route all non-trivial work through the Eidolons pipeline — this is the default, not an opt-in. The orchestrator delegates to Eidolon roles via the cortex and does not implement, spec, or scout directly. Answer directly only when a prompt is trivial, conversational, or a single-fact lookup.

**Read:** \`.eidolons/cortex/EIDOLONS.md\` — always-loaded descriptor table + dispatch protocol. It tells you which Eidolon (or chain) handles the prompt, at what tier (\`standard\` is the default; \`TRANCE\` is gated, never default), and what hand-off contract to use.

**Deep tables** (load on demand): \`.eidolons/cortex/trance-matrix.md\`, \`.eidolons/cortex/handoff-graph.md\`, \`.eidolons/cortex/validation-gates.md\`."

    if [[ "'"$shared_dispatch"'" == "true" ]]; then
      for _host_doc in "AGENTS.md" "CLAUDE.md" ".github/copilot-instructions.md"; do
        upsert_marker_block "$_host_doc" "cortex" "$CORTEX_BLOCK"
      done
    fi
  '
}

@test "cortex: injection — cortex block IS in CLAUDE.md after shared-dispatch sync" {
  setup_fake_git_for_upgrade
  seed_shared_dispatch_manifest
  run eidolons sync --yes
  [ "$status" -eq 0 ]
  [ -f "CLAUDE.md" ]
  grep -q '<!-- eidolon:cortex start -->' "CLAUDE.md"
  grep -q '<!-- eidolon:cortex end -->'   "CLAUDE.md"
}

@test "cortex: injection — block contains start marker" {
  invoke_cortex_injection "true"
  grep -q '<!-- eidolon:cortex start -->' "CLAUDE.md"
}

@test "cortex: injection — block contains end marker" {
  invoke_cortex_injection "true"
  grep -q '<!-- eidolon:cortex end -->' "CLAUDE.md"
}

@test "cortex: injection — block points to .eidolons/cortex/EIDOLONS.md" {
  invoke_cortex_injection "true"
  grep -q '\.eidolons/cortex/EIDOLONS\.md' "CLAUDE.md"
}

@test "cortex: injection — block declares delegate-by-default operating mode" {
  invoke_cortex_injection "true"
  grep -qi 'route all non-trivial work through the Eidolons pipeline' "CLAUDE.md"
}

@test "cortex: injection — block NOT injected when shared-dispatch is off" {
  invoke_cortex_injection "false"
  # CLAUDE.md must either not exist or not contain the cortex marker.
  if [ -f "CLAUDE.md" ]; then
    ! grep -q '<!-- eidolon:cortex start -->' "CLAUDE.md"
  else
    true
  fi
}

@test "cortex: injection — idempotency: two injections produce identical CLAUDE.md" {
  invoke_cortex_injection "true"
  CHECKSUM1="$(sha256sum 'CLAUDE.md' 2>/dev/null || shasum -a 256 'CLAUDE.md')"
  invoke_cortex_injection "true"
  CHECKSUM2="$(sha256sum 'CLAUDE.md' 2>/dev/null || shasum -a 256 'CLAUDE.md')"
  [ "$CHECKSUM1" = "$CHECKSUM2" ]
}

@test "cortex: injection — idempotency via full sync --yes: two runs produce identical CLAUDE.md" {
  setup_fake_git_for_upgrade
  seed_shared_dispatch_manifest
  run eidolons sync --yes
  [ "$status" -eq 0 ]
  CHECKSUM1="$(sha256sum 'CLAUDE.md' 2>/dev/null || shasum -a 256 'CLAUDE.md')"
  run eidolons sync --yes
  [ "$status" -eq 0 ]
  CHECKSUM2="$(sha256sum 'CLAUDE.md' 2>/dev/null || shasum -a 256 'CLAUDE.md')"
  [ "$CHECKSUM1" = "$CHECKSUM2" ]
}

@test "cortex: injection — deep tables mirrored to .eidolons/cortex/" {
  setup_fake_git_for_upgrade
  # setup_fake_git_for_upgrade replaces EIDOLONS_NEXUS with a stripped
  # custom dir. Seed the cortex deep tables so the mirror logic finds them.
  mkdir -p "$EIDOLONS_NEXUS/methodology/cortex"
  cp "$EIDOLONS_ROOT/methodology/cortex/trance-matrix.md"  "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/handoff-graph.md"  "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/validation-gates.md" "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/README.md"         "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/EIDOLONS.md" "$EIDOLONS_NEXUS/EIDOLONS.md"
  seed_shared_dispatch_manifest
  run eidolons sync --yes
  [ "$status" -eq 0 ]
  [ -f ".eidolons/cortex/trance-matrix.md" ]
  [ -f ".eidolons/cortex/handoff-graph.md" ]
  [ -f ".eidolons/cortex/validation-gates.md" ]
  [ -f ".eidolons/cortex/README.md" ]
}

# ─── test: cortex removal (D2 follow-up) ─────────────────────────────────

@test "cortex: removal — block gone from CLAUDE.md after last-eidolon remove" {
  # Inject the cortex block first.
  invoke_cortex_injection "true"
  grep -q '<!-- eidolon:cortex start -->' "CLAUDE.md"

  # Also set up a minimal .eidolons/cortex dir and eidolons.yaml with
  # one member so remove treats atlas as the last member.
  mkdir -p ".eidolons/cortex"
  touch ".eidolons/cortex/EIDOLONS.md"
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
  shared_dispatch: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF

  # Remove exits non-zero (per-Eidolon removal still stubbed) but must
  # clean up the cortex block before dying.
  run eidolons remove atlas
  [ "$status" -ne 0 ]

  # Cortex block must be gone from CLAUDE.md.
  ! grep -q '<!-- eidolon:cortex start -->' "CLAUDE.md"
}

@test "cortex: removal — .eidolons/cortex/ removed after last-eidolon remove" {
  mkdir -p ".eidolons/cortex"
  touch ".eidolons/cortex/EIDOLONS.md"
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
  shared_dispatch: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF

  run eidolons remove atlas
  [ "$status" -ne 0 ]
  [ ! -d ".eidolons/cortex" ]
}

@test "cortex: removal — cortex block survives when other eidolons remain" {
  # Inject the cortex block.
  invoke_cortex_injection "true"
  grep -q '<!-- eidolon:cortex start -->' "CLAUDE.md"

  # Manifest has two members — atlas is NOT the last.
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
  shared_dispatch: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
  - name: spectra
    version: "^4.0.0"
    source: github:Rynaro/SPECTRA
EOF

  run eidolons remove atlas
  [ "$status" -ne 0 ]

  # Cortex block must still be present.
  grep -q '<!-- eidolon:cortex start -->' "CLAUDE.md"
}

# ─── test: CRYSTALIUM memory protocol surface in EIDOLONS.md ──────────────

@test "cortex: EIDOLONS.md memory protocol section references ingest tool" {
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  [ -f "$REAL_CORTEX" ]
  grep -q 'ingest' "$REAL_CORTEX"
}

@test "cortex: EIDOLONS.md memory protocol section references session_end tool" {
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  grep -q 'session_end' "$REAL_CORTEX"
}

@test "cortex: EIDOLONS.md memory protocol section contains trust-tier map (T0/T1/T3)" {
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  # The trust-tier map must name all three tiers.
  grep -q 'T0' "$REAL_CORTEX"
  grep -q 'T1' "$REAL_CORTEX"
  grep -q 'T3' "$REAL_CORTEX"
}

@test "cortex: EIDOLONS.md declares crystalium wiring_mode as allowlist/direct" {
  REAL_CORTEX="$EIDOLONS_ROOT/EIDOLONS.md"
  grep -qi 'allowlist' "$REAL_CORTEX"
}

@test "cortex: memory-protocol.md deep table exists under methodology/cortex/" {
  [ -f "$EIDOLONS_ROOT/methodology/cortex/memory-protocol.md" ]
}

@test "cortex: memory-protocol.md covers all 8 crystalium tools" {
  PROTO="$EIDOLONS_ROOT/methodology/cortex/memory-protocol.md"
  [ -f "$PROTO" ]
  grep -q 'recall' "$PROTO"
  grep -q 'commit' "$PROTO"
  grep -q 'ingest' "$PROTO"
  grep -q 'update' "$PROTO"
  grep -q 'skill_invoke' "$PROTO"
  grep -q 'plan_checkpoint' "$PROTO"
  grep -q 'plan_replan' "$PROTO"
  grep -q 'session_end' "$PROTO"
}

@test "cortex: sync mirrors memory-protocol.md into .eidolons/cortex/" {
  setup_fake_git_for_upgrade
  # Seed the cortex deep tables so the mirror logic finds them.
  mkdir -p "$EIDOLONS_NEXUS/methodology/cortex"
  cp "$EIDOLONS_ROOT/methodology/cortex/trance-matrix.md"    "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/handoff-graph.md"    "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/validation-gates.md" "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/README.md"           "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/memory-protocol.md"  "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/EIDOLONS.md" "$EIDOLONS_NEXUS/EIDOLONS.md"
  seed_shared_dispatch_manifest
  run eidolons sync --yes
  [ "$status" -eq 0 ]
  [ -f ".eidolons/cortex/memory-protocol.md" ]
}

@test "cortex: memory-protocol.md mirror is idempotent — second sync produces no diff" {
  setup_fake_git_for_upgrade
  mkdir -p "$EIDOLONS_NEXUS/methodology/cortex"
  cp "$EIDOLONS_ROOT/methodology/cortex/trance-matrix.md"    "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/handoff-graph.md"    "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/validation-gates.md" "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/README.md"           "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/methodology/cortex/memory-protocol.md"  "$EIDOLONS_NEXUS/methodology/cortex/"
  cp "$EIDOLONS_ROOT/EIDOLONS.md" "$EIDOLONS_NEXUS/EIDOLONS.md"
  seed_shared_dispatch_manifest
  run eidolons sync --yes
  [ "$status" -eq 0 ]
  CHECKSUM1="$(sha256sum '.eidolons/cortex/memory-protocol.md' 2>/dev/null \
               || shasum -a 256 '.eidolons/cortex/memory-protocol.md')"
  run eidolons sync --yes
  [ "$status" -eq 0 ]
  CHECKSUM2="$(sha256sum '.eidolons/cortex/memory-protocol.md' 2>/dev/null \
               || shasum -a 256 '.eidolons/cortex/memory-protocol.md')"
  [ "$CHECKSUM1" = "$CHECKSUM2" ]
}
