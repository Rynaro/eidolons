#!/usr/bin/env bats
#
# atlas-aci dispatch tests — nexus-side (§5.1 of docs/specs/atlas-aci-integration.md).
#
# These tests cover ONLY the nexus's role in routing `eidolons atlas aci …`
# to the ATLAS-shipped script. Full contract tests for commands/aci.sh
# (§4 — prereqs, jq/yq writes, idempotency, exit codes 4–6, etc.) live in
# the ATLAS repo, not here. See docs/specs/atlas-aci-artifacts/ for the
# staged implementation that ships from Rynaro/ATLAS.
#
# Spec gates covered: T1, T2, T3, T4, T5 (A1, A6, A9 by extension).

load helpers

# Fake git used by init tests to block real clones — same pattern as init.bats.
setup_fake_git() {
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "clone" ]]; then
  echo "fake-git: clone blocked in tests" >&2
  exit 128
fi
exec /usr/bin/env git-real "$@" 2>/dev/null || true
EOF
  chmod +x "$FAKE_BIN/git"
  export PATH="$FAKE_BIN:$PATH"
}

# Stage a minimal commands/aci.sh at the installed target. The stub echoes
# a marker on stdout so T1 can assert the dispatcher resolved and exec'd
# the right file. This is deliberately NOT the full §4 contract — that
# script lives in Rynaro/ATLAS; see docs/specs/atlas-aci-artifacts/.
install_atlas_stub_with_aci() {
  mkdir -p ".eidolons/atlas/commands"
  # install.manifest.json presence is ATLAS's signal that it is installed
  # (see §4.3); the guard in commands/aci.sh keys on this file.
  cat > ".eidolons/atlas/install.manifest.json" <<'EOF'
{
  "name": "atlas",
  "version": "1.0.3",
  "hosts_wired": ["claude-code"],
  "files": []
}
EOF
  cat > ".eidolons/atlas/commands/aci.sh" <<'EOF'
#!/usr/bin/env bash
# Test stub — real impl lives in Rynaro/ATLAS per D2.
echo "ATLAS_ACI_STUB_MARKER args=$*"
EOF
  chmod +x ".eidolons/atlas/commands/aci.sh"
}

# Stage a commands/aci.sh that ONLY encodes the §4.3 not-installed guard
# (the file that SHOULD refuse to run when ATLAS is not installed in the
# project). Used by T2. The guard mirrors the staged artifact.
install_atlas_aci_guard_only() {
  # NOTE: the dispatcher prefers installed-target over cache; with no
  # installed target we would normally hit "not installed" at the
  # dispatcher level. To exercise the §4.3 guard explicitly, we stage
  # the script in the cache dir that dispatch_eidolon.sh looks up via
  # $CACHE_DIR/atlas@<version>/commands/. EIDOLONS_HOME is already
  # scoped to $BATS_TEST_TMPDIR by helpers.bash.
  local ver
  ver="$(bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' && roster_get atlas | jq -r '.versions.latest'")"
  local cache_commands="$EIDOLONS_HOME/cache/atlas@${ver}/commands"
  mkdir -p "$cache_commands"
  cat > "$cache_commands/aci.sh" <<'EOF'
#!/usr/bin/env bash
# Minimal §4.3 guard — full script lives in Rynaro/ATLAS.
set -euo pipefail
if [[ ! -f "./.eidolons/atlas/install.manifest.json" ]]; then
  echo "atlas-aci: ATLAS is not installed in this project." >&2
  echo "  Run 'eidolons sync' to install ATLAS first." >&2
  exit 3
fi
echo "would-have-run"
EOF
  chmod +x "$cache_commands/aci.sh"
}

# ─── T1 ───────────────────────────────────────────────────────────────────
@test "atlas aci: dispatch resolves to ATLAS's shipped script (T1)" {
  install_atlas_stub_with_aci
  run eidolons atlas aci --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ ATLAS_ACI_STUB_MARKER ]]
  # Args are passed through untouched.
  [[ "$output" =~ --dry-run ]]
}

# ─── T2 ───────────────────────────────────────────────────────────────────
@test "atlas aci: exit 3 when ATLAS is not installed (T2)" {
  # Fresh tmpdir — no ./.eidolons/atlas/. Script sourced from the cache
  # fallback path so the §4.3 install-manifest guard can fire.
  install_atlas_aci_guard_only
  run eidolons atlas aci
  [ "$status" -eq 3 ]
  [[ "$output" =~ eidolons\ sync ]]
}

# ─── T3 ───────────────────────────────────────────────────────────────────
@test "atlas aci: eidolons init does not invoke atlas-aci (T3 / A1)" {
  # Block real clones so init's post-manifest sync fails fast without
  # doing any per-Eidolon install work. The assertion is that init
  # produces NO atlas-aci side effects regardless of how far sync gets:
  # no .mcp.json, no .cursor/mcp.json, no .github/agents/*.agent.md
  # changes, no .gitignore change, no .atlas/ directory, and the string
  # "atlas-aci" never appears in any generated config.
  setup_fake_git
  run eidolons init --preset pipeline --hosts claude-code --non-interactive

  [ ! -f ".mcp.json" ]
  [ ! -f ".cursor/mcp.json" ]
  [ ! -d ".atlas" ]
  # No agent files written by init.
  if [[ -d ".github/agents" ]]; then
    run bash -c 'shopt -s nullglob; for f in .github/agents/*.agent.md; do echo FOUND; done'
    [ -z "$output" ]
  fi
  # The substring "atlas-aci" must not appear in eidolons.yaml.
  ! grep -q "atlas-aci" eidolons.yaml
}

# ─── T4 ───────────────────────────────────────────────────────────────────
@test "atlas aci: eidolons sync does not invoke atlas-aci (T4 / A1)" {
  # Seed a manifest (which names atlas but not atlas-aci), run sync in
  # dry-run so no real clones happen, and verify no atlas-aci side
  # effects appeared. A1's invariant is that the string 'atlas-aci'
  # nowhere appears in generated files.
  seed_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]

  [ ! -f ".mcp.json" ]
  [ ! -f ".cursor/mcp.json" ]
  [ ! -d ".atlas" ]
  ! grep -q "atlas-aci" eidolons.yaml
  # eidolons.lock is written in dry-run mode with a header; ensure the
  # string does not sneak in via any generated content.
  if [[ -f eidolons.lock ]]; then
    ! grep -q "atlas-aci" eidolons.lock
  fi
}

# ─── T5 ───────────────────────────────────────────────────────────────────
@test "atlas aci: no roster preset references atlas-aci (T5 / A9 / D4)" {
  # Belt-and-suspenders: locked by D4, enforced here.
  roster_json="$(bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' && yaml_to_json '$EIDOLONS_ROOT/roster/index.yaml'")"

  # No roster entry named 'atlas-aci'.
  run bash -c "echo '$roster_json' | jq -r '.eidolons[].name'"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -Fxq "atlas-aci"

  # No preset lists 'atlas-aci' as a member.
  run bash -c "echo '$roster_json' | jq -r '.presets | to_entries[].value.members[]?'"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -Fxq "atlas-aci"
}
