#!/usr/bin/env bats
#
# backfill_roster_ref.bats — covers nexus_ensure_roster_ref auto-backfill
# behaviour introduced in v1.13.3. Test IDs: BRR-1..BRR-5.
#
# Scenarios:
#   BRR-1: no .roster_ref + no env var → nexus_refresh writes "main"
#   BRR-2: .roster_ref=staging already exists → nexus_refresh does NOT overwrite
#   BRR-3: no .roster_ref + EIDOLONS_ROSTER_REF=feature/foo → writes "feature/foo"
#   BRR-4: upgrade self on a cache without .roster_ref → also writes the default
#   BRR-5: nexus_ensure_roster_ref directly — idempotent on repeated calls

load helpers

# ─── BRR-1: no .roster_ref → nexus_refresh backfills "main" ──────────────

@test "BRR-1: nexus_refresh backfills .roster_ref = main when file absent" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-brr1"
  mkdir -p "$fake_nexus/.git"
  # Pre-v1.11.0 state: only .install_ref, no .roster_ref.
  printf 'v1.10.0\n' > "$fake_nexus/.install_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='https://invalid.example.invalid/repo.git'
    unset EIDOLONS_ROSTER_REF
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    nexus_refresh
    cat '$fake_nexus/.roster_ref'
  " 2>&1
  [ "$status" -eq 0 ]
  # Last stdout line is the cat output.
  echo "$output" | grep -qx "main"
}

# ─── BRR-2: .roster_ref exists → nexus_refresh does NOT overwrite ─────────

@test "BRR-2: nexus_refresh does NOT overwrite existing .roster_ref (idempotent)" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-brr2"
  mkdir -p "$fake_nexus/.git"
  printf 'staging\n' > "$fake_nexus/.roster_ref"
  printf 'v1.11.0\n' > "$fake_nexus/.install_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='https://invalid.example.invalid/repo.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    nexus_refresh
    cat '$fake_nexus/.roster_ref'
  " 2>&1
  [ "$status" -eq 0 ]
  # .roster_ref must still be "staging", not "main".
  echo "$output" | grep -qx "staging"
}

# ─── BRR-3: EIDOLONS_ROSTER_REF env → backfill writes that value ──────────

@test "BRR-3: nexus_refresh backfills .roster_ref = EIDOLONS_ROSTER_REF when set" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-brr3"
  mkdir -p "$fake_nexus/.git"
  # No .roster_ref at all.

  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='https://invalid.example.invalid/repo.git'
    export EIDOLONS_ROSTER_REF='feature/foo'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    nexus_refresh
    cat '$fake_nexus/.roster_ref'
  " 2>&1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "feature/foo"
}

# ─── BRR-4: upgrade self path — nexus_ensure_roster_ref called for .git nexus ──

@test "BRR-4: upgrade self backfills .roster_ref when absent from a .git nexus" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-brr4"
  mkdir -p "$fake_nexus/.git"
  # No .roster_ref; pre-v1.11.0 state.
  # We test nexus_ensure_roster_ref (which upgrade_self.sh also calls) directly.

  run bash -c "
    export EIDOLONS_NEXUS=''
    unset EIDOLONS_ROSTER_REF
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    nexus_ensure_roster_ref
    cat '$fake_nexus/.roster_ref'
  " 2>&1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "main"
}

# ─── BRR-5: nexus_ensure_roster_ref is idempotent ─────────────────────────

@test "BRR-5: nexus_ensure_roster_ref is idempotent — does not overwrite on second call" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-brr5"
  mkdir -p "$fake_nexus"
  printf 'release/2026Q3\n' > "$fake_nexus/.roster_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    unset EIDOLONS_ROSTER_REF
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    # Call twice.
    nexus_ensure_roster_ref
    nexus_ensure_roster_ref
    cat '$fake_nexus/.roster_ref'
  " 2>&1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "release/2026Q3"
}
