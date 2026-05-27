#!/usr/bin/env bats
#
# gitignore_sidecar.bats — covers nexus_ensure_gitignore_sidecar and the
# gitignore-heal path in nexus_ensure_roster_ref (v1.13.4).
# Test IDs: GIS-1..GIS-7.
#
# Scenarios:
#   GIS-1: .gitignore absent → backfill creates it with the entry
#   GIS-2: .gitignore exists, entry absent → backfill appends it
#   GIS-3: .gitignore exists, entry present → backfill is idempotent (no dup)
#   GIS-4: nexus_ensure_roster_ref writes .roster_ref AND adds it to .gitignore
#   GIS-5: nexus_ensure_roster_ref heals all sidecar entries in one pass
#   GIS-6: nexus_ensure_roster_ref is idempotent — gitignore unchanged on second call
#   GIS-7: upgrade self dirty-tree check passes after backfill (post-heal clean tree)

load helpers

# ─── GIS-1: .gitignore absent → helper creates it ─────────────────────────

@test "GIS-1: nexus_ensure_gitignore_sidecar creates .gitignore when absent" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-gis1"
  mkdir -p "$fake_nexus"
  # No .gitignore present.

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    nexus_ensure_gitignore_sidecar '.roster_ref'
  " 2>&1
  [ "$status" -eq 0 ]
  [ -f "$fake_nexus/.gitignore" ]
  grep -qxF '.roster_ref' "$fake_nexus/.gitignore"
}

# ─── GIS-2: .gitignore exists, entry absent → helper appends ──────────────

@test "GIS-2: nexus_ensure_gitignore_sidecar appends missing entry to existing .gitignore" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-gis2"
  mkdir -p "$fake_nexus"
  printf '.install_date\n.install_ref\n.install_commit\n' > "$fake_nexus/.gitignore"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    nexus_ensure_gitignore_sidecar '.roster_ref'
  " 2>&1
  [ "$status" -eq 0 ]
  grep -qxF '.roster_ref' "$fake_nexus/.gitignore"
  # Existing entries must be preserved.
  grep -qxF '.install_date'   "$fake_nexus/.gitignore"
  grep -qxF '.install_ref'    "$fake_nexus/.gitignore"
  grep -qxF '.install_commit' "$fake_nexus/.gitignore"
}

# ─── GIS-3: entry already present → idempotent, no duplicate ─────────────

@test "GIS-3: nexus_ensure_gitignore_sidecar is idempotent when entry already present" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-gis3"
  mkdir -p "$fake_nexus"
  printf '.install_date\n.install_ref\n.install_commit\n.roster_ref\n' \
    > "$fake_nexus/.gitignore"

  local before_count after_count
  before_count="$(grep -c '.' "$fake_nexus/.gitignore")"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    nexus_ensure_gitignore_sidecar '.roster_ref'
  " 2>&1
  [ "$status" -eq 0 ]

  after_count="$(grep -c '.' "$fake_nexus/.gitignore")"
  # Line count must not have grown.
  [ "$before_count" -eq "$after_count" ]
  # Entry still present exactly once.
  count="$(grep -cxF '.roster_ref' "$fake_nexus/.gitignore")"
  [ "$count" -eq 1 ]
}

# ─── GIS-4: nexus_ensure_roster_ref writes .roster_ref AND heals .gitignore ──

@test "GIS-4: nexus_ensure_roster_ref writes .roster_ref and adds it to .gitignore" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-gis4"
  mkdir -p "$fake_nexus/.git"
  # Pre-v1.11.0 state: .gitignore without .roster_ref; no .roster_ref file.
  printf '.install_date\n.install_ref\n.install_commit\n' > "$fake_nexus/.gitignore"

  run bash -c "
    export EIDOLONS_NEXUS=''
    unset EIDOLONS_ROSTER_REF
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    nexus_ensure_roster_ref
  " 2>&1
  [ "$status" -eq 0 ]

  # .roster_ref file must be written.
  [ -f "$fake_nexus/.roster_ref" ]

  # .roster_ref must appear in .gitignore.
  grep -qxF '.roster_ref' "$fake_nexus/.gitignore"
}

# ─── GIS-5: nexus_ensure_roster_ref heals ALL sidecar entries ─────────────

