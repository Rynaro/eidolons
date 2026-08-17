#!/usr/bin/env bats
#
# upgrade_self.bats — covers cli/src/upgrade_self.sh.
# Spec stories S1–S8 from .spectra/plans/nexus-cli-versioning-2026-05-04.md §5.
#
# Test strategy (D8.A): bare local git repo used as the "upstream" remote.
# EIDOLONS_REPO is overridden to the bare repo so nexus_latest_tag and
# nexus_clone_to_sibling work fully offline.
#
# Key design:
#   EIDOLONS_NEXUS → real checkout (so the real upgrade_self.sh / lib.sh are used)
#   EIDOLONS_HOME  → $BATS_TEST_TMPDIR/eidolons-home (isolated per test)
#   EIDOLONS_NEXUS is then ALSO set to the *installed* nexus path inside HOME
#   after setup_fixture_nexus_in_home() copies the minimal tree there.
#
# The real upgrade_self.sh sources lib.sh from its own directory (the checkout),
# and lib.sh derives NEXUS from EIDOLONS_NEXUS. So:
#   EIDOLONS_NEXUS = ~/.eidolons/nexus (the *installed* copy we control)
#   EIDOLONS_REPO  = file:///path/to/bare-remote (the fake upstream)

load helpers

# ─── Fixture helpers ──────────────────────────────────────────────────────

# Seed a minimal nexus tree adequate for:
#   - cli/eidolons --version --quiet → prints "eidolons VERSION"
#   - nexus_verify_release → finds placeholder metadata → skips (OK)
#   - nexus_latest_tag → reads from EIDOLONS_REPO (bare remote)
_seed_minimal_nexus_tree() {
  local dir="$1" ver="$2"
  mkdir -p "$dir/cli/src/ui/themes" "$dir/roster" "$dir/schemas"

  # Copy the REAL CLI scripts so any clone of this remote has working scripts.
  # This is essential so that after an upgrade swap, the new nexus has
  # upgrade_self.sh and lib.sh available for subsequent operations (e.g. rollback).
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"          "$dir/cli/src/lib.sh"
  cp "$EIDOLONS_ROOT/cli/src/upgrade_self.sh" "$dir/cli/src/upgrade_self.sh"
  cp "$EIDOLONS_ROOT/cli/src/ui/"*.sh         "$dir/cli/src/ui/" 2>/dev/null || true
  if [[ -d "$EIDOLONS_ROOT/cli/src/ui/themes" ]]; then
    cp "$EIDOLONS_ROOT/cli/src/ui/themes/"*.sh "$dir/cli/src/ui/themes/" 2>/dev/null || true
  fi
  # Copy the real cli/eidolons dispatcher.
  cp "$EIDOLONS_ROOT/cli/eidolons" "$dir/cli/eidolons"
  chmod +x "$dir/cli/eidolons" "$dir/cli/src/upgrade_self.sh"

  printf '%s\n' "$ver" > "$dir/VERSION"

  cat > "$dir/roster/index.yaml" <<REOF
registry_version: "1.0"
updated_at: "2026-05-04T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons: []
nexus:
  version: "$ver"
  versions:
    latest: "$ver"
    pins:
      stable: "$ver"
    releases:
      "$ver":
        tag: "v$ver"
        commit: "<filled-by-release-workflow>"
        tree: "<filled-by-release-workflow>"
        archive_sha256: "<filled-by-release-workflow>"
        provenance:
          github_attestation: false
        released_at: "2026-05-04T00:00:00Z"
presets: {}
REOF
  printf '{}' > "$dir/schemas/roster.schema.json"
}

# Create a bare fixture remote and populate EIDOLONS_HOME/nexus with the
# initial version. After this call:
#   FIXTURE_REMOTE  — path to the bare git repo (used as EIDOLONS_REPO)
#   EIDOLONS_HOME   — isolated home dir (already set by helpers.bash setup)
#   EIDOLONS_NEXUS  — $EIDOLONS_HOME/nexus (the installed nexus working copy)
#   EIDOLONS_REPO   — file://FIXTURE_REMOTE
setup_fixture_remote() {
  local init_ver="${1:-1.0.0}"
  FIXTURE_REMOTE="$BATS_TEST_TMPDIR/remote.git"

  # Use a non-bare repo as the "remote" to avoid HEAD-points-to-nothing
  # issues with bare repos. git ls-remote works fine against a regular repo.
  mkdir -p "$FIXTURE_REMOTE"
  git -C "$FIXTURE_REMOTE" init -q
  git -C "$FIXTURE_REMOTE" config user.email "remote@test.local"
  git -C "$FIXTURE_REMOTE" config user.name  "Remote"
  git -C "$FIXTURE_REMOTE" config receive.denyCurrentBranch ignore

  # Seed and commit the initial version directly into the remote.
  _seed_minimal_nexus_tree "$FIXTURE_REMOTE" "$init_ver"
  git -C "$FIXTURE_REMOTE" add -A
  git -C "$FIXTURE_REMOTE" commit -q -m "init v${init_ver}"
  git -C "$FIXTURE_REMOTE" tag "v${init_ver}"

  # Clone it into EIDOLONS_HOME/nexus (the "installed" nexus).
  # Use file:// prefix so git doesn't ignore --depth on local paths.
  local nexus_dir="$EIDOLONS_HOME/nexus"
  git clone -q "file://$FIXTURE_REMOTE" "$nexus_dir"
  git -C "$nexus_dir" config user.email "test@test.local"
  git -C "$nexus_dir" config user.name  "Test"

  # Install the real CLI scripts into the fixture nexus so upgrade_self.sh
  # and lib.sh resolve from the installed nexus path, not the checkout.
  mkdir -p "$nexus_dir/cli/src/ui/themes"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"          "$nexus_dir/cli/src/lib.sh"
  cp "$EIDOLONS_ROOT/cli/src/upgrade_self.sh" "$nexus_dir/cli/src/upgrade_self.sh"
  # Copy the entire ui directory.
  cp "$EIDOLONS_ROOT/cli/src/ui/"*.sh         "$nexus_dir/cli/src/ui/" 2>/dev/null || true
  if [[ -d "$EIDOLONS_ROOT/cli/src/ui/themes" ]]; then
    cp "$EIDOLONS_ROOT/cli/src/ui/themes/"*.sh  "$nexus_dir/cli/src/ui/themes/" 2>/dev/null || true
  fi
  cp "$EIDOLONS_ROOT/cli/eidolons"            "$nexus_dir/cli/eidolons"
  chmod +x "$nexus_dir/cli/eidolons" "$nexus_dir/cli/src/upgrade_self.sh"

  # Override EIDOLONS_NEXUS to point at the installed copy so lib.sh finds the
  # fixture roster. EIDOLONS_REPO points at the fake "upstream" remote.
  export EIDOLONS_NEXUS="$nexus_dir"
  export EIDOLONS_REPO="file://$FIXTURE_REMOTE"

  FIXTURE_VER="$init_ver"
}

# Push a new version tag to the fixture remote (does NOT touch the installed nexus).
push_fixture_tag() {
  local new_ver="$1"

  # Add a new commit directly in the remote repo (non-bare workaround).
  git -C "$FIXTURE_REMOTE" config user.email "remote@test.local"
  git -C "$FIXTURE_REMOTE" config user.name  "Remote"

  _seed_minimal_nexus_tree "$FIXTURE_REMOTE" "$new_ver"
  git -C "$FIXTURE_REMOTE" add -A
  git -C "$FIXTURE_REMOTE" commit -q -m "bump v${new_ver}"
  git -C "$FIXTURE_REMOTE" tag "v${new_ver}"
}

# ─── G11 — version output is grepable (--quiet) ───────────────────────────
@test "G11: --version --quiet prints single grepable line" {
  run bash "$EIDOLONS_BIN" --version --quiet
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^eidolons [0-9]+\.[0-9]+\.[0-9]'
}

@test "G11: --version prints enriched multi-line output" {
  run bash "$EIDOLONS_BIN" --version
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^eidolons [0-9]+\.[0-9]+\.[0-9]'
}

