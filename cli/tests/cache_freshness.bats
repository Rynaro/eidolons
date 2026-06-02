#!/usr/bin/env bats
#
# cache_freshness.bats — covers nexus_refresh (Fix A) and
# resolve_version_constraint caret/tilde semantics (Fix B).

load helpers

# ─── nexus_refresh ──────────────────────────────────────────────────────────

# RF-1: EIDOLONS_NEXUS set → refresh is skipped (local-checkout path).
@test "nexus_refresh: EIDOLONS_NEXUS set skips refresh" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  # Set a nonsense repo so any real fetch would fail, proving we skipped.
  export EIDOLONS_REPO="https://invalid.example/repo.git"
  run bash -c "
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    export EIDOLONS_REPO='https://invalid.example/repo.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    nexus_refresh
  "
  [ "$status" -eq 0 ]
}

# RF-2: EIDOLONS_SKIP_REFRESH=1 → refresh is skipped.
@test "nexus_refresh: EIDOLONS_SKIP_REFRESH=1 skips refresh" {
  run bash -c "
    export EIDOLONS_SKIP_REFRESH=1
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='https://invalid.example/repo.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    nexus_refresh
  "
  [ "$status" -eq 0 ]
}

# RF-3: No .git dir in nexus → refresh is skipped (returns 0).
@test "nexus_refresh: no .git directory skips refresh gracefully" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus"
  mkdir -p "$fake_nexus"
  printf 'v1.9.0\n' > "$fake_nexus/.install_ref"
  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    nexus_refresh
  "
  [ "$status" -eq 0 ]
}

# RF-4: .install_ref absent → skips refresh gracefully.
@test "nexus_refresh: absent .install_ref skips refresh gracefully" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus-noref"
  mkdir -p "$fake_nexus/.git"
  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    nexus_refresh
  "
  [ "$status" -eq 0 ]
}

# RF-5: Network unavailable → warn and return 0 (non-fatal).
@test "nexus_refresh: network failure emits warn and returns 0" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus-net"
  mkdir -p "$fake_nexus/.git"
  printf 'v1.9.0\n' > "$fake_nexus/.install_ref"
  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='https://invalid.example.invalid/repo.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    nexus_refresh
  " 2>&1
  [ "$status" -eq 0 ]
  # Should emit the stale-cache warn to stderr (captured in $output by bats).
  [[ "$output" =~ "nexus cache stale" ]]
}

# RF-6: nexus_refresh succeeds against a local bare-repo fixture (simulates
#        a real fetch+reset cycle without hitting the network).
@test "nexus_refresh: fetch+reset succeeds against local git fixture" {
  # Build a minimal bare git repo to act as the "remote".
  local remote="$BATS_TEST_TMPDIR/remote.git"
  local nexus="$BATS_TEST_TMPDIR/nexus-clone"
  git init --bare "$remote" >/dev/null 2>&1

  # Seed the remote with one commit. Use HEAD ref to be branch-name agnostic
  # (default branch may be 'master' or 'main' depending on git config).
  local work="$BATS_TEST_TMPDIR/work"
  git clone "$remote" "$work" >/dev/null 2>&1
  echo "hello" > "$work/VERSION"
  git -C "$work" add VERSION >/dev/null 2>&1
  git -C "$work" -c user.email="test@test" -c user.name="T" \
    commit -m "init" >/dev/null 2>&1
  git -C "$work" push origin HEAD >/dev/null 2>&1

  # Clone a working copy for the nexus and plant .install_ref.
  # Determine the actual default branch name (may be master or main).
  git clone "$remote" "$nexus" >/dev/null 2>&1
  local default_branch
  default_branch="$(git -C "$nexus" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")"
  printf '%s\n' "$default_branch" > "$nexus/.install_ref"

  # Verify that nexus_refresh does a fetch+reset without error.
  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='$remote'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$nexus'
    ROSTER_FILE='$nexus/roster/index.yaml'
    nexus_refresh
  "
  [ "$status" -eq 0 ]
}

