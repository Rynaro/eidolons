#!/usr/bin/env bats
#
# cli/tests/mcp_uid_pin.bats — coverage for the OCI --user UID/GID pin fix
# (fix/mcp-uid-pin-all-oci-servers).
#
# Background: tonberry, atomos, and atlas-aci are distroless OCI images whose
# default in-container user is a fixed non-root UID (65532). Their .mcp.json
# entries bind-mount the host project workspace read-write. Without a
# `--user <host-uid>:<host-gid>` pin, every container write against that
# bind mount fails with EACCES/EPERM even though the host directory is owned
# by the invoking user — this made 'eidolons esl' completely unusable
# (tonberry propose/transition/archive all failed) on any host whose UID is
# not 65532.
#
# This file proves:
#   (a) all three templates render a `--user <uid>:<gid>` pair matching the
#       CURRENT host user (never a hardcoded value) — via the generic
#       _mcp_oci_render_and_merge path (tonberry, atomos) and the dedicated
#       atlas-aci generator script (mcp_atlas_aci.sh).
#   (b) the __UID_GID__ placeholder is present in the templates themselves
#       (a static regression guard — this is what a naive future edit could
#       accidentally drop).
#
# The doctor/mcp-health regression coverage for the SEPARATE
# _mcp_driver_oci_uid_bind_probes()/doctor.sh Check-7b hardcoded-name bug
# (which is what let this defect stay green under 'eidolons doctor' and
# 'eidolons mcp health') lives in cli/tests/doctor.bats (D-T3.9) and
# cli/tests/mcp_health.bats ("NON-atlas-aci server (tonberry)" tests).
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

# ─── Static: __UID_GID__ placeholder present in every workspace-binding template ──

@test "uid-pin template: tonberry.mcp.json.tmpl renders --user __UID_GID__" {
  run grep -A1 -- "--user" "$EIDOLONS_ROOT/cli/templates/mcp/tonberry.mcp.json.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "__UID_GID__" ]]
}

@test "uid-pin template: atomos.mcp.json.tmpl renders --user __UID_GID__" {
  run grep -A1 -- "--user" "$EIDOLONS_ROOT/cli/templates/mcp/atomos.mcp.json.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "__UID_GID__" ]]
}

@test "uid-pin template: atlas-aci.mcp.json.tmpl renders --user __UID_GID__" {
  run grep -A1 -- "--user" "$EIDOLONS_ROOT/cli/templates/mcp/atlas-aci.mcp.json.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "__UID_GID__" ]]
}

# ─── Render: tonberry via the generic _mcp_oci_render_and_merge path ─────────
# tonberry has no dedicated generator script (unlike atlas-aci) — it renders
# through the same _mcp_oci_render_and_merge helper atomos and crystalium use.
# No Docker daemon needed: this helper only does template substitution + jq
# merge, it never shells out to docker.

@test "uid-pin render: tonberry entry contains --user <current uid>:<gid>" {
  local project="$BATS_TEST_TMPDIR/tonberry-project"
  mkdir -p "$project"
  local digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  run bash -c "
    set -euo pipefail
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    export NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'
    _mcp_oci_render_and_merge tonberry '$project' '$digest' 'cli/templates/mcp/tonberry.mcp.json.tmpl'
  "
  [ "$status" -eq 0 ]
  [ -f "$project/.mcp.json" ]

  local cur_uid cur_gid expected
  cur_uid="$(id -u)"
  cur_gid="$(id -g)"
  expected="${cur_uid}:${cur_gid}"

  # No literal placeholder must survive rendering.
  run bash -c "grep -q '__UID_GID__' '$project/.mcp.json'"
  [ "$status" -ne 0 ]

  # The -u value immediately following "-u" in tonberry's args must equal
  # the CURRENT host user's uid:gid — never a hardcoded/stale value.
  local pinned
  pinned="$(jq -r '
    .mcpServers.tonberry.args as $a |
    ($a | indices("--user"))[0] as $i |
    $a[$i + 1]
  ' "$project/.mcp.json")"
  [ "$pinned" = "$expected" ]
}

# ─── Render: atomos via the generic _mcp_oci_render_and_merge path ──────────

