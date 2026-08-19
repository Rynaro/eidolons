#!/usr/bin/env bats
# mcp_resources.bats — OCI MCP per-container resource profile contract.

load helpers

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  mkdir -p "$EIDOLONS_HOME"
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"
  # shellcheck disable=SC1090
  . "$EIDOLONS_ROOT/cli/src/lib.sh"
  # shellcheck disable=SC1090
  . "$EIDOLONS_ROOT/cli/src/lib_mcp.sh"
}

write_manifest() {
  local project_profile="${1:-}"
  local entry_profile="${2:-}"
  {
    echo 'version: 1'
    echo 'hosts:'
    echo '  wire: [codex]'
    echo 'members:'
    echo '  - name: atlas'
    echo '    version: "^1.0.0"'
    if [ -n "$project_profile" ]; then
      echo 'mcp_runtime:'
      echo "  resource_profile: ${project_profile}"
    fi
    echo 'mcps:'
    echo '  - name: crystalium'
    echo '    version: "^2.2.0"'
    if [ -n "$entry_profile" ]; then
      echo "    resource_profile: ${entry_profile}"
    fi
  } > eidolons.yaml
}

@test "absent profile preserves unlimited legacy behavior" {
  write_manifest
  run _mcp_runtime_resolve crystalium "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.resource_profile')" = "unlimited" ]
  [ "$(printf '%s' "$output" | jq -r 'has("limits")')" = "false" ]
}

@test "per-entry profile overrides project default" {
  write_manifest minimal full
  run _mcp_runtime_resolve crystalium "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.resource_profile')" = "full" ]
  [ "$(printf '%s' "$output" | jq -r '.limits.cpus')" = "2.00" ]
  [ "$(printf '%s' "$output" | jq -r '.limits.memory')" = "4g" ]
  [ "$(printf '%s' "$output" | jq -r '.limits.pids')" = "512" ]
}

@test "standard profiles resolve catalogue ceilings for every OCI MCP" {
  write_manifest standard
  local expected
  expected='atlas-aci=1.00,1g,256 crystalium=1.00,2g,256 tonberry=0.50,256m,96 atomos=0.50,256m,96'
  local pair name values actual
  for pair in $expected; do
    name="${pair%%=*}"
    values="${pair#*=}"
    actual="$(_mcp_runtime_resolve "$name" "$TEST_PROJECT" \
      | jq -r '[.limits.cpus,.limits.memory,(.limits.pids|tostring)] | join(",")')"
    [ "$actual" = "$values" ]
  done
}

@test "bounded profile inserts one complete limit set after docker run" {
  write_manifest standard
  local rendered applied args
  rendered='{"mcpServers":{"crystalium":{"command":"docker","args":["run","--rm","-i","example@sha256:abc","serve"]}}}'
  applied="$(_mcp_runtime_apply crystalium "$TEST_PROJECT" "$rendered")"
  args="$(printf '%s' "$applied" | jq -c '.mcpServers.crystalium.args')"
  [ "$args" = '["run","--cpus","1.00","--memory","2g","--memory-swap","2g","--pids-limit","256","--rm","-i","example@sha256:abc","serve"]' ]
  [ "$(printf '%s' "$args" | jq '[.[] | select(. == "--memory")] | length')" -eq 1 ]
}

@test "rendered Codex TOML carries the same bounded Docker argv" {
  write_manifest standard
  _mcp_oci_render_and_merge \
    crystalium "$TEST_PROJECT" sha256:test \
    cli/templates/mcp/crystalium.mcp.json.tmpl true

  run grep -F -- 'args = ["run","--cpus","1.00","--memory","2g","--memory-swap","2g","--pids-limit","256"' \
    "$TEST_PROJECT/.codex/config.toml"
  [ "$status" -eq 0 ]
  run jq -e '.mcpServers.crystalium.args[0:9] == ["run","--cpus","1.00","--memory","2g","--memory-swap","2g","--pids-limit","256"]' \
    "$TEST_PROJECT/.mcp.json"
  [ "$status" -eq 0 ]
}

@test "unlimited leaves rendered Docker args unchanged" {
  write_manifest unlimited
  local rendered applied
  rendered='{"mcpServers":{"crystalium":{"command":"docker","args":["run","--rm","-i","example@sha256:abc","serve"]}}}'
  applied="$(_mcp_runtime_apply crystalium "$TEST_PROJECT" "$rendered")"
  [ "$(printf '%s' "$applied" | jq -c '.mcpServers.crystalium.args')" = '["run","--rm","-i","example@sha256:abc","serve"]' ]
}

@test "invalid profile fails before rendering" {
  write_manifest tiny
  run _mcp_runtime_resolve crystalium "$TEST_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown MCP resource profile 'tiny'"* ]]
}

@test "lock receipt tracks bounded drift without churning legacy unlimited" {
  local base before after bounded
  base='{"name":"crystalium","kind":"oci-image","version":"2.2.0","source":{"image":"ghcr.io/rynaro/crystalium"},"integrity":{"algo":"oci-digest","value":"sha256:test"},"target":".mcp.json","hosts_wired":[".mcp.json"],"installed_at":"2026-08-19T00:00:00Z"}'
  mcp_lock_write_from_array "[$base]"
  before="$(cksum eidolons.mcp.lock)"

  mcp_lock_upsert crystalium \
    "$(printf '%s' "$base" | jq '.runtime={resource_profile:"unlimited"}')"
  after="$(cksum eidolons.mcp.lock)"
  [ "$before" = "$after" ]

  bounded="$(printf '%s' "$base" | jq \
    '.runtime={resource_profile:"standard",limits:{cpus:"1.00",memory:"2g",pids:256}}')"
  mcp_lock_upsert crystalium "$bounded"
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; yaml_to_json eidolons.mcp.lock | jq -e '.mcps[0].runtime == {resource_profile:\"standard\",limits:{cpus:\"1.00\",memory:\"2g\",pids:256}}'"
  [ "$status" -eq 0 ]
}
