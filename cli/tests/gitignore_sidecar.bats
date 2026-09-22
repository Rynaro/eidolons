#!/usr/bin/env bats
# Git-local sidecar exclusions: preserve source files and never require a
# commit of installer mutations to make the dirty guard pass.
load helpers

_git_fixture() {
  FAKE_NEXUS="$BATS_TEST_TMPDIR/nexus-gis"
  mkdir -p "$FAKE_NEXUS"
  git -C "$FAKE_NEXUS" init -q
  git -C "$FAKE_NEXUS" config user.email fixture@example.invalid
  git -C "$FAKE_NEXUS" config user.name Fixture
}

_sidecar_helper() {
  EIDOLONS_NEXUS="$FAKE_NEXUS" bash -c '. "$1/cli/src/lib.sh"; nexus_ensure_gitignore_sidecar .roster_ref' _ "$EIDOLONS_ROOT"
}

_backfill_helper() {
  EIDOLONS_NEXUS="$FAKE_NEXUS" bash -c '. "$1/cli/src/lib.sh"; nexus_ensure_roster_ref' _ "$EIDOLONS_ROOT"
}

@test "GIS-1: missing gitignore stays absent while root sidecar becomes ignored" {
  _git_fixture
  run _sidecar_helper
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_NEXUS/.gitignore" ]
  grep -qxF '/.roster_ref' "$FAKE_NEXUS/.git/info/exclude"
  git -C "$FAKE_NEXUS" check-ignore -q .roster_ref
}

@test "GIS-2: existing gitignore and existing local exclusions retain exact bytes" {
  _git_fixture
  printf '# user bytes without newline' > "$FAKE_NEXUS/.gitignore"
  printf 'my-local-file' > "$FAKE_NEXUS/.git/info/exclude"
  cp "$FAKE_NEXUS/.gitignore" "$BATS_TEST_TMPDIR/before"
  run _sidecar_helper
  [ "$status" -eq 0 ]
  cmp "$FAKE_NEXUS/.gitignore" "$BATS_TEST_TMPDIR/before"
  grep -qxF 'my-local-file' "$FAKE_NEXUS/.git/info/exclude"
  git -C "$FAKE_NEXUS" check-ignore -q my-local-file
  git -C "$FAKE_NEXUS" check-ignore -q .roster_ref
}

@test "GIS-3: local exclusions are idempotent on repeated calls" {
  _git_fixture
  run _sidecar_helper
  [ "$status" -eq 0 ]
  cp "$FAKE_NEXUS/.git/info/exclude" "$BATS_TEST_TMPDIR/before"
  run _sidecar_helper
  [ "$status" -eq 0 ]
  cmp "$FAKE_NEXUS/.git/info/exclude" "$BATS_TEST_TMPDIR/before"
}

@test "GIS-4: roster backfill creates its default without editing tracked gitignore" {
  _git_fixture
  printf '.install_date\n.install_ref\n.install_commit\n' > "$FAKE_NEXUS/.gitignore"
  git -C "$FAKE_NEXUS" add .gitignore
  git -C "$FAKE_NEXUS" commit -qm base
  run _backfill_helper
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_NEXUS/.roster_ref")" = main ]
  [ -z "$(git -C "$FAKE_NEXUS" status --porcelain)" ]
}

@test "GIS-5: all four root sidecars are ignored but nested same-named files are not" {
  _git_fixture
  run _backfill_helper
  [ "$status" -eq 0 ]
  local sidecar
  for sidecar in .install_date .install_ref .install_commit .roster_ref; do
    git -C "$FAKE_NEXUS" check-ignore -q "$sidecar"
    run git -C "$FAKE_NEXUS" check-ignore -q "nested/$sidecar"
    [ "$status" -eq 1 ]
  done
}

@test "GIS-6: repeated backfill preserves the exact configured roster channel" {
  _git_fixture
  printf 'feature/custom\n\n' > "$FAKE_NEXUS/.roster_ref"
  cp "$FAKE_NEXUS/.roster_ref" "$BATS_TEST_TMPDIR/channel"
  run _backfill_helper
  [ "$status" -eq 0 ]
  cp "$FAKE_NEXUS/.git/info/exclude" "$BATS_TEST_TMPDIR/exclude"
  run _backfill_helper
  [ "$status" -eq 0 ]
  cmp "$FAKE_NEXUS/.roster_ref" "$BATS_TEST_TMPDIR/channel"
  cmp "$FAKE_NEXUS/.git/info/exclude" "$BATS_TEST_TMPDIR/exclude"
}

@test "GIS-7: legacy backfill leaves tracked tree clean without committing any repair" {
  _git_fixture
  printf '1.10.0\n' > "$FAKE_NEXUS/VERSION"
  printf '.install_date\n.install_ref\n.install_commit\n' > "$FAKE_NEXUS/.gitignore"
  git -C "$FAKE_NEXUS" add -A
  git -C "$FAKE_NEXUS" commit -qm base
  local before
  before="$(git -C "$FAKE_NEXUS" rev-parse HEAD)"
  printf 'date\n' > "$FAKE_NEXUS/.install_date"
  printf 'v1.10.0\n' > "$FAKE_NEXUS/.install_ref"
  printf 'commit\n' > "$FAKE_NEXUS/.install_commit"
  run _backfill_helper
  [ "$status" -eq 0 ]
  [ -f "$FAKE_NEXUS/.roster_ref" ]
  [ "$(git -C "$FAKE_NEXUS" rev-parse HEAD)" = "$before" ]
  [ -z "$(git -C "$FAKE_NEXUS" status --porcelain)" ]
}

@test "GIS-8: helper resolves info exclude for linked worktrees" {
  _git_fixture
  printf base > "$FAKE_NEXUS/file"
  git -C "$FAKE_NEXUS" add -A
  git -C "$FAKE_NEXUS" commit -qm base
  git -C "$FAKE_NEXUS" worktree add -q --detach "$BATS_TEST_TMPDIR/linked" HEAD
  FAKE_NEXUS="$BATS_TEST_TMPDIR/linked"
  run _sidecar_helper
  [ "$status" -eq 0 ]
  git -C "$FAKE_NEXUS" check-ignore -q .roster_ref
  [ ! -e "$FAKE_NEXUS/.gitignore" ]
}

@test "GIS-9: non-git directories never acquire a gitignore from sidecar maintenance" {
  FAKE_NEXUS="$BATS_TEST_TMPDIR/not-a-repo"
  mkdir -p "$FAKE_NEXUS"
  run _backfill_helper
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_NEXUS/.roster_ref")" = main ]
  [ ! -e "$FAKE_NEXUS/.gitignore" ]
}
