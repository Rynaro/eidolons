#!/usr/bin/env bats

load helpers

@test "list --available: prints every roster Eidolon" {
  run eidolons list --available
  [ "$status" -eq 0 ]
  [[ "$output" =~ atlas ]]
  [[ "$output" =~ spectra ]]
  [[ "$output" =~ apivr ]]
  [[ "$output" =~ idg ]]
  [[ "$output" =~ forge ]]
  [[ "$output" =~ NAME ]]
  [[ "$output" =~ METHODOLOGY ]]
}

@test "list -a: short flag for --available" {
  run eidolons list -a
  [ "$status" -eq 0 ]
  [[ "$output" =~ atlas ]]
}

@test "list --presets: enumerates every preset" {
  run eidolons list --presets
  [ "$status" -eq 0 ]
  [[ "$output" =~ minimal ]]
  [[ "$output" =~ pipeline ]]
  [[ "$output" =~ full ]]
}

@test "list --json: emits parseable JSON" {
  run eidolons list --json
  [ "$status" -eq 0 ]
  # Should contain the top-level roster keys.
  [[ "$output" =~ eidolons ]]
  [[ "$output" =~ presets ]]
  # Must round-trip through jq.
  echo "$output" | jq -e '.eidolons | length > 0' >/dev/null
  echo "$output" | jq -e '.presets | length > 0' >/dev/null
}

@test "list --installed: defaults to available when no manifest present" {
  # Default mode is "installed" but falls back to "available" when cwd lacks eidolons.yaml.
  run eidolons list
  [ "$status" -eq 0 ]
  [[ "$output" =~ atlas ]]
}

@test "list --installed: errors explicitly when flag forced without manifest" {
  run eidolons list --installed
  [ "$status" -ne 0 ]
  [[ "$output" =~ No\ eidolons\.yaml ]]
}

@test "list --installed: works with manifest + lock" {
  seed_manifest
  seed_lock
  run eidolons list --installed
  [ "$status" -eq 0 ]
  [[ "$output" =~ atlas ]]
  [[ "$output" =~ VERSION ]]
}

@test "list --installed: works with manifest but no lock" {
  seed_manifest
  run eidolons list --installed
  [ "$status" -eq 0 ]
  [[ "$output" =~ atlas ]]
  [[ "$output" =~ not\ installed ]]
}

@test "list -h: help prints" {
  run eidolons list -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons\ list ]]
}

@test "list: rejects unknown flag" {
  run eidolons list --bogus-flag
  [ "$status" -ne 0 ]
}