@test "uid-pin render: atomos entry contains --user <current uid>:<gid>" {
  local project="$BATS_TEST_TMPDIR/atomos-project"
  mkdir -p "$project"
  local digest="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  run bash -c "
    set -euo pipefail
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    export NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'
    _mcp_oci_render_and_merge atomos '$project' '$digest' 'cli/templates/mcp/atomos.mcp.json.tmpl'
  "
  [ "$status" -eq 0 ]
  [ -f "$project/.mcp.json" ]

  local cur_uid cur_gid expected
  cur_uid="$(id -u)"
  cur_gid="$(id -g)"
  expected="${cur_uid}:${cur_gid}"

  run bash -c "grep -q '__UID_GID__' '$project/.mcp.json'"
  [ "$status" -ne 0 ]

  local pinned
  pinned="$(jq -r '
    .mcpServers.atomos.args as $a |
    ($a | indices("--user"))[0] as $i |
    $a[$i + 1]
  ' "$project/.mcp.json")"
  [ "$pinned" = "$expected" ]
}

# ─── Render: both entries coexist in the same .mcp.json (merge does not clobber) ──

@test "uid-pin render: tonberry + atomos coexist in .mcp.json, both carry the current uid:gid" {
  local project="$BATS_TEST_TMPDIR/coexist-project"
  mkdir -p "$project"
  local digest="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

  run bash -c "
    set -euo pipefail
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    export NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'
    _mcp_oci_render_and_merge tonberry '$project' '$digest' 'cli/templates/mcp/tonberry.mcp.json.tmpl'
    _mcp_oci_render_and_merge atomos '$project' '$digest' 'cli/templates/mcp/atomos.mcp.json.tmpl'
  "
  [ "$status" -eq 0 ]

  local cur_uid cur_gid expected
  cur_uid="$(id -u)"
  cur_gid="$(id -g)"
  expected="${cur_uid}:${cur_gid}"

  run bash -c "jq -e '.mcpServers.tonberry' '$project/.mcp.json'"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcpServers.atomos' '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  local tonberry_pin atomos_pin
  tonberry_pin="$(jq -r '.mcpServers.tonberry.args as $a | ($a | indices("--user"))[0] as $i | $a[$i + 1]' "$project/.mcp.json")"
  atomos_pin="$(jq -r '.mcpServers.atomos.args as $a | ($a | indices("--user"))[0] as $i | $a[$i + 1]' "$project/.mcp.json")"
  [ "$tonberry_pin" = "$expected" ]
  [ "$atomos_pin" = "$expected" ]
}

# ─── Render: atlas-aci via its dedicated generator script (mcp_atlas_aci.sh) ──
# atlas-aci has its own sed pass (a separate render path from
# _mcp_oci_render_and_merge — see mcp_atlas_aci.sh) so it needs its own
# coverage rather than relying on the tonberry/atomos assertions above.
# Mirrors the fake-docker harness from mcp_atlas_aci.bats so no real Docker
# daemon is needed.

_setup_fake_docker_for_uid_pin() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin-uid-pin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
subcmd="${1:-}"
case "$subcmd" in
  info)  exit 0 ;;
  image) exit 0 ;;
  *)     exit 0 ;;
esac
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
}

@test "uid-pin render: atlas-aci entry (via mcp_atlas_aci.sh) contains --user <current uid>:<gid>" {
  _setup_fake_docker_for_uid_pin
  local project="$BATS_TEST_TMPDIR/atlas-aci-uid-project"
  mkdir -p "$project"
  local digest="sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

  run bash "$EIDOLONS_ROOT/cli/src/mcp_atlas_aci.sh" --project-root "$project" --image-digest "$digest"
  [ "$status" -eq 0 ]
  [ -f "$project/.mcp.json" ]

  local cur_uid cur_gid expected
  cur_uid="$(id -u)"
  cur_gid="$(id -g)"
  expected="${cur_uid}:${cur_gid}"

  run bash -c "grep -q '__UID_GID__' '$project/.mcp.json'"
  [ "$status" -ne 0 ]

  local pinned
  pinned="$(jq -r '
    .mcpServers["atlas-aci"].args as $a |
    ($a | indices("--user"))[0] as $i |
    $a[$i + 1]
  ' "$project/.mcp.json")"
  [ "$pinned" = "$expected" ]
}