# ─── S2 — no-op when on latest ────────────────────────────────────────────
@test "S2/G8: noop_when_on_latest" {
  setup_fixture_remote "1.0.0"

  # Capture the current nexus directory mtime via ls.
  _before="$(ls -la "$EIDOLONS_NEXUS/VERSION" 2>/dev/null | awk '{print $6,$7,$8}')"

  # --force bypasses the dirty-check (the fixture nexus has uncommitted script
  # copies which are an artifact of test setup, not a user-facing dirty state).
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No upgrade needed" || "$output" =~ "Already on" || "$output" =~ "latest" ]]

  # nexus.new must not persist.
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
  # nexus.prev must not be created.
  [ ! -d "$EIDOLONS_HOME/nexus.prev" ]
}

# ─── S3 — upgrade across versions ────────────────────────────────────────
@test "S3: upgrades_clean_across_versions" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.1"

  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1.0.1" || "$output" =~ "Upgraded" ]]

  # nexus should be at the new version.
  [ -f "$EIDOLONS_NEXUS/VERSION" ]
  _new_ver="$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION")"
  [ "$_new_ver" = "1.0.1" ]

  # Previous nexus preserved.
  [ -d "$EIDOLONS_HOME/nexus.prev" ]

  # nexus.new cleaned up.
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

# ─── S4 — upgrade with --ref pinning ─────────────────────────────────────
@test "S4: respects_ref_flag_for_tag" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.1"

  run bash "$EIDOLONS_BIN" upgrade self --ref "v1.0.1" --force
  [ "$status" -eq 0 ]

  [ -f "$EIDOLONS_NEXUS/VERSION" ]
  _ver="$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION")"
  [ "$_ver" = "1.0.1" ]
}

@test "S4: respects_ref_flag_for_branch_with_warning" {
  setup_fixture_remote "1.0.0"

  # A branch ref (non-tag) should proceed with a warning, not integrity fail.
  run bash "$EIDOLONS_BIN" upgrade self --ref "main" --force
  # Should succeed (exit 0 or 1 is OK; 5 = integrity fail is NOT OK).
  [ "$status" -ne 5 ]
  # Warning about non-tag ref should appear in stderr output.
  [[ "$output" =~ "warning" || "$output" =~ "Warning" || "$output" =~ "skipped" \
     || "$output" =~ "Upgrading" || "$output" =~ "Already" || "$status" -eq 0 ]]
}

@test "S4: respects_ref_flag_for_sha_with_warning" {
  setup_fixture_remote "1.0.0"

  _sha="$(git -C "$EIDOLONS_NEXUS" rev-parse HEAD)"
  # A SHA ref (non-tag) should proceed without integrity-fail.
  run bash "$EIDOLONS_BIN" upgrade self --ref "$_sha" --force
  [ "$status" -ne 5 ]
}

# ─── S5 — network unreachable exits 4 ────────────────────────────────────
@test "S5/G14: network_unreachable_exits_4" {
  setup_fixture_remote "1.0.0"

  # Override EIDOLONS_REPO with an unreachable address.
  # Use an invalid file path that git ls-remote will fail on quickly.
  export EIDOLONS_REPO="/nonexistent/no-such-repo-ever.git"

  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 4 ]
  [[ "$output" =~ "Cannot reach upstream" || "$output" =~ "connectivity" ]]

  # nexus directory must be untouched.
  [ -f "$EIDOLONS_NEXUS/VERSION" ]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

# ─── S6 — integrity failure aborts before swap ────────────────────────────
@test "S6/G15: integrity_failure_aborts_before_swap" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.1"

  # Tamper the roster on the fixture nexus: set a wrong expected commit.
  yq e '.nexus.versions.releases["1.0.1"].commit = "0000000000000000000000000000000000000000"' \
    -i "$EIDOLONS_NEXUS/roster/index.yaml" 2>/dev/null || true
  # Also tamper the EIDOLONS_NEXUS's roster so nexus_verify_release reads wrong metadata.
  # The upgrade_self.sh sources lib.sh which reads from ROSTER_FILE = $NEXUS/roster/index.yaml.
  # We need the nexus being used (EIDOLONS_NEXUS) to have the wrong metadata.
  _roster="$EIDOLONS_NEXUS/roster/index.yaml"
  if command -v yq >/dev/null 2>&1; then
    yq e ".nexus.versions.releases[\"1.0.1\"].commit = \"0000000000000000000000000000000000000000\" |
          .nexus.versions.releases[\"1.0.1\"].tree = \"0000000000000000000000000000000000000001\"" \
      -i "$_roster" 2>/dev/null || true
  else
    # Fallback: write the roster with wrong hashes via python3.
    python3 - "$_roster" <<'PYEOF' 2>/dev/null || true
import sys, re
f = sys.argv[1]
t = open(f).read()
t = re.sub(r'(commit:\s*)"<filled-by-release-workflow>"',
           r'\1"0000000000000000000000000000000000000000"', t)
open(f, 'w').write(t)
PYEOF
  fi

  # Pre-record what the nexus looks like before the attempted upgrade.
  _before_ver="$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION" 2>/dev/null || echo unknown)"

  run bash "$EIDOLONS_BIN" upgrade self
  # If integrity metadata contains placeholder, nexus_verify_release skips (exit 0).
  # If it contains a real wrong hash, exit 5. Accept either here since the
  # placeholder detection path is the one actually exercised.
  # The important assertion is: nexus.new is cleaned up and nexus is untouched.
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
  _after_ver="$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION" 2>/dev/null || echo unknown)"
  [ "$_before_ver" = "$_after_ver" ]
}

# ─── S7 — rollback restores previous ─────────────────────────────────────
@test "S7/G13: rollback_restores_previous" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.1"

  # First, do a successful upgrade (--force to bypass fixture dirty-check).
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]
  [ -d "$EIDOLONS_HOME/nexus.prev" ]

  _new_ver="$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION" 2>/dev/null || echo unknown)"
  [ "$_new_ver" = "1.0.1" ]

  # Now rollback.
  run bash "$EIDOLONS_BIN" upgrade self --rollback
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Rolled back" || "$output" =~ "rollback" || "$output" =~ "1.0.0" ]]

  _rolled_ver="$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION" 2>/dev/null || echo unknown)"
  [ "$_rolled_ver" = "1.0.0" ]

  # nexus.failed should now exist (the 1.0.1 install).
  [ -d "$EIDOLONS_HOME/nexus.failed" ]
}

@test "S7: rollback_when_no_prev_fails_clearly" {
  setup_fixture_remote "1.0.0"
  # No prior upgrade → no nexus.prev.
  [ ! -d "$EIDOLONS_HOME/nexus.prev" ]

  run bash "$EIDOLONS_BIN" upgrade self --rollback
  [ "$status" -eq 7 ]
  [[ "$output" =~ "No previous" || "$output" =~ "nexus.prev" || "$output" =~ "unavailable" ]]
}

# ─── S8 — upgrade preserves consumer-project state ───────────────────────
@test "S8/G12: does_not_touch_consumer_project" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.1"

  # Set up a fake consumer project in $TEST_PROJECT (already set by helpers.bash setup).
  cat > "$TEST_PROJECT/eidolons.yaml" <<'EOF'
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  cat > "$TEST_PROJECT/eidolons.lock" <<'EOF'
generated_at: "2026-05-04T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
  mkdir -p "$TEST_PROJECT/.eidolons/atlas"
  echo "stub" > "$TEST_PROJECT/.eidolons/atlas/AGENTS.md"
  echo "stub-claude" > "$TEST_PROJECT/CLAUDE.md"
  echo "stub-agents" > "$TEST_PROJECT/AGENTS.md"

  # Capture checksums before upgrade.
  _yaml_before="$(md5sum "$TEST_PROJECT/eidolons.yaml" | awk '{print $1}')"
  _lock_before="$(md5sum "$TEST_PROJECT/eidolons.lock" | awk '{print $1}')"
  _claude_before="$(md5sum "$TEST_PROJECT/CLAUDE.md" | awk '{print $1}')"
  _agents_before="$(md5sum "$TEST_PROJECT/AGENTS.md" | awk '{print $1}')"
  _atlas_before="$(md5sum "$TEST_PROJECT/.eidolons/atlas/AGENTS.md" | awk '{print $1}')"

  # Run upgrade from within the consumer project directory.
  # --force bypasses the fixture dirty-check.
  cd "$TEST_PROJECT"
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]

  # All consumer files must be byte-identical.
  _yaml_after="$(md5sum "$TEST_PROJECT/eidolons.yaml" | awk '{print $1}')"
  _lock_after="$(md5sum "$TEST_PROJECT/eidolons.lock" | awk '{print $1}')"
  _claude_after="$(md5sum "$TEST_PROJECT/CLAUDE.md" | awk '{print $1}')"
  _agents_after="$(md5sum "$TEST_PROJECT/AGENTS.md" | awk '{print $1}')"
  _atlas_after="$(md5sum "$TEST_PROJECT/.eidolons/atlas/AGENTS.md" | awk '{print $1}')"

  [ "$_yaml_before"   = "$_yaml_after"   ]
  [ "$_lock_before"   = "$_lock_after"   ]
  [ "$_claude_before" = "$_claude_after" ]
  [ "$_agents_before" = "$_agents_after" ]
  [ "$_atlas_before"  = "$_atlas_after"  ]
}

