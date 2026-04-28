#!/usr/bin/env bats
# tests/index.bats — T23, T24 from §5.2.
#
# T23: atlas-aci index failure aborts before any MCP config writes.
# T24: .atlas/manifest.yaml existing pre-run → index skipped on re-install.

load helpers

# Anchors: Spec §5.2 T23 (atlas-aci index non-zero → exit 6, no MCP writes)
@test "T23: atlas-aci index failure → exit 6 and no MCP config files written" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  # Override the atlas-aci stub so `index` exits non-zero.
  install_stub "atlas-aci" 0 'case "$1" in
  index) echo "atlas-aci: index failed (stubbed failure)" >&2; exit 7 ;;
  *) : ;;
esac'

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 6 ]
  # atlas-aci error should have been forwarded on stderr.
  [[ "$output" == *"atlas-aci: index failed"* ]] || \
    [[ "$output" == *"index failed"* ]]
  # Ordering invariant: no MCP config files created.
  [ ! -f .mcp.json ]
  [ ! -f .cursor/mcp.json ]
}

# Anchors: Spec §5.2 T24 (.atlas/manifest.yaml present → skip re-index)
@test "T24: .atlas/manifest.yaml present → atlas-aci index not invoked" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  # Pre-create the manifest that signals a prior successful index.
  mkdir -p .atlas
  printf "generated: true\n" > .atlas/manifest.yaml
  # Clear the atlas-aci log so we can assert 0 invocations.
  : > "$BATS_TEST_TMPDIR/atlas-aci.log"

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]

  local count
  count="$(stub_log_count atlas-aci)"
  [ "$count" = "0" ]
}
