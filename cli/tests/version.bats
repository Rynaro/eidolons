#!/usr/bin/env bats

load helpers

@test "version: prints eidolons <semver>" {
  run eidolons version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^eidolons\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
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
