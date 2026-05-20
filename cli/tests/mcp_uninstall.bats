#!/usr/bin/env bats
#
# cli/tests/mcp_uninstall.bats — coverage for 'eidolons mcp uninstall' (F2.4 stories S12-S14).
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

FAKE_JUNCTION_VERSION="0.2.0"

# Seed a minimal junction lockfile entry.
seed_junction_lock_for_uninstall() {
  local ver="${1:-$FAKE_JUNCTION_VERSION}"
  local cache_dir="$EIDOLONS_HOME/cache/junction@${ver}"
  mkdir -p "$cache_dir"
  cat > "$cache_dir/junction" <<'JSTUB'
#!/usr/bin/env bash
echo "stub"
JSTUB
  chmod +x "$cache_dir/junction"

  cat > eidolons.mcp.lock <<EOF
# eidolons.mcp.lock
generated_at: "2026-05-19T00:00:00Z"
eidolons_cli_version: "1.3.0"
catalogue_version: "1.0"
mcps:
  - name: junction
    kind: binary
    version: "${ver}"
    source:
      repo: "Rynaro/Junction"
    integrity:
      algo: none
      value: ""
    target: "${cache_dir}/junction"
    hosts_wired: []
    installed_at: "2026-05-19T00:00:00Z"
EOF
}

@test "mcp uninstall: help exits 0" {
  run eidolons mcp uninstall --help
  [ "$status" -eq 0 ]
}

@test "mcp uninstall: no args exits 2" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons mcp uninstall
  [ "$status" -eq 2 ]
}

@test "mcp uninstall: unknown MCP exits 1" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons mcp uninstall no-such-mcp
  [ "$status" -eq 1 ]
}

@test "mcp uninstall S12: removes lockfile entry after uninstall" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_for_uninstall
  run bash "$EIDOLONS_ROOT/cli/src/mcp_uninstall.sh" "junction"
  [ "$status" -eq 0 ]
  # Entry should be gone from lockfile (or lockfile removed if empty).
  if [ -f "eidolons.mcp.lock" ]; then
    result="$(grep -c 'junction' eidolons.mcp.lock || true)"
    [ "$result" -eq 0 ]
  fi
}

@test "mcp uninstall S14: idempotent — second uninstall is no-op" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_for_uninstall
  run bash "$EIDOLONS_ROOT/cli/src/mcp_uninstall.sh" "junction"
  [ "$status" -eq 0 ]
  # Second uninstall — should not error even when entry is already gone.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_uninstall.sh" "junction"
  [ "$status" -eq 0 ]
}

@test "mcp uninstall: lockfile stays valid YAML after uninstall" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_for_uninstall
  run bash "$EIDOLONS_ROOT/cli/src/mcp_uninstall.sh" "junction"
  [ "$status" -eq 0 ]
  if [ -f "eidolons.mcp.lock" ]; then
    run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' && yaml_to_json eidolons.mcp.lock | jq empty"
    [ "$status" -eq 0 ]
  fi
}
