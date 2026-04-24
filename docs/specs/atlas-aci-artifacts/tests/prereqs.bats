#!/usr/bin/env bats
# tests/prereqs.bats — T19, T20, T21, T22 from §5.2.
#
# Each test removes or tampers with one prereq stub and asserts the
# script exits 5 with a copy-pasteable install hint on stderr.

load helpers

# Anchors: Spec §5.2 T19 (missing uv → exit 5 + uv install hint)
@test "T19: missing uv → exit 5, stderr contains uv install hint" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  uninstall_stub "uv"

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 5 ]
  [[ "$output" == *"uv"* ]]
  [[ "$output" == *"astral.sh/uv/install.sh"* ]]
  # No MCP config should have been written.
  [ ! -f .mcp.json ]
}

# Anchors: Spec §5.2 T20 (missing rg → exit 5 + rg install hint)
@test "T20: missing rg → exit 5, stderr mentions ripgrep" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  uninstall_stub "rg"

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 5 ]
  [[ "$output" == *"ripgrep"* ]] || [[ "$output" == *"'rg'"* ]]
  [ ! -f .mcp.json ]
}

# Anchors: Spec §5.2 T21 (python3 < 3.11 → exit 5)
@test "T21: python3 reports 3.10 → exit 5" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  # Override the python3 stub to report 3.10.
  install_stub "python3" 0 'case "$1" in
  --version) echo "Python 3.10.12"; exit 0 ;;
esac'

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 5 ]
  [[ "$output" == *"3.11"* ]]
  [ ! -f .mcp.json ]
}

# Anchors: Spec §5.2 T22 (missing atlas-aci binary → exit 5 + clone hint)
@test "T22: missing atlas-aci binary → exit 5 with clone + uv tool install hint" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  uninstall_stub "atlas-aci"

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 5 ]
  [[ "$output" == *"atlas-aci"* ]]
  [[ "$output" == *"git clone"* ]]
  [[ "$output" == *"uv tool install"* ]]
  [ ! -f .mcp.json ]
}

# Anchors: Spec §5.2 T22 (verifies exit happens BEFORE atlas-aci index is called)
@test "T22: missing atlas-aci → no atlas-aci subcommands were invoked" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  # Keep the stub so its logfile exists, then mask the executable by
  # deleting it — `command -v` returns non-zero but the logfile persists
  # so we can verify zero invocations.
  rm -f "$STUBS_DIR/atlas-aci"
  : > "$BATS_TEST_TMPDIR/atlas-aci.log"

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 5 ]

  local count
  count="$(stub_log_count atlas-aci)"
  [ "$count" = "0" ]
}
