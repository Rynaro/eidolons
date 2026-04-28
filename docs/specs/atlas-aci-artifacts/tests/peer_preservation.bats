#!/usr/bin/env bats
# tests/peer_preservation.bats — T9a/b/c, T10a/b/c from §5.2.
#
# Specialises the A11 invariant ("don't clobber peer MCP servers") per
# host file type. T9* covers install, T10* covers remove.

load helpers

# Anchors: Spec §5.2 T9a (.mcp.json install preserves peers)
@test "T9a: install preserves peer mcpServers.other-server in .mcp.json" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  seed_mcp_json_with_peer ./.mcp.json

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]

  # atlas-aci sibling present
  assert_mcp_json_contains .mcp.json "atlas-aci"
  # peer intact (jq -S normalised compare)
  assert_peer_preserved .mcp.json
}

# Anchors: Spec §5.2 T9b (.cursor/mcp.json install preserves peers)
@test "T9b: install preserves peer mcpServers.other-server in .cursor/mcp.json" {
  setup_fresh_project
  setup_stubs
  seed_cursor_host
  seed_mcp_json_with_peer ./.cursor/mcp.json

  run_aci --install --host cursor --non-interactive
  [ "$status" -eq 0 ]

  assert_mcp_json_contains .cursor/mcp.json "atlas-aci"
  assert_peer_preserved .cursor/mcp.json
}

# Anchors: Spec §5.2 T9c (copilot agent preserves peer list entries)
@test "T9c: install preserves peer name:other-server in .agent.md frontmatter" {
  setup_fresh_project
  setup_stubs
  seed_copilot_agent_with_peer

  run_aci --install --host copilot --non-interactive
  [ "$status" -eq 0 ]

  assert_agent_md_has_atlas_aci ./.github/agents/example.agent.md
  # Peer list entry still present.
  run yq eval '.tools.mcp_servers[] | select(.name == "other-server")' \
      <(awk 'NR>1 && /^---$/ { exit } NR>1 { print }' ./.github/agents/example.agent.md)
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# Anchors: Spec §5.2 T10a (.mcp.json remove preserves peers)
@test "T10a: remove preserves peer mcpServers.other-server in .mcp.json" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  seed_mcp_json_with_peer ./.mcp.json

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  assert_mcp_json_contains .mcp.json "atlas-aci"

  run_aci --remove --host claude-code --non-interactive
  [ "$status" -eq 0 ]

  assert_mcp_json_missing .mcp.json "atlas-aci"
  assert_peer_preserved .mcp.json
}

# Anchors: Spec §5.2 T10b (.cursor/mcp.json remove preserves peers)
@test "T10b: remove preserves peer mcpServers.other-server in .cursor/mcp.json" {
  setup_fresh_project
  setup_stubs
  seed_cursor_host
  seed_mcp_json_with_peer ./.cursor/mcp.json

  run_aci --install --host cursor --non-interactive
  [ "$status" -eq 0 ]
  run_aci --remove --host cursor --non-interactive
  [ "$status" -eq 0 ]

  assert_mcp_json_missing .cursor/mcp.json "atlas-aci"
  assert_peer_preserved .cursor/mcp.json
}

# Anchors: Spec §5.2 T10c (copilot agent remove preserves peer list entries)
@test "T10c: remove preserves peer name:other-server in .agent.md frontmatter" {
  setup_fresh_project
  setup_stubs
  seed_copilot_agent_with_peer

  run_aci --install --host copilot --non-interactive
  [ "$status" -eq 0 ]
  run_aci --remove --host copilot --non-interactive
  [ "$status" -eq 0 ]

  # atlas-aci gone
  run grep -c 'name: atlas-aci' ./.github/agents/example.agent.md
  [ "$status" -ne 0 ] || [ "$output" = "0" ]
  # peer intact
  run yq eval '.tools.mcp_servers[] | select(.name == "other-server")' \
      <(awk 'NR>1 && /^---$/ { exit } NR>1 { print }' ./.github/agents/example.agent.md)
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
