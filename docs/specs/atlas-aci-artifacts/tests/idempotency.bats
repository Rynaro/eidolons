#!/usr/bin/env bats
# tests/idempotency.bats — T6, T7, T8 from docs/specs/atlas-aci-integration.md §5.2.
#
# Note: this suite MUST run under /bin/bash on macos-latest per T27 to
# validate bash 3.2 compliance. See tests/operational.bats for the
# shebang sanity assertion.

load helpers

# Anchors: Spec §5.2 T6 (install idempotency, P1)
@test "T6: install twice → byte-identical .mcp.json, .gitignore" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  [ -f .mcp.json ]
  local first_mcp first_gi
  first_mcp="$(normalise_json .mcp.json)"
  first_gi="$(cat .gitignore)"

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  local second_mcp second_gi
  second_mcp="$(normalise_json .mcp.json)"
  second_gi="$(cat .gitignore)"

  # Byte-level equality after key-order normalisation.
  [ "$first_mcp" = "$second_mcp" ]
  [ "$first_gi"  = "$second_gi" ]
  # .gitignore has exactly one .atlas/ line (see T16 for the explicit
  # count assertion).
}

# Anchors: Spec §5.2 T6 (idempotency extended to cursor host)
@test "T6: install twice with cursor host → byte-identical .cursor/mcp.json" {
  setup_fresh_project
  setup_stubs
  seed_cursor_host

  run_aci --install --host cursor --non-interactive
  [ "$status" -eq 0 ]
  [ -f .cursor/mcp.json ]
  local first
  first="$(normalise_json .cursor/mcp.json)"

  run_aci --install --host cursor --non-interactive
  [ "$status" -eq 0 ]
  local second
  second="$(normalise_json .cursor/mcp.json)"

  [ "$first" = "$second" ]
}

# Anchors: Spec §5.2 T7 (round-trip: install → remove → install)
@test "T7: install → remove → install round-trips to single-install state" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  local baseline
  baseline="$(normalise_json .mcp.json)"

  run_aci --remove --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  # After remove, mcpServers.atlas-aci is absent.
  assert_mcp_json_missing .mcp.json "atlas-aci"

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  local rebuilt
  rebuilt="$(normalise_json .mcp.json)"

  [ "$baseline" = "$rebuilt" ]
}

# Anchors: Spec §5.2 T8 (remove is idempotent when nothing installed)
@test "T8: remove on fresh project → exit 0, no MCP files created" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  run_aci --remove --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  [ ! -f .mcp.json ]
  [ ! -f .cursor/mcp.json ]
}

# Anchors: Spec §5.2 T8 (remove on already-clean project is idempotent)
@test "T8: remove twice → exit 0 both times, no files materialised" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  run_aci --remove --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  run_aci --remove --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  [ ! -f .mcp.json ]
}
