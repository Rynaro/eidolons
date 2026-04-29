#!/usr/bin/env bats
# tests/host_filter.bats — T11, T12, T13 from §5.2.
#
# Exercises --host filtering against a fully-populated project where
# markers for all three hosts are present. The script must write only
# to the host named on --host.

load helpers

# Common fixture: all three host markers present.
seed_all_hosts() {
  seed_claude_host
  seed_cursor_host
  seed_copilot_host_with_agent
}

# Anchors: Spec §5.2 T11 (--host cursor only touches .cursor/mcp.json)
@test "T11: --host cursor only writes .cursor/mcp.json" {
  setup_fresh_project
  setup_stubs
  seed_all_hosts

  run_aci --install --host cursor --non-interactive
  [ "$status" -eq 0 ]

  [ -f .cursor/mcp.json ]
  [ ! -f .mcp.json ]
  # Copilot agent file should be unchanged (baseline content from
  # seed_copilot_host_with_agent does NOT contain atlas-aci).
  run grep -q 'name: atlas-aci' ./.github/agents/example.agent.md
  [ "$status" -ne 0 ]
}

# Anchors: Spec §5.2 T12 (--host copilot only touches .github/agents/*.agent.md)
@test "T12: --host copilot only writes .github/agents/*.agent.md" {
  setup_fresh_project
  setup_stubs
  seed_all_hosts

  run_aci --install --host copilot --non-interactive
  [ "$status" -eq 0 ]

  [ ! -f .mcp.json ]
  [ ! -f .cursor/mcp.json ]
  assert_agent_md_has_atlas_aci ./.github/agents/example.agent.md
}

# Anchors: Spec §5.2 T13 (--host claude-code only touches .mcp.json)
@test "T13: --host claude-code only writes .mcp.json" {
  setup_fresh_project
  setup_stubs
  seed_all_hosts

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]

  [ -f .mcp.json ]
  [ ! -f .cursor/mcp.json ]
  run grep -q 'name: atlas-aci' ./.github/agents/example.agent.md
  [ "$status" -ne 0 ]
}
