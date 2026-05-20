#!/usr/bin/env bats
#
# cli/tests/mcp_list.bats — coverage for 'eidolons mcp list' (F1.1 stories S1, S2).
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

# ─── Fixtures ────────────────────────────────────────────────────────────────

setup_mcp_env() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
}

# ─── Tests ───────────────────────────────────────────────────────────────────

@test "mcp list: exits 0 and shows header" {
  setup_mcp_env
  run eidolons mcp list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "NAME"
  echo "$output" | grep -q "LATEST"
}

@test "mcp list: shows atlas-aci entry" {
  setup_mcp_env
  run eidolons mcp list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "atlas-aci"
}

@test "mcp list: shows junction entry" {
  setup_mcp_env
  run eidolons mcp list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "junction"
}

@test "mcp list S2: no lockfile — INSTALLED column shows dash" {
  setup_mcp_env
  # Ensure no lockfile.
  rm -f eidolons.mcp.lock
  run eidolons mcp list
  [ "$status" -eq 0 ]
  # The dash character for not-installed.
  echo "$output" | grep -q "—"
}

@test "mcp list S2: no lockfile — UPDATE? shows install" {
  setup_mcp_env
  rm -f eidolons.mcp.lock
  run eidolons mcp list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "install"
}

@test "mcp list: --json flag returns JSON array" {
  setup_mcp_env
  run eidolons mcp list --json
  [ "$status" -eq 0 ]
  # Output should be parseable JSON.
  echo "$output" | jq 'length > 0' > /dev/null
}

@test "mcp list: --json includes atlas-aci" {
  setup_mcp_env
  run eidolons mcp list --json
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.[].name' | grep 'atlas-aci')"
  [ "$result" = "atlas-aci" ]
}

@test "mcp list: help exits 0" {
  run eidolons mcp list --help
  [ "$status" -eq 0 ]
}