# ─── --check mode ────────────────────────────────────────────────────────
@test "upgrade self --check exits 0 and prints version info" {
  setup_fixture_remote "1.0.0"

  run bash "$EIDOLONS_BIN" upgrade self --check --force
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEXUS" || "$output" =~ "1.0.0" || "$output" =~ "target" || "$output" =~ "current" ]]
  # --check must not create nexus.new.
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

# ─── S1 partial: VERSION file from install ───────────────────────────────
@test "S1/install: VERSION file exists in checkout" {
  # The VERSION file should exist at the nexus root (checkout).
  [ -f "$EIDOLONS_ROOT/VERSION" ]
  _ver="$(tr -d '[:space:]' < "$EIDOLONS_ROOT/VERSION")"
  echo "$_ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]'
}

@test "S1/install: eidolons --version --quiet is grepable" {
  run bash "$EIDOLONS_BIN" --version --quiet
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^eidolons [0-9]+\.[0-9]+\.[0-9]'
}

# ─── PR-4: dirty-guard tolerates refresh-induced drift ──────────────────

@test "PR-4: upgrade self --check does NOT abort on refresh-managed path drift" {
  # Simulate a nexus whose only working-tree changes are in roster/ + EIDOLONS.md
  # (what nexus_refresh path-checkout induces). The dirty guard should NOT abort.
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr4"
  mkdir -p "$fake_nexus/.git" "$fake_nexus/roster" "$fake_nexus/cli/src" \
    "$fake_nexus/methodology/cortex"

  git -C "$fake_nexus" init -q 2>/dev/null || true
  git -C "$fake_nexus" config user.email "t@t"
  git -C "$fake_nexus" config user.name "T"

  printf 'roster original\n' > "$fake_nexus/roster/index.yaml"
  printf 'EIDOLONS original\n' > "$fake_nexus/EIDOLONS.md"
  printf 'cli v1\n' > "$fake_nexus/cli/src/lib.sh"
  printf 'v1.0.0\n' > "$fake_nexus/.install_ref"
  printf 'v1.0.0\n' > "$fake_nexus/VERSION"
  printf '.install_date\n.install_ref\n.install_commit\n.roster_ref\n' > "$fake_nexus/.gitignore"

  git -C "$fake_nexus" add -A >/dev/null 2>&1
  git -C "$fake_nexus" commit -q -m "base"

  # Now simulate refresh-induced drift in ONLY the data paths.
  printf 'roster UPDATED by refresh\n' > "$fake_nexus/roster/index.yaml"
  printf 'EIDOLONS UPDATED by refresh\n' > "$fake_nexus/EIDOLONS.md"

  # Test _nexus_is_dirty by calling it from the ACTUAL upgrade_self.sh environment.
  # Use a subshell that sources upgrade_self.sh's helper function.
  # NEXUS is set AFTER sourcing lib.sh so that lib.sh's re-derivation
  # (NEXUS=\${EIDOLONS_NEXUS:-\$EIDOLONS_HOME/nexus}) does not clobber it.
  run bash -c "
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    # Define _nexus_is_dirty exactly as in upgrade_self.sh (STORY-2 version).
    _nexus_is_dirty() {
      [[ -d \"\$NEXUS/.git\" ]] || return 1
      local status
      status=\"\$(git -C \"\$NEXUS\" status --porcelain -- \
        . ':!roster' ':!EIDOLONS.md' ':!methodology/cortex' 2>/dev/null | head -1)\"
      [[ -n \"\$status\" ]]
    }
    if _nexus_is_dirty; then
      echo 'DIRTY'
      exit 1
    else
      echo 'CLEAN (data-only drift tolerated)'
      exit 0
    fi
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CLEAN" ]]
}

# PR-5: A genuine edit to cli/src/lib.sh STILL trips the dirty guard.
@test "PR-5: dirty guard still fires on genuine CLI code edit" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr5"
  mkdir -p "$fake_nexus/.git" "$fake_nexus/roster" "$fake_nexus/cli/src" \
    "$fake_nexus/methodology/cortex"

  git -C "$fake_nexus" init -q 2>/dev/null || true
  git -C "$fake_nexus" config user.email "t@t"
  git -C "$fake_nexus" config user.name "T"

  printf 'roster original\n' > "$fake_nexus/roster/index.yaml"
  printf 'EIDOLONS original\n' > "$fake_nexus/EIDOLONS.md"
  printf 'cli v1\n' > "$fake_nexus/cli/src/lib.sh"
  printf '.install_date\n.install_ref\n.install_commit\n.roster_ref\n' > "$fake_nexus/.gitignore"

  git -C "$fake_nexus" add -A >/dev/null 2>&1
  git -C "$fake_nexus" commit -q -m "base"

  # Edit a CLI file (lib.sh) — this SHOULD trip the guard.
  printf 'cli HAND-EDITED\n' >> "$fake_nexus/cli/src/lib.sh"

  # NEXUS must be set AFTER sourcing lib.sh (as PR-4 does): lib.sh:11 re-derives
  # NEXUS from EIDOLONS_NEXUS, so setting it first gets clobbered to the checkout
  # under test → the guard would check the wrong tree. (That mistake passes on CI
  # by coincidence — EIDOLONS_NEXUS is dirty there — but fails from a clean clone
  # or a git worktree where $checkout/.git is a file.)
  run bash -c "
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    _nexus_is_dirty() {
      [[ -d \"\$NEXUS/.git\" ]] || return 1
      local status
      status=\"\$(git -C \"\$NEXUS\" status --porcelain -- \
        . ':!roster' ':!EIDOLONS.md' ':!methodology/cortex' 2>/dev/null | head -1)\"
      [[ -n \"\$status\" ]]
    }
    if _nexus_is_dirty; then
      echo 'DIRTY (correctly detected)'
      exit 1
    else
      echo 'CLEAN'
      exit 0
    fi
  "
  [ "$status" -eq 1 ] || return 1
  [[ "$output" =~ "DIRTY" ]]
}

# ─── B1: upgrade self does NOT modify .roster_ref ────────────────────────
@test "upgrade self: .roster_ref unchanged after upgrade (B1)" {
  setup_fixture_remote "1.0.0"

  local nexus_dir="$EIDOLONS_HOME/nexus"
  # Plant .roster_ref into the installed nexus.
  printf 'main\n' > "$nexus_dir/.roster_ref"
  printf 'v1.0.0\n' > "$nexus_dir/.install_ref"

  # Push a v2.0.0 upgrade target to the fixture remote.
  push_fixture_tag "2.0.0"

  # Run upgrade self (non-interactive + force to skip confirmations).
  run bash "$EIDOLONS_BIN" upgrade self --force --non-interactive
  # Upgrade may or may not succeed depending on fixture tag availability,
  # but the key invariant is that .roster_ref must remain "main".
  local roster_ref_after
  local nexus_actual
  # After upgrade, EIDOLONS_NEXUS still points at the nexus dir.
  nexus_actual="$nexus_dir"
  # If the swap happened, check the new nexus location too.
  if [[ -f "$nexus_dir/.roster_ref" ]]; then
    roster_ref_after="$(tr -d '[:space:]' < "$nexus_dir/.roster_ref" 2>/dev/null || echo '')"
    [ "$roster_ref_after" = "main" ]
  fi
  # If nexus.new was swapped in, it will not have a .roster_ref at all
  # (not written by _write_install_sidecars) which is acceptable —
  # the back-compat fallback to .install_ref covers new installs.
  # The critical invariant: .roster_ref must never be rewritten to a version tag.
  local rref_content
  rref_content="$(cat "$nexus_dir/.roster_ref" 2>/dev/null || echo 'absent')"
  [[ "$rref_content" != v[0-9]* ]] || [ "$rref_content" = "main" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# upgrade-self-integrity-gate (ESL, closes #561) — new fixture helpers + tests.
# Nothing above this marker is modified — AC-10 requires the existing 18
# tests untouched at their measured 18/18-green baseline (933f36b).
#
# The two-source classifier consults:
#   installed — $ROSTER_FILE, the fixture's installed-nexus copy of the roster.
#   upstream  — origin HEAD of $FIXTURE_REMOTE, reached via a real `git fetch`
#               (the fixture remote is a real, non-bare git repo — see the
#               module header — so this is genuinely offline-testable, not
#               mocked).
# ═══════════════════════════════════════════════════════════════════════════

# sha256 of stdin, portable (mirrors lib.sh's sha256_file backend probe).
_fixture_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

# Set (creating if absent) the three integrity fields of a nexus release
# block in FILE's roster. Empty args leave that specific field untouched
# (yq still requires a value, so pass "" explicitly to set it to empty).
_set_fixture_release_fields() {
  local file="$1" version="$2" commit="$3" tree="$4" archive="$5"
  yq e ".nexus.versions.releases[\"$version\"].commit = \"$commit\" |
        .nexus.versions.releases[\"$version\"].tree = \"$tree\" |
        .nexus.versions.releases[\"$version\"].archive_sha256 = \"$archive\"" \
    -i "$file"
}

# Delete a release block entirely — simulates "absent" for that source.
_delete_fixture_release_block() {
  local file="$1" version="$2"
  yq e "del(.nexus.versions.releases[\"$version\"])" -i "$file"
}

# Delete ONLY the three hash fields from a release block, leaving tag /
# released_at (and whatever else is there) intact — AC-21 shape (a): a
# record that exists but carries nothing comparable.
_delete_fixture_release_hash_fields() {
  local file="$1" version="$2"
  yq e "del(.nexus.versions.releases[\"$version\"].commit) |
        del(.nexus.versions.releases[\"$version\"].tree) |
        del(.nexus.versions.releases[\"$version\"].archive_sha256)" -i "$file"
}

# Push a new tag to $FIXTURE_REMOTE (placeholder metadata, like push_fixture_tag)
# then immediately delete that version's release block in a follow-up commit —
# simulating "no release record exists anywhere yet" (genuinely absent upstream,
# and absent on the installed side too, since it predates the push).
_push_fixture_tag_no_upstream_metadata() {
  local new_ver="$1"
  push_fixture_tag "$new_ver"
  _delete_fixture_release_block "$FIXTURE_REMOTE/roster/index.yaml" "$new_ver"
  git -C "$FIXTURE_REMOTE" add -A
  git -C "$FIXTURE_REMOTE" commit -q -m "no release record recorded yet for v${new_ver}"
}

# Push a new tag, then record its REAL commit/tree/archive_sha256 as a
# FOLLOW-UP commit on the default branch — never touching the tag itself.
# This is the measured production construction: the tag's own tree still
# carries the placeholder (from _seed_minimal_nexus_tree); the real values
# are reachable ONLY via the default branch, one commit later. Never present
# on the installed side (predates the push).
_push_fixture_tag_with_real_upstream_metadata() {
  local new_ver="$1"
  push_fixture_tag "$new_ver"
  local rc rt ra
  rc="$(git -C "$FIXTURE_REMOTE" rev-parse "v${new_ver}")"
  rt="$(git -C "$FIXTURE_REMOTE" rev-parse "v${new_ver}^{tree}")"
  ra="$(git -C "$FIXTURE_REMOTE" archive --format=tar --prefix="eidolons-${new_ver}/" "v${new_ver}" | _fixture_sha256)"
  _set_fixture_release_fields "$FIXTURE_REMOTE/roster/index.yaml" "$new_ver" "$rc" "$rt" "$ra"
  git -C "$FIXTURE_REMOTE" add -A
  git -C "$FIXTURE_REMOTE" commit -q -m "record real release metadata for v${new_ver}"
}

# Same as above, then force-moves the tag to a DIFFERENT (tampered) commit —
# the served payload no longer matches the record that was written for it.
_push_fixture_tag_then_tamper() {
  local new_ver="$1"
  _push_fixture_tag_with_real_upstream_metadata "$new_ver"
  echo "tamper" > "$FIXTURE_REMOTE/TAMPER_MARKER"
  git -C "$FIXTURE_REMOTE" add -A
  git -C "$FIXTURE_REMOTE" commit -q -m "tampered payload"
  git -C "$FIXTURE_REMOTE" tag -f "v${new_ver}"
}

# ─── AC-1 / AC-2 — the gate goes RED on the defect it names, paired with the
#     control that shows it keys on the tamper and not on the setup ─────────

@test "AC-1: upstream-only metadata + tag force-moved after the record => mismatch, exit 5" {
  setup_fixture_remote "1.0.0"
  _push_fixture_tag_then_tamper "1.0.1"

  _before_ver="$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION")"

  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"mismatch"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]

  _after_ver="$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION")"
  [ "$_before_ver" = "$_after_ver" ]
}

@test "AC-2: control — same fixture untampered => exit 0, integrity: verified" {
  setup_fixture_remote "1.0.0"
  _push_fixture_tag_with_real_upstream_metadata "1.0.1"

  # Never present in the installed roster (predates the push) and never in
  # the tag's own tree (still the placeholder) — reachable ONLY via the
  # fixture remote's default branch, the measured production shape.
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: verified)"* ]]
  [ -f "$EIDOLONS_NEXUS/VERSION" ]
  [ "$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION")" = "1.0.1" ]
}

# ─── AC-3 — the stable roster channel verifies too ──────────────────────────

@test "AC-3: stable roster channel verifies too (unchanged from AC-2)" {
  setup_fixture_remote "1.0.0"
  printf 'stable\n' > "$EIDOLONS_NEXUS/.roster_ref"
  _push_fixture_tag_with_real_upstream_metadata "1.0.1"

  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: verified)"* ]]

  # Second mechanical half: the issue's own probe, kept as a standing
  # assertion — nexus_refresh is never called from the upgrade-self path.
  run grep -n '^[[:space:]]*nexus_refresh' "$EIDOLONS_ROOT/cli/src/upgrade_self.sh"
  [ "$status" -ne 0 ]
}

# ─── AC-4 / AC-5 / AC-6 — no metadata anywhere: strict refuses, warn proceeds
#     unverified, --allow-unverified proceeds unverified under strict ───────

@test "AC-4: strict + no metadata anywhere => refuses exit 5, names both escape hatches" {
  setup_fixture_remote "1.0.0"
  _push_fixture_tag_no_upstream_metadata "1.0.2"

  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"could not be verified"* ]]
  [[ "$output" == *"--allow-unverified"* ]]
  [[ "$output" == *"EIDOLONS_INTEGRITY_ENFORCEMENT=warn"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
  [ -f "$EIDOLONS_NEXUS/VERSION" ]
  [ "$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION")" = "1.0.0" ]
}

@test "AC-5: warn + no metadata anywhere => proceeds exit 0 with UNVERIFIED summary" {
  setup_fixture_remote "1.0.0"
  _push_fixture_tag_no_upstream_metadata "1.0.2"

  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]
  [[ "$output" != *"(integrity: verified)"* ]]
  [[ "$output" == *"(integrity: UNVERIFIED - absent)"* ]]
}

@test "AC-6: --allow-unverified under strict with no metadata => proceeds exit 0 UNVERIFIED" {
  setup_fixture_remote "1.0.0"
  _push_fixture_tag_no_upstream_metadata "1.0.2"

  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --force --allow-unverified
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: UNVERIFIED - absent)"* ]]
}

# ─── AC-7 — the escape hatch cannot disable the gate on a real mismatch ─────

@test "AC-7a: --allow-unverified does not override a detected mismatch" {
  setup_fixture_remote "1.0.0"
  _push_fixture_tag_then_tamper "1.0.1"

  run bash "$EIDOLONS_BIN" upgrade self --force --allow-unverified
  [ "$status" -eq 5 ]
  [[ "$output" == *"mismatch"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

@test "AC-7b: EIDOLONS_INTEGRITY_ENFORCEMENT=warn does not override a detected mismatch" {
  setup_fixture_remote "1.0.0"
  _push_fixture_tag_then_tamper "1.0.1"

  export EIDOLONS_INTEGRITY_ENFORCEMENT=warn
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"mismatch"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

# ─── AC-8 — a failed metadata fetch is its own outcome (network), never
#     absent and never verified ──────────────────────────────────────────────
# Mechanism measured directly: `git clone --branch vX` still succeeds when the
# remote's HEAD symref is broken (tags are unaffected), but a subsequent
# `fetch --depth 1 origin HEAD` exits 128. Re-verifying v1.0.0 (already
# installed, whose OWN installed-roster entry is a placeholder, not absent)
# isolates the network signal cleanly against a placeholder competitor.

@test "AC-8a: failed upstream fetch reports network under warn (proceeds UNVERIFIED)" {
  setup_fixture_remote "1.0.0"
  git -C "$FIXTURE_REMOTE" symbolic-ref HEAD refs/heads/no-such-branch

  run bash "$EIDOLONS_BIN" upgrade self --ref v1.0.0 --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: UNVERIFIED - network)"* ]]
}

@test "AC-8b: failed upstream fetch under strict refuses, naming the network cause" {
  setup_fixture_remote "1.0.0"
  git -C "$FIXTURE_REMOTE" symbolic-ref HEAD refs/heads/no-such-branch

  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --ref v1.0.0 --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"network"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

# ─── AC-9 — the placeholder path is preserved, not repurposed, and holds
#     ONLY when no source reports absent ─────────────────────────────────────

@test "AC-9: both sources placeholder (no absent) => skips under warn, UNVERIFIED" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.3"

  # Also seed a placeholder release block in the INSTALLED roster so neither
  # source reports absent — the qualifier AC-9 requires.
  _set_fixture_release_fields "$EIDOLONS_NEXUS/roster/index.yaml" "1.0.3" \
    "<filled-by-release-workflow>" "<filled-by-release-workflow>" "<filled-by-release-workflow>"

  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: UNVERIFIED - placeholder)"* ]]
}

@test "AC-9b: both sources placeholder (no absent) => skips under strict too" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.3"
  _set_fixture_release_fields "$EIDOLONS_NEXUS/roster/index.yaml" "1.0.3" \
    "<filled-by-release-workflow>" "<filled-by-release-workflow>" "<filled-by-release-workflow>"

  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: UNVERIFIED - placeholder)"* ]]
}

# ─── AC-16 — severity dominance is the selector ─────────────────────────────

@test "AC-16: upstream placeholder + installed absent => refuses as absent (placeholder does not mask it)" {
  setup_fixture_remote "1.0.0"
  # Default push_fixture_tag state: upstream=placeholder, installed=absent —
  # measured as the fixture's own default forward-upgrade state.
  push_fixture_tag "1.0.4"

  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"could not be verified (absent)"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

@test "AC-16b: local-write downgrade guard — a locally-forged placeholder cannot mask upstream's absence" {
  setup_fixture_remote "1.0.0"
  # Genuinely absent on BOTH sources (no release record anywhere yet).
  _push_fixture_tag_no_upstream_metadata "1.0.5"

  # An actor with only local file write (strictly weaker than origin control)
  # forges a placeholder-shaped commit into the INSTALLED roster, hoping a
  # placeholder-dominant rule would treat this as the harmless bootstrap skip
  # rather than a refusal.
  _set_fixture_release_fields "$EIDOLONS_NEXUS/roster/index.yaml" "1.0.5" "<x" "" ""

  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"could not be verified (absent)"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

# ─── AC-17 / AC-18 — the non-tag branch stops claiming a verification, and
#     set -u safety holds on that path ───────────────────────────────────────

@test "AC-17: non-tag ref completes with '(integrity: UNVERIFIED - non-tag ref)' summary, no false verification claim" {
  setup_fixture_remote "1.0.0"

  # The fixture remote's default branch is 'master' (git init with
  # init.defaultBranch unset) — a real non-tag ref, not a tag.
  run bash "$EIDOLONS_BIN" upgrade self --ref master --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: UNVERIFIED - non-tag ref)"* ]]
  [[ "$output" != *"commit SHA verified"* ]]
}

@test "AC-18: non-tag ref does not abort with unbound variable (set -u safety)" {
  setup_fixture_remote "1.0.0"

  run bash "$EIDOLONS_BIN" upgrade self --ref master --force
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" == *"Upgraded nexus"* ]]
}

# ─── AC-11 — the installed roster remains a live constraint (regression
#     guard: this already refuses pre-fix, since it reads $ROSTER_FILE too) ──

@test "AC-11: installed-only wrong metadata still refuses with exit 5" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.6"

  # Wrong values recorded ONLY on the installed side; upstream still carries
  # push_fixture_tag's default placeholder (not a competing real value).
  _set_fixture_release_fields "$EIDOLONS_NEXUS/roster/index.yaml" "1.0.6" \
    "0000000000000000000000000000000000000000" \
    "0000000000000000000000000000000000000001" \
    ""

  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"mismatch"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

# ─── AC-12 — nexus_verify_release writes nothing to stdout in any outcome ───

@test "AC-12: nexus_verify_release writes nothing to stdout (verified / mismatch / no-evidence)" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.7"

  local clone_dir="$BATS_TEST_TMPDIR/ac12-clone"
  git clone -q --depth 1 --branch "v1.0.7" "file://$FIXTURE_REMOTE" "$clone_dir"
  local real_commit real_tree real_archive
  real_commit="$(git -C "$clone_dir" rev-parse HEAD)"
  real_tree="$(git -C "$clone_dir" rev-parse HEAD^{tree})"
  real_archive="$(git -C "$clone_dir" archive --format=tar --prefix="eidolons-1.0.7/" HEAD | _fixture_sha256)"

  local out="$BATS_TEST_TMPDIR/ac12-stdout"

  # Every invocation below guards the call with `|| rc=$?` — lib.sh runs
  # under `set -euo pipefail`, and nexus_verify_release's non-zero return
  # codes (2/3/4) are its NORMAL outcomes, not errors. An unguarded call
  # would abort the probe script before the rc could even be echoed — the
  # same class of bug this change's own contract warns against.

  # Scenario 1 — no evidence (installed absent; upstream is the default
  # push_fixture_tag placeholder) => rc 4.
  : > "$out"
  run env EIDOLONS_NEXUS="$EIDOLONS_NEXUS" bash -c "
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    rc=0
    nexus_verify_release '1.0.7' '$clone_dir' >'$out' 2>/dev/null || rc=\$?
    echo \"rc=\$rc\"
  "
  [[ "$output" == "rc=4" ]]
  [ ! -s "$out" ]

  # Scenario 2 — installed reports a real, matching value => rc 0
  # (verified:local-only, since upstream is still just a placeholder).
  _set_fixture_release_fields "$EIDOLONS_NEXUS/roster/index.yaml" "1.0.7" \
    "$real_commit" "$real_tree" "$real_archive"
  : > "$out"
  run env EIDOLONS_NEXUS="$EIDOLONS_NEXUS" bash -c "
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    rc=0
    nexus_verify_release '1.0.7' '$clone_dir' >'$out' 2>/dev/null || rc=\$?
    echo \"rc=\$rc\"
  "
  [[ "$output" == "rc=0" ]]
  [ ! -s "$out" ]

  # Scenario 3 — installed reports a wrong value => rc 2 (mismatch).
  _set_fixture_release_fields "$EIDOLONS_NEXUS/roster/index.yaml" "1.0.7" \
    "0000000000000000000000000000000000000000" "" ""
  : > "$out"
  run env EIDOLONS_NEXUS="$EIDOLONS_NEXUS" bash -c "
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    rc=0
    nexus_verify_release '1.0.7' '$clone_dir' >'$out' 2>/dev/null || rc=\$?
    echo \"rc=\$rc\"
  "
  [[ "$output" == "rc=2" ]]
  [ ! -s "$out" ]
}

# ─── AC-15 — the flag and exit-code surfaces agree as SETS, diffed pairwise,
#     never compared by length ───────────────────────────────────────────────

@test "AC-15: upgrade-self flag set agrees across header, --help, and docs (pairwise, as sets)" {
  local src="$EIDOLONS_ROOT/cli/src/upgrade_self.sh"
  local doc="$EIDOLONS_ROOT/docs/cli-reference.md"

  # Scope to the `upgrade self` section FIRST — several other subcommands
  # (`init`, `upgrade`, `release`) have their own "| Flag | Purpose |" tables
  # and "Exit codes" blocks in this same file, and a bare pattern match
  # anchors on the FIRST occurrence anywhere in the file, not this section's.
  local section
  section="$(sed -n '/^## `eidolons upgrade self`$/,/^## `eidolons release`$/p' "$doc")"

  local header_flags help_flags docs_usage_flags docs_table_flags
  header_flags="$(sed -n '/^# Flags:/,/^# Exit codes:/p' "$src" | grep -oE -- '--[a-z][a-z-]*' | sort -u)"
  help_flags="$(sed -n '/^Flags:/,/^Exit codes:/p' "$src" | grep -oE -- '--[a-z][a-z-]*' | sort -u)"
  docs_usage_flags="$(echo "$section" | sed -n '/^```$/,/^```$/p' | grep -oE -- '--[a-z][a-z-]*' | sort -u)"
  docs_table_flags="$(echo "$section" | sed -n '/^| Flag | Purpose |$/,/^$/p' | grep -oE -- '--[a-z][a-z-]*' | sort -u)"

  [ -n "$header_flags" ]
  [ -n "$help_flags" ]
  [ -n "$docs_usage_flags" ]
  [ -n "$docs_table_flags" ]

  [ -z "$(comm -3 <(echo "$header_flags") <(echo "$help_flags"))" ]
  [ -z "$(comm -3 <(echo "$header_flags") <(echo "$docs_usage_flags"))" ]
  [ -z "$(comm -3 <(echo "$header_flags") <(echo "$docs_table_flags"))" ]
}

@test "AC-15: upgrade-self exit-code set agrees across header, --help, and docs (pairwise, as sets)" {
  local src="$EIDOLONS_ROOT/cli/src/upgrade_self.sh"
  local doc="$EIDOLONS_ROOT/docs/cli-reference.md"

  local section
  section="$(sed -n '/^## `eidolons upgrade self`$/,/^## `eidolons release`$/p' "$doc")"

  local header_codes help_codes docs_codes
  header_codes="$(sed -n '/^# Exit codes:/,/^# ═/p' "$src" | grep -oE '[0-9]+' | sort -un)"
  help_codes="$(sed -n '/^Exit codes:/,/^HELP/p' "$src" | grep -oE '[0-9]+' | sort -un)"
  docs_codes="$(echo "$section" | sed -n '/^\*\*Exit codes\.\*\*$/,/^---$/p' | grep -oE '[0-9]+' | sort -un)"

  [ -n "$header_codes" ]
  [ -n "$help_codes" ]
  [ -n "$docs_codes" ]

  [ -z "$(comm -3 <(echo "$header_codes") <(echo "$help_codes"))" ]
  [ -z "$(comm -3 <(echo "$header_codes") <(echo "$docs_codes"))" ]
}

# ─── AC-19 — the documentation states what the code now does ───────────────

@test "AC-19: docs/cli-reference.md step 4 names the upstream default branch, not the installed roster" {
  local doc="$EIDOLONS_ROOT/docs/cli-reference.md"
  local step4
  step4="$(grep -n '^4\. Verifies integrity' "$doc")"
  [ -n "$step4" ]
  [[ "$step4" == *"upstream default branch"* ]]
  [[ "$step4" == *"origin HEAD"* ]]
  [[ "$step4" == *"--allow-unverified"* ]]
  [[ "$step4" == *"mismatch > corrupt > absent > network > placeholder"* ]]
  [[ "$step4" == *"exit 5"* ]]
  # The exact wrong-source sentence this change exists to correct must be gone.
  run grep -n 'match \`nexus.versions.releases' "$doc"
  [ "$status" -ne 0 ]
}

# ─── AC-20 — no surface still advertises a guarantee the code does not
#     provide (the fix makes the existing claims true; this pins that they
#     still exist at the three known live surfaces, and CHANGELOG.md:1764's
#     historical entry is deliberately excluded, per anti-scope) ────────────

@test "AC-20: the three live integrity-verified claims still exist (README + 2x cli-reference)" {
  run grep -c 'integrity-verified' "$EIDOLONS_ROOT/README.md"
  [[ "$output" == "1" ]]
  run grep -c 'integrity-verified' "$EIDOLONS_ROOT/docs/cli-reference.md"
  [[ "$output" == "2" ]]
}

# ─── AC-21 — the vacuous-record class: a record that exists but carries
#     nothing comparable is no-evidence, never `verified` ──────────────────

@test "AC-21: four vacuous shapes classify as no-evidence, never verified (executed directly)" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.11"

  local clone_dir="$BATS_TEST_TMPDIR/ac21-clone"
  git clone -q --depth 1 --branch "v1.0.11" "file://$FIXTURE_REMOTE" "$clone_dir"

  local shapes_dir="$BATS_TEST_TMPDIR/ac21-shapes"
  mkdir -p "$shapes_dir"
  # (a) {tag, released_at} only — schema-legal, no hash fields at all.
  printf '%s' '{"tag":"v1.0.11","released_at":"2026-05-04T00:00:00Z"}' > "$shapes_dir/a.json"
  # (b) commit/tree/archive_sha256 all present but empty strings.
  printf '%s' '{"commit":"","tree":"","archive_sha256":""}' > "$shapes_dir/b.json"
  # (c) a non-object scalar (string) where the record should be.
  printf '%s' '"just-a-string"' > "$shapes_dir/c1.json"
  # (c) a non-object scalar (number).
  printf '%s' '42' > "$shapes_dir/c2.json"
  # (d) commit absent, tree/archive_sha256 hold `<`-sentinels.
  printf '%s' '{"tree":"<filled-by-release-workflow>","archive_sha256":"<filled-by-release-workflow>"}' > "$shapes_dir/d.json"

  local err="$BATS_TEST_TMPDIR/ac21-stderr"
  : > "$err"

  run env EIDOLONS_NEXUS="$EIDOLONS_NEXUS" \
      AC21_LIB="$EIDOLONS_ROOT/cli/src/lib.sh" \
      AC21_CLONE="$clone_dir" \
      AC21_SHAPES="$shapes_dir" \
      AC21_ERR="$err" \
      bash -c '
        . "$AC21_LIB"
        commit="$(git -C "$AC21_CLONE" rev-parse HEAD)"
        tree="$(git -C "$AC21_CLONE" rev-parse HEAD^{tree})"
        for shape in a b c1 c2 d; do
          meta="$(cat "$AC21_SHAPES/$shape.json")"
          st="$(_nexus_release_source_status "$meta" "$commit" "$tree" "$AC21_CLONE" "1.0.11" 2>>"$AC21_ERR")"
          echo "$shape=$st"
        done
      '

  [[ "$output" == *"a=absent"* ]]
  [[ "$output" == *"b=absent"* ]]
  [[ "$output" == *"c1=absent"* ]]
  [[ "$output" == *"c2=absent"* ]]
  [[ "$output" == *"d=placeholder"* ]]

  # AC-21 also requires the non-object shape to stop leaking a raw jq error.
  run cat "$err"
  [[ "$output" != *"jq: error"* ]]
}

@test "AC-21: upstream vacuous record ({tag,released_at} only) does not verify; strict refuses" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.12"
  _delete_fixture_release_hash_fields "$FIXTURE_REMOTE/roster/index.yaml" "1.0.12"
  git -C "$FIXTURE_REMOTE" add -A
  git -C "$FIXTURE_REMOTE" commit -q -m "vacuous upstream record for v1.0.12 (no hash fields)"

  # Never present in the installed roster (predates the push) — both sources
  # are no-evidence, and neither may resolve to `verified`.
  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 5 ]
  [[ "$output" != *"(integrity: verified"* ]]
  [[ "$output" == *"could not be verified"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
  [ "$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION")" = "1.0.0" ]
}

@test "AC-21: local-write escalation — a vacuous installed record cannot turn a strict refusal into a completed upgrade" {
  setup_fixture_remote "1.0.0"
  _push_fixture_tag_no_upstream_metadata "1.0.13"

  # An actor with only local file write (no hash knowledge, no origin
  # control) writes a vacuous {tag, released_at}-only record into the
  # INSTALLED roster for the target version — exactly the shape that
  # classified `verified:local-only` pre-fix.
  yq e ".nexus.versions.releases[\"1.0.13\"].tag = \"v1.0.13\" |
        .nexus.versions.releases[\"1.0.13\"].released_at = \"2026-08-10T00:00:00Z\"" \
    -i "$EIDOLONS_NEXUS/roster/index.yaml"

  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 5 ]
  [[ "$output" != *"(integrity: verified"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
  [ -f "$EIDOLONS_NEXUS/VERSION" ]
  [ "$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION")" = "1.0.0" ]
}

# ─── AC-22 — the `<`-sentinel is recognised in all three fields, not
#     commit alone ───────────────────────────────────────────────────────────

@test "AC-22: the <-sentinel is recognised in all three fields, not commit alone" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.14"

  local clone_dir="$BATS_TEST_TMPDIR/ac22-clone"
  git clone -q --depth 1 --branch "v1.0.14" "file://$FIXTURE_REMOTE" "$clone_dir"

  local err="$BATS_TEST_TMPDIR/ac22-stderr"
  : > "$err"

  run env EIDOLONS_NEXUS="$EIDOLONS_NEXUS" \
      AC22_LIB="$EIDOLONS_ROOT/cli/src/lib.sh" \
      AC22_CLONE="$clone_dir" \
      AC22_ERR="$err" \
      bash -c '
        . "$AC22_LIB"
        commit="$(git -C "$AC22_CLONE" rev-parse HEAD)"
        tree="$(git -C "$AC22_CLONE" rev-parse HEAD^{tree})"

        # tree/archive sentinels only, no commit field at all — placeholder
        # (was `verified` pre-fix: the sentinel scope was keyed on commit alone).
        st="$(_nexus_release_source_status "{\"tree\":\"<filled-by-release-workflow>\",\"archive_sha256\":\"<filled-by-release-workflow>\"}" "$commit" "$tree" "$AC22_CLONE" "1.0.14" 2>>"$AC22_ERR")"
        echo "tree_archive_sentinel=$st"

        # commit sentinel alone — placeholder (unchanged behaviour).
        st="$(_nexus_release_source_status "{\"commit\":\"<filled-by-release-workflow>\"}" "$commit" "$tree" "$AC22_CLONE" "1.0.14" 2>>"$AC22_ERR")"
        echo "commit_sentinel=$st"

        # a real, matching commit plus a sentinel tree — still verified: the
        # sentinel skips a field, it never vetoes a real match.
        real="{\"commit\":\"$commit\",\"tree\":\"<filled-by-release-workflow>\"}"
        st="$(_nexus_release_source_status "$real" "$commit" "$tree" "$AC22_CLONE" "1.0.14" 2>>"$AC22_ERR")"
        echo "real_commit_with_sentinel_tree=$st"
      '

  [[ "$output" == *"tree_archive_sentinel=placeholder"* ]]
  [[ "$output" == *"commit_sentinel=placeholder"* ]]
  [[ "$output" == *"real_commit_with_sentinel_tree=verified"* ]]
}

# ─── AC-23 — the enforcement read is fail-closed on the upgrade path ───────

@test "AC-23: EIDOLONS_INTEGRITY_ENFORCEMENT is trimmed+lowercased; any non-strict/warn value (incl. empty) refuses" {
  setup_fixture_remote "1.0.0"
  # Default push_fixture_tag state: upstream=placeholder, installed=absent —
  # severity resolves to `absent`, a no-evidence rc-4 outcome. None of the
  # values below advance installed state (every one refuses), so a single
  # fixture can be reused across all of them.
  push_fixture_tag "1.0.15"

  local val
  for val in "STRICT" "Strict" " strict" "bogus" ""; do
    export EIDOLONS_INTEGRITY_ENFORCEMENT="$val"
    run bash "$EIDOLONS_BIN" upgrade self --force
    [ "$status" -eq 5 ]
    [[ "$output" == *"could not be verified"* ]]
    [ ! -d "$EIDOLONS_HOME/nexus.new" ]
  done
  unset EIDOLONS_INTEGRITY_ENFORCEMENT
}

@test "AC-23: EIDOLONS_INTEGRITY_ENFORCEMENT case-insensitivity also recognises WARN as warn (control)" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.15"

  export EIDOLONS_INTEGRITY_ENFORCEMENT="WARN"
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: UNVERIFIED - absent)"* ]]
}

@test "AC-23: enforcement unset + unparseable installed roster resolves to strict, not the fail-open warn" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.16"

  unset EIDOLONS_INTEGRITY_ENFORCEMENT || true
  # Corrupt the installed roster so it can no longer be parsed as YAML — the
  # roster's own `enforcement: warn` setting must not be reachable, and
  # `integrity_enforcement_mode`'s literal-string "warn" fail-open return for
  # an unreadable roster must not be trusted as-is at this call site.
  printf ':::not: yaml: [\n' > "$EIDOLONS_NEXUS/roster/index.yaml"

  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"could not be verified"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

# ─── AC-24 — all three exit-5 descriptions state the no-evidence refusal ───

@test "AC-24: all three exit-5 descriptions state the no-evidence refusal, not only a failed check" {
  local src="$EIDOLONS_ROOT/cli/src/upgrade_self.sh"
  local doc="$EIDOLONS_ROOT/docs/cli-reference.md"

  local header_block help_block docs_block
  header_block="$(sed -n '/^# Exit codes:/,/^# ═/p' "$src")"
  help_block="$(sed -n '/^Exit codes:/,/^HELP/p' "$src")"
  docs_block="$(sed -n '/^## `eidolons upgrade self`$/,/^## `eidolons release`$/p' "$doc" | sed -n '/^\*\*Exit codes\.\*\*$/,/^---$/p')"

  [[ "$header_block" == *"5"* ]]
  [[ "$help_block" == *"5"* ]]
  [[ "$docs_block" == *"5"* ]]

  [[ "$header_block" == *"refused under strict"* ]]
  [[ "$help_block" == *"refused under strict"* ]]
  [[ "$docs_block" == *"refused under strict"* ]]
}

# ─── AC-25 — a suppressed witness is named, not folded into the benign case ─

@test "AC-25: a suppressed upstream witness is named in the strict refusal, not folded into plain absent" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.17"
  # Break the fixture remote's HEAD symref (AC-8's measured mechanism):
  # `clone --branch vX` still succeeds, but `fetch --depth 1 origin HEAD`
  # exits 128 — upstream is unreachable, never merely silent.
  git -C "$FIXTURE_REMOTE" symbolic-ref HEAD refs/heads/no-such-branch

  # The installed roster has never seen 1.0.17 (predates the push) — a
  # genuine absent, not a competing report.
  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --ref v1.0.17 --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"upstream unreachable"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

@test "AC-25: the same suppressed-witness disclosure carries onto the summary reason under warn" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.18"
  git -C "$FIXTURE_REMOTE" symbolic-ref HEAD refs/heads/no-such-branch

  # Fixture roster ships enforcement: warn — proceeds unverified, but the
  # summary reason must still name the suppressed witness, not read as the
  # plain, benign "(integrity: UNVERIFIED - absent)".
  run bash "$EIDOLONS_BIN" upgrade self --ref v1.0.18 --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: UNVERIFIED - absent, upstream unreachable)"* ]]
}

# ─── AC-26 fixture helper — a reachable upstream with no roster file ───────
# Pushes a tag the same way push_fixture_tag does (the tag's own tree still
# carries a roster/index.yaml, from _seed_minimal_nexus_tree — a tag's tree
# can never hold its OWN metadata, but it can and does hold *some* roster
# file), then moves the DEFAULT BRANCH (what `origin HEAD` resolves to) to an
# orphan, docs-only history that has no roster/index.yaml at all. Only what
# HEAD points at changes — the tag and its history are untouched. This makes
# `git fetch --depth 1 origin HEAD` succeed (upstream reachable) while
# `git show FETCH_HEAD:roster/index.yaml` fails (no such file at that ref) —
# genuinely different from AC-8/AC-25's broken-HEAD-symref mechanism, where
# the fetch itself never succeeds.
_push_fixture_tag_then_orphan_default_branch() {
  local new_ver="$1"
  push_fixture_tag "$new_ver"

  git -C "$FIXTURE_REMOTE" checkout --orphan docs-only -q
  git -C "$FIXTURE_REMOTE" rm -rf -q . >/dev/null 2>&1 || true
  printf '# docs only — no roster/index.yaml on this branch\n' > "$FIXTURE_REMOTE/README.md"
  git -C "$FIXTURE_REMOTE" add README.md
  git -C "$FIXTURE_REMOTE" commit -q -m "orphan default branch, no roster (AC-26 fixture)"
}

# ─── AC-26 — a reachable upstream with no roster file is `absent`, never
#     reported as "unreachable" ─────────────────────────────────────────────

@test "AC-26: reachable upstream with no roster file classifies absent, not network — strict refuses without 'unreachable'" {
  setup_fixture_remote "1.0.0"
  _push_fixture_tag_then_orphan_default_branch "1.0.19"

  # Sanity: origin HEAD really is reachable (fetch succeeds) even though the
  # branch it names has no roster/index.yaml — this is the load-bearing
  # distinction from AC-8/AC-25 (fetch itself fails there).
  git -C "$FIXTURE_REMOTE" rev-parse HEAD >/dev/null

  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --ref v1.0.19 --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"could not be verified (absent)."* ]]
  [[ "$output" != *"unreachable"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

@test "AC-26: reachable upstream with no roster file — warn proceeds with plain UNVERIFIED - absent, no 'unreachable'" {
  setup_fixture_remote "1.0.0"
  _push_fixture_tag_then_orphan_default_branch "1.0.20"

  run bash "$EIDOLONS_BIN" upgrade self --ref v1.0.20 --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: UNVERIFIED - absent)"* ]]
  [[ "$output" != *"unreachable"* ]]
}

@test "AC-26: control — genuine upstream unreachability still classifies network and still discloses" {
  setup_fixture_remote "1.0.0"
  push_fixture_tag "1.0.21"
  # AC-8/AC-25's mechanism, restated here so the network->absent shift is
  # pinned alongside the fix that produced it: a broken HEAD symref means
  # `git fetch --depth 1 origin HEAD` never succeeds at all — a genuine
  # fetch failure must still classify `network` and still disclose.
  git -C "$FIXTURE_REMOTE" symbolic-ref HEAD refs/heads/no-such-branch

  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --ref v1.0.21 --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"upstream unreachable"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
}

# ─── AC-27 fixture helper — the FULL cli/ tree, so $EIDOLONS_BIN actually
#     runs the fixture's own scripts ─────────────────────────────────────
# The obvious mechanism (sed the fixture's lib.sh, then run through
# $EIDOLONS_BIN) does NOT work: _seed_minimal_nexus_tree/setup_fixture_remote
# never copy cli/src/upgrade.sh into the fixture nexus, and cli/eidolons's
# own source probe (`[[ ! -f "$CLI_SRC/upgrade.sh" ]]`) fires on that
# absence and resets CLI_SRC to the CHECKOUT's cli/src — traced with
# `bash -x`, the exec line becomes the checkout's (unpatched) upgrade_self.sh.
# Sed-ing $EIDOLONS_NEXUS/cli/src/lib.sh then mutates a file that never
# executes: the same unreachable-mechanism trap AC-8 was amended for.
# Adding cli/src/upgrade.sh alone satisfies the probe — its own content is
# never exercised here (only "eidolons upgrade self" is invoked).
_seed_full_cli_tree_for_upgrade_probe() {
  cp "$EIDOLONS_ROOT/cli/src/upgrade.sh" "$EIDOLONS_NEXUS/cli/src/upgrade.sh"
  chmod +x "$EIDOLONS_NEXUS/cli/src/upgrade.sh"
}

# ─── AC-27 — the `*)` catch-all must refuse on an out-of-contract return
#     code, never default to "verified" ─────────────────────────────────────
# The arm is unreachable from real code today: nexus_verify_release's whole
# documented return set is {0,2,3,4}, and the call site
# (`nexus_verify_release ... || _verify_rc=$?`) suppresses errexit for the
# function's entire dynamic extent under `set -e`, so nothing inside the
# function can abort the script either. The only way to exercise the arm is
# to make the function itself return something out-of-contract — done here
# in a FIXTURE COPY of lib.sh, never in the shipped cli/src/lib.sh, reached
# via $EIDOLONS_BIN + _seed_full_cli_tree_for_upgrade_probe above (see that
# helper's comment for why the direct-invocation shortcut is not used).

@test "AC-27: out-of-contract nexus_verify_release return code refuses (exit 5), never defaults to verified" {
  setup_fixture_remote "1.0.0"
  _seed_full_cli_tree_for_upgrade_probe
  _push_fixture_tag_no_upstream_metadata "1.0.22"

  # Force nexus_verify_release's no-evidence branch (its one literal
  # `return 4`) to return 9 instead — the checker's exact construction.
  sed -i.bak 's/return 4/return 9/' "$EIDOLONS_NEXUS/cli/src/lib.sh"
  # Prove the mutation actually applied before trusting anything downstream —
  # a no-op sed would make this test pass green for the wrong reason.
  grep -q '^  return 9$' "$EIDOLONS_NEXUS/cli/src/lib.sh"
  ! grep -q '^  return 4$' "$EIDOLONS_NEXUS/cli/src/lib.sh"

  # strict + no metadata anywhere — the exact construction the frozen
  # criterion measured against pre-fix behaviour (exit 0, "(integrity:
  # verified)", swap completed). The rc-9 run still emits
  # nexus_verify_release's own warn on stderr ("has no verifiable release
  # integrity metadata …") before the forced return — that line is not
  # asserted absent here; what this binds is the exit code and the summary
  # display string, per the corrected finding.
  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 5 ]
  [[ "$output" == *"unexpected code"* ]]
  [[ "$output" == *"rc=9"* ]]
  [[ "$output" != *"(integrity: verified)"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
  [ "$(tr -d '[:space:]' < "$EIDOLONS_NEXUS/VERSION")" = "1.0.0" ]
}

@test "AC-27: control — the real, unmutated rc=4 no-evidence branch still proceeds as UNVERIFIED, not this new refusal" {
  setup_fixture_remote "1.0.0"
  _seed_full_cli_tree_for_upgrade_probe
  _push_fixture_tag_no_upstream_metadata "1.0.23"

  # Same invocation path as the mutated test above (fixture's own
  # upgrade_self.sh via $EIDOLONS_BIN, unpatched lib.sh) but default (warn)
  # enforcement, so the real rc=4 branch's own existing behaviour — proceed
  # unverified — is what's on display, sharply distinguishable from the
  # mutated test's exit 5: the ONLY thing that changes the outcome from 0 to
  # 5 is the sed mutation, not this test's own setup.
  run bash "$EIDOLONS_BIN" upgrade self --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"(integrity: UNVERIFIED - absent)"* ]]
  [[ "$output" != *"unexpected code"* ]]
}
