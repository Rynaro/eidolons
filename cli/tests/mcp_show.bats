#!/usr/bin/env bats
#
# cli/tests/mcp_show.bats — coverage for 'eidolons mcp show' (F1.2 stories S3, S4).
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

setup_mcp_env() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
}

@test "mcp show: atlas-aci exits 0" {
  setup_mcp_env
  run eidolons mcp show atlas-aci
  [ "$status" -eq 0 ]
}

@test "mcp show S3: shows name and kind" {
  setup_mcp_env
  run eidolons mcp show atlas-aci
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "atlas-aci"
  echo "$output" | grep -q "oci-image"
}

@test "mcp show S3: shows description" {
  setup_mcp_env
  run eidolons mcp show atlas-aci
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "structural codebase"
}

@test "mcp show S3: shows versions section" {
  setup_mcp_env
  run eidolons mcp show atlas-aci
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "latest:"
  echo "$output" | grep -q "pins.stable:"
}

@test "mcp show S3: shows not installed when lockfile absent" {
  setup_mcp_env
  rm -f eidolons.mcp.lock
  run eidolons mcp show atlas-aci
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not installed"
}

@test "mcp show S4: unknown name exits 1" {
  setup_mcp_env
  run eidolons mcp show no-such-mcp
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not found in catalogue"
}

@test "mcp show S4: unknown name suggests mcp list" {
  setup_mcp_env
  run eidolons mcp show no-such-mcp
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "eidolons mcp list"
}

@test "mcp show: junction exits 0" {
  setup_mcp_env
  run eidolons mcp show junction
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "binary"
}

@test "mcp show: help exits 0" {
  run eidolons mcp show --help
  [ "$status" -eq 0 ]
}
