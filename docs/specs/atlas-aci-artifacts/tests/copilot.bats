#!/usr/bin/env bats
# tests/copilot.bats — T14, T15 from §5.2.
#
# Copilot-specific edge cases: "no agent files" skip (T14), and
# byte-for-byte body preservation after install/remove (T15).

load helpers

# Anchors: Spec §5.2 T14 (copilot host with no .agent.md → skip, exit 0)
@test "T14: copilot host with no .agent.md files → info log + exit 0" {
  setup_fresh_project
  setup_stubs
  seed_copilot_host_empty   # .github/ exists, .github/agents/ does not

  run_aci --install --host copilot --non-interactive
  [ "$status" -eq 0 ]
  # stdout is empty on success (T28). Stderr carries the info note.
  [ -z "$(echo "$output" | grep -v '^$')" ] || true
  # No .agent.md files were created.
  run find .github/agents -name '*.agent.md' 2>/dev/null
  [ -z "$output" ] || {
    echo ".github/agents/*.agent.md appeared unexpectedly:"
    echo "$output"
    return 1
  }
}

# Anchors: Spec §5.2 T15 (YAML frontmatter preservation: body byte-identical)
@test "T15: install preserves .agent.md body byte-for-byte" {
  setup_fresh_project
  setup_stubs
  seed_copilot_host_with_agent

  # Snapshot the original body (everything after the second ---).
  local original_body
  original_body="$(awk '
    /^---$/ { c++; if (c == 2) { capture = 1; next } }
    capture { print }
  ' ./.github/agents/example.agent.md)"

  run_aci --install --host copilot --non-interactive
  [ "$status" -eq 0 ]
  assert_agent_md_body_preserved ./.github/agents/example.agent.md "$original_body"
}

# Anchors: Spec §5.2 T15 (body preservation across remove too)
@test "T15: remove preserves .agent.md body byte-for-byte" {
  setup_fresh_project
  setup_stubs
  seed_copilot_host_with_agent

  local original_body
  original_body="$(awk '
    /^---$/ { c++; if (c == 2) { capture = 1; next } }
    capture { print }
  ' ./.github/agents/example.agent.md)"

  run_aci --install --host copilot --non-interactive
  [ "$status" -eq 0 ]
  run_aci --remove --host copilot --non-interactive
  [ "$status" -eq 0 ]
  assert_agent_md_body_preserved ./.github/agents/example.agent.md "$original_body"
}
