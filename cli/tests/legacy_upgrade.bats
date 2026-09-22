#!/usr/bin/env bats
# R01–R05 anchors. No --force, --allow-unverified, or advisory policy.
load helpers
load legacy_upgrade_helpers

@test "V4-02 T01: repeated checks leave affected v1.10 v1.40 v1.41 snapshots byte-identical" {
  local version attempt before exclude_before
  for version in 1.10.0 1.40.0 1.41.0; do
    rm -rf "$EIDOLONS_HOME/nexus"
    legacy_install "$version"
    before="$(legacy_snapshot "$EIDOLONS_NEXUS")"
    exclude_before="$(cat "$EIDOLONS_NEXUS/.git/info/exclude")"
    for attempt in 1 2; do
      run legacy_upgrade --check --ref v9.0.0
      [ "$status" -eq 0 ]
      [[ "$output" == *"upgrade available"* ]]
      [ "$(legacy_snapshot "$EIDOLONS_NEXUS")" = "$before" ]
      [ "$(cat "$EIDOLONS_NEXUS/.git/info/exclude")" = "$exclude_before" ]
      [ -z "$(git -C "$EIDOLONS_NEXUS" diff HEAD --name-only)" ]
      [ ! -d "$EIDOLONS_HOME/nexus.new" ]
    done
  done
}

@test "V4-02 T02: genuine gitignore and source edits refuse before staging and preserve exact bytes" {
  local file
  for file in .gitignore cli/src/upgrade.sh; do
    rm -rf "$EIDOLONS_HOME/nexus"
    legacy_install 1.41.0
    printf '\n# personal edit without final newline' >> "$EIDOLONS_NEXUS/$file"
    legacy_settings
    run legacy_upgrade --ref v9.0.0 --non-interactive
    [ "$status" -eq 1 ]
    [[ "$output" == *"local changes"* ]]
    [ ! -d "$EIDOLONS_HOME/nexus.new" ]
    legacy_assert_preserved
  done
}

@test "V4-02 T02: pre-existing installer-shaped gitignore changes are preserved, never guessed disposable" {
  legacy_install 1.41.0
  printf '.roster_ref\n' >> "$EIDOLONS_NEXUS/.gitignore"
  legacy_settings
  run legacy_upgrade --ref v9.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"local changes"* ]]
  legacy_assert_preserved
}

@test "V4-02 T03: valid verified target upgrades six historical snapshots without bypass" {
  local version
  legacy_target
  for version in 1.10.0 1.40.0 1.41.0 1.41.1 2.20.0 3.3.1; do
    rm -rf "$EIDOLONS_HOME/nexus" "$EIDOLONS_HOME/nexus.prev"
    legacy_install "$version"
    legacy_settings
    run legacy_upgrade --ref v9.0.0 --non-interactive
    [ "$status" -eq 0 ]
    [[ "$output" == *"integrity: verified"* ]]
    [ "$(cat "$EIDOLONS_NEXUS/VERSION")" = 9.0.0 ]
    [ "$(legacy_snapshot "$EIDOLONS_HOME/nexus.prev")" = "$OLD_TREE" ]
    [ -z "$(git -C "$EIDOLONS_NEXUS" status --porcelain)" ]
    [ "$(legacy_snapshot "$HOME")" = "$OLD_SETTINGS" ]
    [ "$(legacy_snapshot "$TEST_PROJECT")" = "$OLD_CONSUMER" ]
    if [[ "$version" == 1.10.0 ]]; then
      [ "$(cat "$EIDOLONS_NEXUS/.roster_ref")" = main ]
    else
      cmp "$EIDOLONS_NEXUS/.roster_ref" "$EIDOLONS_HOME/nexus.prev/.roster_ref"
    fi
  done
}

@test "V4-02 T04: clone download failure and interruption preserve old tree binary and settings" {
  local fault
  for fault in download-failure download-interrupt; do
    legacy_install 1.41.0
    legacy_settings
    legacy_clone_fault "$fault"
    run legacy_upgrade --ref v9.0.0
    [ "$status" -ne 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/fault-marker")" = "$fault" ]
    legacy_assert_preserved
    rm -rf "$EIDOLONS_HOME/nexus"
  done
}

@test "V4-02 T04: clone checkout failure and interruption preserve old tree binary and settings" {
  legacy_target
  local fault
  for fault in checkout-failure checkout-interrupt; do
    legacy_install 1.41.0
    legacy_settings
    legacy_clone_fault "$fault"
    run legacy_upgrade --ref v9.0.0
    [ "$status" -ne 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/fault-marker")" = "$fault" ]
    legacy_assert_preserved
    rm -rf "$EIDOLONS_HOME/nexus"
  done
}