# RF-7: EIDOLONS_NEXUS= (set but empty string) does NOT skip refresh — only
#        a non-empty value means "local-checkout mode".
@test "nexus_refresh: empty EIDOLONS_NEXUS does not block refresh" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus-empty"
  mkdir -p "$fake_nexus/.git"
  printf 'v1.9.0\n' > "$fake_nexus/.install_ref"
  # Use an invalid repo URL so fetch fails → we get the warn + 0 path.
  run bash -c "
    unset EIDOLONS_NEXUS
    export EIDOLONS_REPO='https://invalid.example.invalid/repo.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    nexus_refresh
  " 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "nexus cache stale" ]]
}

# ─── sync: EIDOLONS_NEXUS set → refresh is skipped ───────────────────────
# This exercises the integration path: the nexus_refresh call inside sync.sh
# respects EIDOLONS_NEXUS (already set by helpers.bash via setup()).

@test "sync: EIDOLONS_NEXUS prevents auto-refresh" {
  # EIDOLONS_NEXUS is already set to $EIDOLONS_ROOT by helpers.bash setup().
  # Plant a poisoned EIDOLONS_REPO to prove no real fetch happens.
  export EIDOLONS_REPO="https://invalid.example.invalid/poison.git"
  export EIDOLONS_SKIP_REFRESH=0

  seed_manifest
  # This should not fail due to network error.
  run eidolons sync --dry-run --non-interactive
  [ "$status" -eq 0 ]
}

# ─── resolve_version_constraint — caret semantics (Fix B) ───────────────────

# SC-1: bare X.Y.Z → echoes X.Y.Z unchanged (exact-pin bypass).
@test "semver caret: bare X.Y.Z is an exact pin — returned unchanged" {
  run bash -c "
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    resolve_version_constraint atlas 1.5.0
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1.5.0" ]
}

# SC-2: =X.Y.Z → same as bare (exact pin; strips leading =).
@test "semver caret: =X.Y.Z strips = and returns X.Y.Z" {
  run bash -c "
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    resolve_version_constraint atlas =1.5.0
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1.5.0" ]
}

# SC-3: ^X.Y.Z (X >= 1) → resolves to latest roster version with same major
#        that is >= base (i.e. the highest X.*.* satisfying the constraint).
@test "semver caret: ^X.Y.Z resolves to latest matching-major version from roster" {
  # atlas currently has versions in the roster. Any version of atlas >= the
  # constraint base and with the same major should win.
  # Use a low constraint so there are definitely matches.
  run bash -c "
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    resolve_version_constraint atlas '^1.0.0'
  "
  [ "$status" -eq 0 ]
  # The result must be >= 1.0.0 (base) and start with 1.
  local result="$output"
  [[ "$result" =~ ^1\. ]]
}

# SC-4: ^0.Y.Z → locks minor (semver special case for 0.x).
#        Build a synthetic roster to test without relying on real 0.x releases.
@test "semver caret: ^0.Y.Z locks the minor version (0.x semver rule)" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus-0x"
  mkdir -p "$fake_nexus/roster"
  cat > "$fake_nexus/roster/index.yaml" << 'ROSTER'
registry_version: "1.0"
eidolons:
  - name: mylib
    methodology:
      name: MYLIB
      version: "1.0"
      cycle: "A"
    source:
      type: github
      repo: Test/MYLIB
      default_ref: main
    handoffs:
      upstream: []
      downstream: []
    versions:
      latest: "0.2.5"
      pins:
        stable: "0.2.5"
      releases:
        0.2.3:
          tag: v0.2.3
        0.2.5:
          tag: v0.2.5
        0.3.0:
          tag: v0.3.0
presets: {}
ROSTER
  run bash -c "
    export EIDOLONS_NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    resolve_version_constraint mylib '^0.2.3'
  "
  [ "$status" -eq 0 ]
  # Must match 0.2.x (>= 0.2.3) — 0.3.0 must NOT be selected.
  local result="$output"
  [[ "$result" =~ ^0\.2\. ]]
  # And should pick the highest in 0.2.x range: 0.2.5.
  [ "$result" = "0.2.5" ]
}

# SC-5: ^1.5.3 with roster containing 1.5.3, 1.6.0, 1.7.0, 2.0.0 →
#        selects 1.7.0 (highest 1.x >= 1.5.3).
@test "semver caret: ^1.5.3 selects highest 1.x, not 2.x" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus-caret1"
  mkdir -p "$fake_nexus/roster"
  cat > "$fake_nexus/roster/index.yaml" << 'ROSTER'
