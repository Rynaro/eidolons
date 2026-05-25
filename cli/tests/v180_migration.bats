#!/usr/bin/env bats
# cli/tests/v180_migration.bats — R5-5 v1.8.0 → v1.8.1 migration tests.
#
# Tests the two-phase migration path (R5-D7):
#   Phase A (auto on sync): universal marker-guard hoists CLAUDE.md markers into
#              EIDOLONS.md. No manifest mutation.
#   Phase B (explicit eidolons init --re-derive): updates hosts.pointer_targets to
#              include wired vendor files (default-Y multi-pointer).
#
# Fixture: cli/tests/fixtures/v1.8.0-migration/ — alchemists-orchid style state.

load helpers

# ─── Phase A: compose_eidolons_md universal marker-guard ────────────────────

# R5-mig-1: Phase A — CLAUDE.md with substantive markers gets included in
#   _compose_sources when pointer_targets=[AGENTS.md].
@test "v1.8.0 migration Phase A: CLAUDE.md markers included in _compose_sources (R5)" {
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/CLAUDE.md.v1.8.0" CLAUDE.md

  result="$(bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    POINTER_TARGETS_CSV='AGENTS.md'
    _compose_sources=''
    for _cpt in \$(echo \"\$POINTER_TARGETS_CSV\" | tr ',' ' '); do
      [[ -z \"\$_cpt\" ]] && continue
      _compose_sources=\"\$_compose_sources ./\$_cpt\"
    done
    for _vfile in CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md; do
      [[ -f \"\$_vfile\" ]] || continue
      grep -qE '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' \"\$_vfile\" 2>/dev/null || continue
      grep -E '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' \"\$_vfile\" 2>/dev/null \\
        | grep -vqE 'eidolon:dispatch-pointer' || continue
      case \" \$_compose_sources \" in
        *\" ./\$_vfile \"*) : ;;
        *) _compose_sources=\"\$_compose_sources ./\$_vfile\" ;;
      esac
    done
    _compose_sources=\"\$(echo \"\$_compose_sources\" | xargs 2>/dev/null || true)\"
    echo \"\$_compose_sources\"
  " 2>/dev/null)"
  # CLAUDE.md must be in _compose_sources (the universal marker-guard fires).
  [[ "$result" == *"./CLAUDE.md"* ]]
}

# R5-mig-2: Phase A — AGENTS.md with only cortex+dispatch-pointer markers is not
#   re-added as a substantive source (its only-pointer content skips the guard).
@test "v1.8.0 migration Phase A: AGENTS.md with only pointer markers not duplicated (R5)" {
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/AGENTS.md.v1.8.0" AGENTS.md

  result="$(bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    POINTER_TARGETS_CSV='AGENTS.md'
    _compose_sources=''
    for _cpt in \$(echo \"\$POINTER_TARGETS_CSV\" | tr ',' ' '); do
      [[ -z \"\$_cpt\" ]] && continue
      _compose_sources=\"\$_compose_sources ./\$_cpt\"
    done
    for _vfile in CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md; do
      [[ -f \"\$_vfile\" ]] || continue
      grep -qE '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' \"\$_vfile\" 2>/dev/null || continue
      grep -E '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' \"\$_vfile\" 2>/dev/null \\
        | grep -vqE 'eidolon:dispatch-pointer' || continue
      case \" \$_compose_sources \" in
        *\" ./\$_vfile \"*) : ;;
        *) _compose_sources=\"\$_compose_sources ./\$_vfile\" ;;
      esac
    done
    _compose_sources=\"\$(echo \"\$_compose_sources\" | xargs 2>/dev/null || true)\"
    echo \"\$_compose_sources\"
  " 2>/dev/null)"
  # AGENTS.md already in pointer_targets — exactly one occurrence.
  count="$(printf '%s\n' "$result" | tr ' ' '\n' | grep -c './AGENTS.md' || true)"
  [ "$count" -eq 1 ]
  # CLAUDE.md must NOT be added (it's absent from disk in this test).
  ! [[ "$result" == *"./CLAUDE.md"* ]]
}

# ─── Phase A: compose_eidolons_md hoisting ────────────────────────────────────

# R5-mig-3: Phase A via compose_eidolons_md — CLAUDE.md markers are hoisted into
#   EIDOLONS.md and removed from CLAUDE.md.
@test "v1.8.0 migration Phase A: compose_eidolons_md hoists CLAUDE.md into EIDOLONS.md (R5)" {
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/CLAUDE.md.v1.8.0" CLAUDE.md
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/AGENTS.md.v1.8.0" AGENTS.md
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/EIDOLONS.md.v1.8.0" EIDOLONS.md

  bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh' >/dev/null 2>&1
    compose_eidolons_md 'atlas spectra' './AGENTS.md ./CLAUDE.md'
  " 2>/dev/null

  # CLAUDE.md should no longer contain substantive markers (hoisted).
  ! grep -qF '<!-- eidolon:atlas start -->' CLAUDE.md
  ! grep -qF '<!-- eidolon:spectra start -->' CLAUDE.md

  # EIDOLONS.md should still have the content blocks.
  grep -qF '<!-- eidolon:atlas start -->' EIDOLONS.md
  grep -qF '<!-- eidolon:spectra start -->' EIDOLONS.md

  # AGENTS.md should be unchanged (only pointer markers, nothing to hoist).
  grep -qF '<!-- eidolon:dispatch-pointer start -->' AGENTS.md
}

# R5-mig-4: Phase A idempotency — running compose_eidolons_md twice is safe.
@test "v1.8.0 migration Phase A: compose idempotency — second run unchanged (R5)" {
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/CLAUDE.md.v1.8.0" CLAUDE.md
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/AGENTS.md.v1.8.0" AGENTS.md
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/EIDOLONS.md.v1.8.0" EIDOLONS.md

  bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh' >/dev/null 2>&1
    compose_eidolons_md 'atlas spectra' './AGENTS.md ./CLAUDE.md'
  " 2>/dev/null

  cp EIDOLONS.md EIDOLONS.md.first
  cp CLAUDE.md CLAUDE.md.first

  bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh' >/dev/null 2>&1
    compose_eidolons_md 'atlas spectra' './AGENTS.md ./CLAUDE.md'
  " 2>/dev/null

  diff -q EIDOLONS.md EIDOLONS.md.first
  diff -q CLAUDE.md CLAUDE.md.first
}

# ─── Phase B: --re-derive updates manifest ────────────────────────────────────

# R5-mig-5: Phase B — --re-derive with v1.8.0 manifest (pointer_targets=[AGENTS.md])
#   → default-Y multi-pointer updates to [AGENTS.md, CLAUDE.md].
@test "v1.8.0 migration Phase B: --re-derive default-Y updates pointer_targets (R5)" {
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/eidolons.yaml.v1.8.0" eidolons.yaml

  run bash "$EIDOLONS_ROOT/cli/eidolons" init --re-derive
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Updated hosts.pointer_targets" ]]

  # pointer_targets must now include CLAUDE.md (default-Y multi-pointer).
  grep -qF "CLAUDE.md" eidolons.yaml
  grep -qF "AGENTS.md" eidolons.yaml

  # Other fields must be preserved.
  grep -qF "shared_dispatch: true" eidolons.yaml
  grep -qF "strict: false" eidolons.yaml
  grep -qF "name: atlas" eidolons.yaml
  grep -qF "name: spectra" eidolons.yaml
}

# R5-mig-6: Phase B — --re-derive --no-multi-pointer keeps AGENTS.md only.
@test "v1.8.0 migration Phase B: --re-derive --no-multi-pointer stays AGENTS.md only (R5)" {
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/eidolons.yaml.v1.8.0" eidolons.yaml

  run bash "$EIDOLONS_ROOT/cli/eidolons" init --re-derive --no-multi-pointer
  [ "$status" -eq 0 ]
  grep -qF "AGENTS.md" eidolons.yaml
  ! grep -E "pointer_targets:.*CLAUDE" eidolons.yaml
}

# ─── Doctor Check 14 bridges A → B ───────────────────────────────────────────

# R5-mig-7: Doctor Check 14 fires on v1.8.0 manifest state (before Phase B).
@test "v1.8.0 migration: Doctor Check 14 fires before Phase B (R5)" {
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/eidolons.yaml.v1.8.0" eidolons.yaml

  # Seed lock + install manifest so doctor passes checks 1-13.
  cat > eidolons.lock <<'LOCK'
generated_at: "2026-05-25T00:00:00Z"
eidolons_cli_version: "1.8.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.5.3"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
  - name: spectra
    version: "4.3.3"
    resolved: "github:Rynaro/SPECTRA@test"
    target: "./.eidolons/spectra"
    hosts_wired: ["claude-code"]
LOCK
  mkdir -p .eidolons/atlas .eidolons/spectra .claude/agents
  cat > .eidolons/atlas/install.manifest.json <<'EOF'
{"name":"atlas","version":"1.5.3","hosts_wired":["claude-code"],"files":[]}
EOF
  cat > .eidolons/spectra/install.manifest.json <<'EOF'
{"name":"spectra","version":"4.3.3","hosts_wired":["claude-code"],"files":[]}
EOF
  echo "---" > .claude/agents/atlas.md
  echo "---" > .claude/agents/spectra.md
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/CLAUDE.md.v1.8.0" CLAUDE.md
  cp "$BATS_TEST_DIRNAME/fixtures/v1.8.0-migration/AGENTS.md.v1.8.0" AGENTS.md

  run bash "$EIDOLONS_ROOT/cli/eidolons" doctor
  # Check 14 fires: CLAUDE.md has substantive markers, claude-code wired, not in pointer_targets.
  [[ "$output" =~ "carries Eidolon content markers but is not in hosts.pointer_targets" ]]
  [[ "$output" =~ "CLAUDE.md" ]]
}

# R5-mig-8: hoisted_from is [] when pointer_targets=[] and no vendor files have markers.
@test "v1.8.0 migration: lock hoisted_from is empty array when no sources (R5)" {
  # Manifest with explicit empty pointer_targets and no host-derived fallback.
  # cursor host has no vendor pointer file (maps to nothing), so _compose_sources = empty.
  cat > eidolons.yaml <<'YAML'
version: 1
hosts:
  wire: [cursor]
  shared_dispatch: false
  strict: false
  pointer_targets: []
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
YAML

  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  [ -f eidolons.lock ]
  grep -qF "hoisted_from: []" eidolons.lock
}