@test "V4-02 T04: integrity mismatch reaches integrity gate and preserves old tree binary and settings" {
  legacy_install 1.41.0
  legacy_target
  printf 'tamper\n' > "$BATS_TEST_TMPDIR/target/tamper"
  git -C "$BATS_TEST_TMPDIR/target" add -A
  git -C "$BATS_TEST_TMPDIR/target" commit -qm tamper
  git -C "$BATS_TEST_TMPDIR/target" tag -f v9.0.0
  legacy_settings
  run legacy_upgrade --ref v9.0.0
  [ "$status" -eq 5 ]
  [[ "$output" == *"mismatch"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
  legacy_assert_preserved
}

@test "V4-02 T04: verified replacement smoke failure preserves old tree binary and settings" {
  legacy_install 1.41.0
  legacy_target smoke-failure
  legacy_settings
  run legacy_upgrade --ref v9.0.0
  [ "$status" -eq 6 ]
  [[ "$output" == *"Smoke test failed"* ]]
  [ -f "$BATS_TEST_TMPDIR/smoke-marker" ]
  [ -d "$EIDOLONS_HOME/nexus.new" ]
  legacy_assert_preserved
}

@test "V4-02 T04: interruption during verified replacement smoke preserves old tree binary and settings" {
  legacy_install 1.41.0
  legacy_target smoke-interrupt
  legacy_settings
  run legacy_upgrade --ref v9.0.0
  [ "$status" -ne 0 ]
  [ -f "$BATS_TEST_TMPDIR/smoke-marker" ]
  legacy_assert_preserved
}

@test "V4-02 T05: repeated completed upgrade and check preserve dirty consumer and host settings" {
  legacy_install 1.41.0
  legacy_target
  legacy_settings
  run legacy_upgrade --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"integrity: verified"* ]]
  local first prev
  first="$(legacy_snapshot "$EIDOLONS_NEXUS")"
  prev="$(legacy_snapshot "$EIDOLONS_HOME/nexus.prev")"
  run legacy_upgrade --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"No upgrade needed"* ]]
  run legacy_upgrade --check --ref v9.0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"up-to-date"* ]]
  [ "$(legacy_snapshot "$EIDOLONS_NEXUS")" = "$first" ]
  [ "$(legacy_snapshot "$EIDOLONS_HOME/nexus.prev")" = "$prev" ]
  [ "$(legacy_snapshot "$HOME")" = "$OLD_SETTINGS" ]
  [ "$(legacy_snapshot "$TEST_PROJECT")" = "$OLD_CONSUMER" ]
}

@test "V4-02 T02: linked-worktree edits are guarded and clean linked-worktree swaps are refused" {
  legacy_install 1.41.1
  local original="$EIDOLONS_NEXUS"
  git -C "$original" worktree add -q --detach "$EIDOLONS_HOME/linked" HEAD
  export EIDOLONS_NEXUS="$EIDOLONS_HOME/linked"
  printf '\n# my source edit\n' >> "$EIDOLONS_NEXUS/cli/src/upgrade.sh"
  local before
  before="$(legacy_snapshot "$EIDOLONS_NEXUS")"
  run legacy_upgrade --ref v9.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"local changes"* ]]
  [ "$(legacy_snapshot "$EIDOLONS_NEXUS")" = "$before" ]
  git -C "$EIDOLONS_NEXUS" checkout -- cli/src/upgrade.sh
  run legacy_upgrade --check --ref v9.0.0
  [ "$status" -eq 0 ]
  run legacy_upgrade --ref v9.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"linked worktree"* ]]
  [ ! -d "$EIDOLONS_HOME/nexus.new" ]
  [ -f "$EIDOLONS_NEXUS/cli/eidolons" ]
}

@test "V4-02 T02: tracked sidecar edits are not mistaken for untracked installation metadata" {
  legacy_install 1.41.1
  git -C "$EIDOLONS_NEXUS" add -f .roster_ref
  git -C "$EIDOLONS_NEXUS" commit -qm 'user tracks channel'
  printf 'user/new-channel\n' > "$EIDOLONS_NEXUS/.roster_ref"
  legacy_settings
  run legacy_upgrade --ref v9.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"local changes"* ]]
  legacy_assert_preserved
}

@test "V4-02 T04: interruption during upstream integrity metadata fetch retains prior installation" {
  legacy_install 1.41.0
  legacy_target
  legacy_settings
  export LEGACY_REAL_GIT="$(command -v git)"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/git" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == -C && "$2" == "$EIDOLONS_HOME/nexus.new" && "$3" == fetch ]]; then
  printf integrity-fetch > "$BATS_TEST_TMPDIR/fault-marker"
  kill -TERM "$LEGACY_UPDATER_PID"
  exit 143
fi
exec "$LEGACY_REAL_GIT" "$@"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  run legacy_upgrade --ref v9.0.0
  [ "$status" -ne 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/fault-marker")" = integrity-fetch ]
  legacy_assert_preserved
}

@test "V4-02 T02: rollback also refuses to relocate a linked worktree" {
  legacy_install 1.41.1
  git -C "$EIDOLONS_NEXUS" worktree add -q --detach "$EIDOLONS_HOME/linked" HEAD
  cp -R "$EIDOLONS_NEXUS" "$EIDOLONS_HOME/nexus.prev"
  export EIDOLONS_NEXUS="$EIDOLONS_HOME/linked"
  local before
  before="$(legacy_snapshot "$EIDOLONS_NEXUS")"
  run legacy_upgrade --rollback
  [ "$status" -eq 1 ]
  [[ "$output" == *"linked worktree"* ]]
  [ "$(legacy_snapshot "$EIDOLONS_NEXUS")" = "$before" ]
  [ -f "$EIDOLONS_NEXUS/.git" ]
  [ ! -d "$EIDOLONS_HOME/nexus.failed" ]
}