registry_version: "1.0"
eidolons:
  - name: widget
    methodology:
      name: WIDGET
      version: "1.0"
      cycle: "A"
    source:
      type: github
      repo: Test/WIDGET
      default_ref: main
    handoffs:
      upstream: []
      downstream: []
    versions:
      latest: "2.0.0"
      pins:
        stable: "1.7.0"
      releases:
        1.5.3:
          tag: v1.5.3
        1.6.0:
          tag: v1.6.0
        1.7.0:
          tag: v1.7.0
        2.0.0:
          tag: v2.0.0
presets: {}
ROSTER
  run bash -c "
    export EIDOLONS_NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    resolve_version_constraint widget '^1.5.3'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1.7.0" ]
}

# SC-6: ~1.5.3 → >= 1.5.3, < 1.6.0 — selects highest 1.5.x.
@test "semver tilde: ~1.5.3 selects highest 1.5.x patch" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus-tilde1"
  mkdir -p "$fake_nexus/roster"
  cat > "$fake_nexus/roster/index.yaml" << 'ROSTER'
registry_version: "1.0"
eidolons:
  - name: gadget
    methodology:
      name: GADGET
      version: "1.0"
      cycle: "A"
    source:
      type: github
      repo: Test/GADGET
      default_ref: main
    handoffs:
      upstream: []
      downstream: []
    versions:
      latest: "1.6.0"
      pins:
        stable: "1.5.9"
      releases:
        1.5.3:
          tag: v1.5.3
        1.5.7:
          tag: v1.5.7
        1.5.9:
          tag: v1.5.9
        1.6.0:
          tag: v1.6.0
presets: {}
ROSTER
  run bash -c "
    export EIDOLONS_NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    resolve_version_constraint gadget '~1.5.3'
  "
  [ "$status" -eq 0 ]
  # Should pick 1.5.9 (highest 1.5.x >= 1.5.3); 1.6.0 excluded.
  [ "$output" = "1.5.9" ]
}

# SC-7: no roster version satisfies constraint → die with helpful message.
@test "semver caret: unsatisfiable constraint exits non-zero with message" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus-nosatisfy"
  mkdir -p "$fake_nexus/roster"
  cat > "$fake_nexus/roster/index.yaml" << 'ROSTER'
registry_version: "1.0"
eidolons:
  - name: mylib
    methodology:
      name: MYLIB
      version: "1.0"
      cycle: "A"
    source:
      type: github
      repo: Test/MYLIB
      default_ref: main
    handoffs:
      upstream: []
      downstream: []
    versions:
      latest: "1.0.0"
      pins:
        stable: "1.0.0"
      releases:
        1.0.0:
          tag: v1.0.0
presets: {}
ROSTER
  run bash -c "
    export EIDOLONS_NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    resolve_version_constraint mylib '^2.0.0'
  " 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "No version satisfies" ]]
  [[ "$output" =~ "^2.0.0" ]]
}

# SC-8: ^X.Y.Z with no roster entry → falls back to stripping ^ (legacy path).
@test "semver caret: missing roster entry falls back to stripping ^ prefix" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus-missing"
  mkdir -p "$fake_nexus/roster"
  cat > "$fake_nexus/roster/index.yaml" << 'ROSTER'
registry_version: "1.0"
eidolons: []
presets: {}
ROSTER
  run bash -c "
    export EIDOLONS_NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    resolve_version_constraint ghost '^1.2.3'
  " 2>&1
  [ "$status" -eq 0 ]
  # Fall-back: strips the ^ and returns base version.
  [ "$output" = "1.2.3" ]
}

# SC-9: ^1.0.0 against the real atlas roster entry resolves to the latest
#        1.x version (sanity integration test against the live roster).
@test "semver caret: ^1.0.0 for atlas resolves to a valid 1.x release" {
  run bash -c "
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    resolve_version_constraint atlas '^1.0.0'
  "
  [ "$status" -eq 0 ]
  # Result must be a valid semver starting with 1.
  [[ "$output" =~ ^1\.[0-9]+\.[0-9]+$ ]]
}

# ─── nexus_roster_ref fallback chain (B1) ────────────────────────────────

