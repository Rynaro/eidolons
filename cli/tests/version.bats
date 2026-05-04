#!/usr/bin/env bats

load helpers

@test "version: prints eidolons <semver>" {
  run eidolons version
  [ "$status" -eq 0 ]
  # The first line of output must be the version line; subsequent lines
  # carry enriched metadata (commit, ref, installed, nexus path).
  echo "$output" | head -1 | grep -qE '^eidolons [0-9]+\.[0-9]+\.[0-9]'
}

@test "version: --quiet prints single-line grep-compat output" {
  run eidolons --version --quiet
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^eidolons\ [0-9]+\.[0-9]+\.[0-9]+ ]]
  # Must not contain newlines (single line).
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "version: --version flag works" {
  run eidolons --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ eidolons ]]
}

@test "version: -v flag works" {
  run eidolons -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ eidolons ]]
}

@test "version: unknown command exits 2" {
  run eidolons bogus-command-xyz
  [ "$status" -eq 2 ]
  [[ "$output" =~ Unknown\ command ]]
}
