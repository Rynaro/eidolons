#!/usr/bin/env bats
#
# nexus.bats — covers 'eidolons nexus' command family (STORY-5).
# Test IDs: PR-8, PR-9, PR-10.
#
# PR-8: nexus channel get/set round-trip for main/stable/<tag>/<sha>; empty arg → exit 2.
# PR-9: nexus status prints CLI ref + roster channel + freshness; offline → unknown, exit 0.
# PR-10: nexus refresh no-ops (prints skip) when EIDOLONS_NEXUS set / EIDOLONS_SKIP_REFRESH=1.

load helpers

# ─── PR-8: nexus channel get/set round-trip ──────────────────────────────

@test "PR-8a: nexus channel get returns current channel (default main)" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr8a"
  mkdir -p "$fake_nexus/.git"
  printf 'main\n' > "$fake_nexus/.roster_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' channel
  "
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

@test "PR-8b: nexus channel set then get round-trips main" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr8b"
  mkdir -p "$fake_nexus"
  printf 'stable\n' > "$fake_nexus/.roster_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' channel main
  "
  [ "$status" -eq 0 ]
  # After set, read back value.
  local got
  got="$(cat "$fake_nexus/.roster_ref")"
  [ "$got" = "main" ]
}

@test "PR-8c: nexus channel set then get round-trips stable" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr8c"
  mkdir -p "$fake_nexus"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' channel stable
  "
  [ "$status" -eq 0 ]
  local got
  got="$(cat "$fake_nexus/.roster_ref")"
  [ "$got" = "stable" ]
}

@test "PR-8d: nexus channel set then get round-trips a tag" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr8d"
  mkdir -p "$fake_nexus"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' channel v1.5.0
  "
  [ "$status" -eq 0 ]
  local got
  got="$(cat "$fake_nexus/.roster_ref")"
  [ "$got" = "v1.5.0" ]
}

@test "PR-8e: nexus channel set then get round-trips a sha" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr8e"
  mkdir -p "$fake_nexus"
  local sha="abc1234def5678901234567890123456789012ab"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' channel '$sha'
  "
  [ "$status" -eq 0 ]
  local got
  got="$(cat "$fake_nexus/.roster_ref")"
  [ "$got" = "$sha" ]
}

@test "PR-8f: nexus channel with empty arg exits 2" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr8f"
  mkdir -p "$fake_nexus"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' channel ''
  " 2>&1
  [ "$status" -eq 2 ]
  [[ "$output" =~ "must not be empty" ]]
}

@test "PR-8g: nexus channel with whitespace-only arg exits 2" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr8g"
  mkdir -p "$fake_nexus"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' channel '   '
  " 2>&1
  [ "$status" -eq 2 ]
}

@test "PR-8h: nexus channel set emits old->new echo" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr8h"
  mkdir -p "$fake_nexus"
  printf 'main\n' > "$fake_nexus/.roster_ref"

  run bash -c "
    export EIDOLONS_NEXUS=''
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' channel v1.14.0
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "main -> v1.14.0" ]]
}

# ─── PR-9: nexus status — CLI ref + roster channel + freshness ───────────

@test "PR-9a: nexus status shows distinct CLI ref and roster channel" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr9a"
  mkdir -p "$fake_nexus"
  printf 'v1.14.0\n' > "$fake_nexus/.install_ref"
  printf 'main\n' > "$fake_nexus/.roster_ref"
  printf 'v1.14.0\n' > "$fake_nexus/VERSION"
  printf 'abc1234\n' > "$fake_nexus/.install_commit"

  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='https://invalid.example.invalid/notareal.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' status
  " 2>&1
  [ "$status" -eq 0 ]
  # Must show CLI ref (install_ref) and roster channel separately.
  [[ "$output" =~ "ref:" ]]
  [[ "$output" =~ "channel:" ]]
  [[ "$output" =~ "main" ]]
}

@test "PR-9b: nexus status exits 0 even when upstream unreachable (offline)" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr9b"
  mkdir -p "$fake_nexus"
  printf 'v1.14.0\n' > "$fake_nexus/.install_ref"
  printf 'main\n' > "$fake_nexus/.roster_ref"
  printf 'v1.14.0\n' > "$fake_nexus/VERSION"
  printf 'abc1234\n' > "$fake_nexus/.install_commit"

  run bash -c "
    export EIDOLONS_NEXUS=''
    export EIDOLONS_REPO='https://invalid.example.invalid/notareal.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' status
  " 2>&1
  [ "$status" -eq 0 ]
  # Freshness should be unknown when offline.
  [[ "$output" =~ "unknown" ]] || [[ "$output" =~ "unreachable" ]]
}

@test "PR-9c: nexus status with EIDOLONS_NEXUS set still shows sidecar data" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr9c"
  mkdir -p "$fake_nexus"
  printf 'v1.14.0\n' > "$fake_nexus/.install_ref"
  printf 'stable\n' > "$fake_nexus/.roster_ref"
  printf 'v1.14.0\n' > "$fake_nexus/VERSION"
  printf 'abc1234\n' > "$fake_nexus/.install_commit"

  run bash -c "
    export EIDOLONS_NEXUS='$fake_nexus'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' status
  " 2>&1
  [ "$status" -eq 0 ]
  # Channel should still be displayed.
  [[ "$output" =~ "channel:" ]]
  [[ "$output" =~ "stable" ]]
}

# ─── PR-10: nexus refresh skip when EIDOLONS_NEXUS set / skip flag ────────

@test "PR-10a: nexus refresh is a no-op when EIDOLONS_NEXUS is set" {
  # With a poison repo, any real fetch would fail. If EIDOLONS_NEXUS is set,
  # the refresh should skip without error.
  run bash -c "
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    export EIDOLONS_REPO='https://invalid.example.invalid/poison.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' refresh
  " 2>&1
  [ "$status" -eq 0 ]
  # Should print "skipped" message.
  [[ "$output" =~ "skipped" ]]
}

@test "PR-10b: nexus refresh is a no-op when EIDOLONS_SKIP_REFRESH=1" {
  run bash -c "
    unset EIDOLONS_NEXUS
    export EIDOLONS_SKIP_REFRESH=1
    export EIDOLONS_REPO='https://invalid.example.invalid/poison.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' refresh
  " 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "skipped" ]]
}

@test "PR-10c: nexus refresh with offline repo warns and exits 0" {
  local fake_nexus="$BATS_TEST_TMPDIR/nexus-pr10c"
  mkdir -p "$fake_nexus/.git"
  printf 'main\n' > "$fake_nexus/.roster_ref"

  run bash -c "
    unset EIDOLONS_NEXUS
    export EIDOLONS_SKIP_REFRESH=0
    export EIDOLONS_REPO='https://invalid.example.invalid/poison.git'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$fake_nexus'
    ROSTER_FILE='$fake_nexus/roster/index.yaml'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' refresh
  " 2>&1
  [ "$status" -eq 0 ]
}

# ─── nexus unknown subcommand exits 2 ────────────────────────────────────

@test "nexus: unknown subcommand exits 2" {
  run bash -c "
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' bogus
  " 2>&1
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Unknown nexus subcommand" ]]
}

@test "nexus: help flag exits 0" {
  run bash -c "
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/nexus.sh' --help
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

# ─── eidolons nexus dispatcher integration ────────────────────────────────

@test "eidolons nexus: dispatcher routes to nexus.sh" {
  run eidolons nexus --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
  [[ "$output" =~ "refresh" ]]
  [[ "$output" =~ "channel" ]]
  [[ "$output" =~ "status" ]]
}