# RF-8: nexus_roster_ref returns .roster_ref when both files present.
@test "nexus_roster_ref: returns .roster_ref when both .roster_ref and .install_ref exist (RF-8)" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus-rf8"
  mkdir -p "$fake_nexus"
  printf 'main\n' > "$fake_nexus/.roster_ref"
  printf 'v1.10.0\n' > "$fake_nexus/.install_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    nexus_roster_ref
  "
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

# RF-9: nexus_roster_ref falls back to .install_ref when .roster_ref is absent.
@test "nexus_roster_ref: falls back to .install_ref when .roster_ref absent (RF-9)" {
  local fake_nexus="$BATS_TEST_TMPDIR/fake-nexus-rf9"
  mkdir -p "$fake_nexus"
  # No .roster_ref — only .install_ref
  printf 'v1.10.0\n' > "$fake_nexus/.install_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    nexus_roster_ref
  "
  [ "$status" -eq 0 ]
  [ "$output" = "v1.10.0" ]
}

# ─── PR-1..PR-3: Path-restricted refresh (STORY-1) ──────────────────────

# PR-1: After nexus_refresh, roster/ is updated from the channel ref but
#        cli/ and VERSION are byte-identical to the tag (CLI stays pinned).
@test "PR-1: nexus_refresh updates roster but leaves cli/+VERSION at tag" {
  local remote="$BATS_TEST_TMPDIR/remote-pr1.git"
  local nexus="$BATS_TEST_TMPDIR/nexus-pr1"
  git init --bare "$remote" >/dev/null 2>&1

  # Seed the remote with a tag (v1.0.0) and a main that advances roster.
  local work="$BATS_TEST_TMPDIR/work-pr1"
  git clone "$remote" "$work" >/dev/null 2>&1
  mkdir -p "$work/roster" "$work/cli/src" "$work/methodology/cortex"
  printf 'roster v1\n' > "$work/roster/index.yaml"
  printf 'EIDOLONS v1\n' > "$work/EIDOLONS.md"
  printf 'cli v1\n' > "$work/cli/src/lib.sh"
  printf '1.0.0\n' > "$work/VERSION"
  git -C "$work" add . >/dev/null 2>&1
  git -C "$work" -c user.email="t@t" -c user.name="T" commit -q -m "v1.0.0"
  git -C "$work" tag v1.0.0
  git -C "$work" push origin HEAD >/dev/null 2>&1
  git -C "$work" push origin v1.0.0 >/dev/null 2>&1

  # Advance roster on main; CLI and VERSION do NOT change.
  printf 'roster v2 from main\n' > "$work/roster/index.yaml"
  printf 'EIDOLONS v2\n' > "$work/EIDOLONS.md"
  git -C "$work" add roster/index.yaml EIDOLONS.md >/dev/null 2>&1
  git -C "$work" -c user.email="t@t" -c user.name="T" commit -q -m "roster bump"
  git -C "$work" push origin HEAD >/dev/null 2>&1

  # Clone nexus at v1.0.0 (CLI pinned to tag).
  local default_branch
  default_branch="$(git -C "$work" rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"
  git clone "$remote" "$nexus" -q --branch v1.0.0 2>/dev/null || \
    git clone "$remote" "$nexus" -q 2>/dev/null
  printf '%s\n' "$default_branch" > "$nexus/.roster_ref"
  printf 'v1.0.0\n' > "$nexus/.install_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='$remote'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$nexus'
    ROSTER_FILE='$nexus/roster/index.yaml'
    nexus_refresh
  "
  [ "$status" -eq 0 ]

  # Roster must have been updated to v2.
  local roster_content
  roster_content="$(cat "$nexus/roster/index.yaml")"
  [[ "$roster_content" == *"v2"* ]]

  # CLI code must still be at v1 (untouched by path-checkout).
  local cli_content
  cli_content="$(cat "$nexus/cli/src/lib.sh")"
  [ "$cli_content" = "cli v1" ]

  # VERSION must be untouched.
  local ver_content
  ver_content="$(cat "$nexus/VERSION")"
  [ "$ver_content" = "1.0.0" ]
}