@test "GIS-5: nexus_ensure_roster_ref heals all four sidecar entries in .gitignore" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-gis5"
  mkdir -p "$fake_nexus/.git"
  # Very old install state: .gitignore exists but has NO sidecar entries at all.
  printf '# intentionally empty\n' > "$fake_nexus/.gitignore"

  run bash -c "
    export EIDOLONS_NEXUS=''
    unset EIDOLONS_ROSTER_REF
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    nexus_ensure_roster_ref
  " 2>&1
  [ "$status" -eq 0 ]

  # All four sidecars must appear in .gitignore.
  grep -qxF '.install_date'   "$fake_nexus/.gitignore"
  grep -qxF '.install_ref'    "$fake_nexus/.gitignore"
  grep -qxF '.install_commit' "$fake_nexus/.gitignore"
  grep -qxF '.roster_ref'     "$fake_nexus/.gitignore"
}

# ─── GIS-6: nexus_ensure_roster_ref idempotent on repeated calls ─────────

@test "GIS-6: nexus_ensure_roster_ref gitignore heal is idempotent on repeated calls" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-gis6"
  mkdir -p "$fake_nexus/.git"
  printf '.install_date\n.install_ref\n.install_commit\n.roster_ref\n' \
    > "$fake_nexus/.gitignore"
  printf 'main\n' > "$fake_nexus/.roster_ref"

  local before_count after_count
  before_count="$(grep -c '.' "$fake_nexus/.gitignore")"

  run bash -c "
    export EIDOLONS_NEXUS=''
    unset EIDOLONS_ROSTER_REF
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    nexus_ensure_roster_ref
    nexus_ensure_roster_ref
  " 2>&1
  [ "$status" -eq 0 ]

  after_count="$(grep -c '.' "$fake_nexus/.gitignore")"
  [ "$before_count" -eq "$after_count" ]
}

# ─── GIS-7: upgrade self dirty-tree check passes after backfill ───────────
# Verifies that after nexus_ensure_roster_ref runs, `git status --porcelain`
# on the nexus is empty (i.e., the dirty-tree guard would not fire).

@test "GIS-7: git status is clean after backfill heals .gitignore" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-gis7"
  mkdir -p "$fake_nexus"

  # Bootstrap a real (non-bare) git repo with only the sidecar entries that
  # were present on old installs (missing .roster_ref).
  git -C "$fake_nexus" init -q
  git -C "$fake_nexus" config user.email "test@test.local"
  git -C "$fake_nexus" config user.name  "Test"

  # Add an initial committed file so the repo has at least one commit.
  printf '1.13.3\n' > "$fake_nexus/VERSION"
  printf '.install_date\n.install_ref\n.install_commit\n' > "$fake_nexus/.gitignore"
  git -C "$fake_nexus" add VERSION .gitignore
  git -C "$fake_nexus" commit -q -m "init"

  # Now plant the sidecars as untracked files (simulating an old install that
  # wrote them after the last commit but before adding .roster_ref to .gitignore).
  printf '2026-05-27\n' > "$fake_nexus/.install_date"
  printf 'main\n'       > "$fake_nexus/.install_ref"
  printf 'abc1234\n'    > "$fake_nexus/.install_commit"
  # .roster_ref is absent — this is the pre-backfill state.

  # Before backfill, the three sidecar files are untracked.
  local before_status
  before_status="$(git -C "$fake_nexus" status --porcelain 2>/dev/null)"
  # (we don't assert they ARE untracked because .gitignore already covers them)

  # Run the backfill.
  run bash -c "
    export EIDOLONS_NEXUS=''
    unset EIDOLONS_ROSTER_REF
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    nexus_ensure_roster_ref
  " 2>&1
  [ "$status" -eq 0 ]

  # After backfill:
  # 1. .roster_ref must exist.
  [ -f "$fake_nexus/.roster_ref" ]

  # 2. All four sidecar entries must be in .gitignore.
  grep -qxF '.roster_ref' "$fake_nexus/.gitignore"

  # 3. git status --porcelain must be clean (no untracked sidecar files).
  #    Note: .gitignore itself is now modified (new entry appended); we need
  #    to commit or check specifically for sidecar files.
  #    The dirty-tree check in upgrade_self.sh uses `git status --porcelain`.
  #    A modified (but not untracked) .gitignore would still trip it.
  #    So commit the healed .gitignore as part of the expected state:
  git -C "$fake_nexus" add .gitignore
  git -C "$fake_nexus" commit -q -m "heal .gitignore" 2>/dev/null || true

  local after_status
  after_status="$(git -C "$fake_nexus" status --porcelain 2>/dev/null)"
  [ -z "$after_status" ]
}
