#!/usr/bin/env bats
# cli/tests/mcp_catalogue_lint.bats — check_mcp_catalogue.sh namespace guard.
#
# The guard makes the historical mcp__atlas_aci__* (underscore) vs
# mcp__atlas-aci__* (hyphen) inert-grant bug unmergeable: the glob, every
# enumerated tool, and the template server key must all derive from the
# catalogue entry name byte-for-byte.

load helpers

CHECKER="$EIDOLONS_ROOT/cli/src/check_mcp_catalogue.sh"

# Seed a minimal nexus root with a single-entry mcps.yaml whose glob/list/
# template are passed in, so each test controls exactly one violation.
#   seed_catalogue GLOB TOOL TEMPLATE_KEY
seed_catalogue() {
  local glob="$1" tool="$2" template_key="$3"
  FIXTURE_ROOT="$BATS_TEST_TMPDIR/nexus-fixture"
  mkdir -p "$FIXTURE_ROOT/roster" "$FIXTURE_ROOT/cli/templates/mcp"
  cat > "$FIXTURE_ROOT/roster/mcps.yaml" <<EOF
catalogue_version: "1.2"
updated_at: "2026-06-02T00:00:00Z"
mcps:
  - name: atlas-aci
    display_name: "Atlas-ACI"
    scope: system
    kind: oci-image
    description: "fixture"
    exposes_tools:
      glob: "$glob"
      list:
        - $tool
    source:
      type: ghcr
      image: "ghcr.io/rynaro/atlas-aci"
    versions:
      latest: "0.2.3"
      pins:
        stable: "0.2.3"
    install:
      hosts_wired: [".mcp.json"]
      template: "cli/templates/mcp/atlas-aci.mcp.json.tmpl"
    health:
      probes: [docker_cli]
EOF
  cat > "$FIXTURE_ROOT/cli/templates/mcp/atlas-aci.mcp.json.tmpl" <<EOF
{
  "mcpServers": {
    "$template_key": {
      "command": "docker",
      "args": ["run"]
    }
  }
}
EOF
}

@test "MCL-1: the real roster/mcps.yaml passes the namespace guard" {
  run bash "$CHECKER" "$EIDOLONS_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"catalogue tool namespaces consistent"* ]]
}

@test "MCL-2: underscore glob for a hyphenated server key fails (the historical inert-grant bug)" {
  seed_catalogue "mcp__atlas_aci__*" "mcp__atlas-aci__view_file" "atlas-aci"
  run bash "$CHECKER" "$FIXTURE_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exposes_tools.glob is 'mcp__atlas_aci__*'"* ]]
  [[ "$output" == *"must be 'mcp__atlas-aci__*'"* ]]
}

@test "MCL-3: tool list item outside the mcp__<name>__ namespace fails" {
  seed_catalogue "mcp__atlas-aci__*" "mcp__atlas_aci__view_file" "atlas-aci"
  run bash "$CHECKER" "$FIXTURE_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'mcp__atlas_aci__view_file' does not start with 'mcp__atlas-aci__'"* ]]
}

@test "MCL-4: template registering the server under a different key fails" {
  seed_catalogue "mcp__atlas-aci__*" "mcp__atlas-aci__view_file" "atlas_aci"
  run bash "$CHECKER" "$FIXTURE_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not register a .mcpServers key named 'atlas-aci'"* ]]
}

@test "MCL-5: fully consistent fixture passes" {
  seed_catalogue "mcp__atlas-aci__*" "mcp__atlas-aci__view_file" "atlas-aci"
  run bash "$CHECKER" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
}

@test "MCL-6: missing template file fails" {
  seed_catalogue "mcp__atlas-aci__*" "mcp__atlas-aci__view_file" "atlas-aci"
  rm "$FIXTURE_ROOT/cli/templates/mcp/atlas-aci.mcp.json.tmpl"
  run bash "$CHECKER" "$FIXTURE_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}