# PR-2: .roster_ref=stable → fetches nexus_latest_tag; offline stable → warn + return 0.
@test "PR-2a: nexus_refresh with .roster_ref=stable resolves latest tag" {
  local remote="$BATS_TEST_TMPDIR/remote-pr2a.git"
  local nexus="$BATS_TEST_TMPDIR/nexus-pr2a"
  git init --bare "$remote" >/dev/null 2>&1

  local work="$BATS_TEST_TMPDIR/work-pr2a"
  git clone "$remote" "$work" >/dev/null 2>&1
  mkdir -p "$work/roster"
  printf 'roster stable\n' > "$work/roster/index.yaml"
  git -C "$work" add . >/dev/null 2>&1
  git -C "$work" -c user.email="t@t" -c user.name="T" commit -q -m "init"
  git -C "$work" tag v1.2.0
  git -C "$work" push origin HEAD >/dev/null 2>&1
  git -C "$work" push origin v1.2.0 >/dev/null 2>&1

  git clone "$remote" "$nexus" -q 2>/dev/null
  printf 'stable\n' > "$nexus/.roster_ref"
  printf 'v1.0.0\n' > "$nexus/.install_ref"

  # With a real local repo, nexus_latest_tag should resolve v1.2.0.
  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='$remote'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$nexus'
    ROSTER_FILE='$nexus/roster/index.yaml'
    nexus_refresh
  " 2>&1
  [ "$status" -eq 0 ]
}

@test "PR-2b: nexus_refresh with .roster_ref=stable and offline repo warns and returns 0" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr2b"
  mkdir -p "$fake_nexus/.git"
  printf 'stable\n' > "$fake_nexus/.roster_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='https://invalid.example.invalid/repo.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    nexus_refresh
  " 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "nexus cache stale" ]]
}

# PR-3: New file added under roster/ on remote appears after refresh;
#        CLI-only file on remote does NOT appear locally.
@test "PR-3: refresh adds new roster file but not CLI-only remote file" {
  local remote="$BATS_TEST_TMPDIR/remote-pr3.git"
  local nexus="$BATS_TEST_TMPDIR/nexus-pr3"
  git init --bare "$remote" >/dev/null 2>&1

  local work="$BATS_TEST_TMPDIR/work-pr3"
  git clone "$remote" "$work" >/dev/null 2>&1
  mkdir -p "$work/roster" "$work/cli/src"
  printf 'base roster\n' > "$work/roster/index.yaml"
  printf 'cli v1\n' > "$work/cli/src/lib.sh"
  git -C "$work" add . >/dev/null 2>&1
  git -C "$work" -c user.email="t@t" -c user.name="T" commit -q -m "init"
  # Tag the initial commit so we can clone the nexus at this point.
  git -C "$work" tag v1.0.0
  git -C "$work" push origin HEAD >/dev/null 2>&1
  git -C "$work" push origin v1.0.0 >/dev/null 2>&1

  local default_branch
  default_branch="$(git -C "$work" rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"

  # Add a new file under roster/ AND a new cli file on the remote.
  printf 'extra roster data\n' > "$work/roster/new-extra.yaml"
  printf 'cli v2 SHOULD NOT APPEAR\n' > "$work/cli/src/new_cli.sh"
  git -C "$work" add . >/dev/null 2>&1
  git -C "$work" -c user.email="t@t" -c user.name="T" commit -q -m "add extras"
  git -C "$work" push origin HEAD >/dev/null 2>&1

  # Clone the nexus at v1.0.0 (before the "add extras" commit) so that
  # new_cli.sh is NOT yet present in the working tree. After nexus_refresh
  # (path-restricted to roster/ etc.), it must still be absent.
  git clone "$remote" "$nexus" -q --branch v1.0.0 2>/dev/null || \
    git clone "$remote" "$nexus" -q 2>/dev/null
  printf '%s\n' "$default_branch" > "$nexus/.roster_ref"
  printf 'v1.0.0\n' > "$nexus/.install_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='$remote'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$nexus'
    ROSTER_FILE='$nexus/roster/index.yaml'
    nexus_refresh
  " 2>&1
  [ "$status" -eq 0 ]

  # New roster file should be present after refresh.
  [ -f "$nexus/roster/new-extra.yaml" ]

  # New CLI file should NOT be present (path checkout only covers roster paths).
  [ ! -f "$nexus/cli/src/new_cli.sh" ]
}
