#!/usr/bin/env bats

load helpers

@test "sync: fails without eidolons.yaml" {
  run eidolons sync
  [ "$status" -ne 0 ]
  [[ "$output" =~ No\ eidolons\.yaml ]]
}

@test "sync --dry-run: prints planned install actions without cloning" {
  seed_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ atlas ]]
  [[ "$output" =~ would ]]
}

@test "sync --dry-run: still writes the lock header" {
  seed_manifest
  run eidolons sync --dry-run
  [ -f eidolons.lock ]
  run cat eidolons.lock
  [[ "$output" =~ generated_at ]]
}

@test "sync -h: help prints" {
  run eidolons sync -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons\ sync ]]
}

@test "sync: rejects unknown flag" {
  seed_manifest
  run eidolons sync --bogus
  [ "$status" -ne 0 ]
}
