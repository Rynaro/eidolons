#!/usr/bin/env bats
#
# cli/tests/mcp_refresh.bats — coverage for 'eidolons mcp refresh' (F2.3 stories S10-S11).
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

FAKE_JUNCTION_VERSION="0.2.0"

setup_fake_curl_and_gh_for_refresh() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/curl" <<'CURL'
#!/usr/bin/env bash
cat <<'INSTALLER'
#!/usr/bin/env bash
DEST="${JUNCTION_INSTALL_DIR:-/usr/local/bin}"
mkdir -p "$DEST"
cat > "$DEST/junction" <<'JBIN'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then echo "junction 0.2.0"; exit 0; fi
echo "stub: $*"
JBIN
chmod +x "$DEST/junction"
INSTALLER
CURL
  chmod +x "$fake_bin/curl"
  cat > "$fake_bin/gh" <<GHSCRIPT
#!/usr/bin/env bash
echo "v${FAKE_JUNCTION_VERSION}"
GHSCRIPT
  chmod +x "$fake_bin/gh"
  export PATH="$fake_bin:$PATH"
}

# Seed a minimal junction lockfile entry with a known installed_at.
seed_junction_lock_for_refresh() {
  local ver="${1:-$FAKE_JUNCTION_VERSION}"
  local cache_dir="$EIDOLONS_HOME/cache/junction@${ver}"
  mkdir -p "$cache_dir"
  cat > "$cache_dir/junction" <<'JSTUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then echo "junction 0.2.0"; exit 0; fi
echo "stub: $*"
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
    installed_at: "2026-05-01T00:00:00Z"
EOF
}

@test "mcp refresh: help exits 0" {
  run eidolons mcp refresh --help
  [ "$status" -eq 0 ]
}

@test "mcp refresh: no args exits 2" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons mcp refresh
  [ "$status" -eq 2 ]
}

@test "mcp refresh: unknown MCP exits 1" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons mcp refresh no-such-mcp
  [ "$status" -eq 1 ]
}

@test "mcp refresh S10: re-fetch binary (junction) succeeds" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_refresh
  seed_junction_lock_for_refresh
  run bash "$EIDOLONS_ROOT/cli/src/mcp_refresh.sh" "junction"
  [ "$status" -eq 0 ]
}

@test "mcp refresh S11: lockfile still valid after refresh" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_refresh
  seed_junction_lock_for_refresh
  run bash "$EIDOLONS_ROOT/cli/src/mcp_refresh.sh" "junction"
  [ "$status" -eq 0 ]
  [ -f "eidolons.mcp.lock" ]
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' && yaml_to_json eidolons.mcp.lock | jq '.mcps | length'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ─── Crystalium refresh via generic driver ────────────────────────────────

setup_fake_docker_for_refresh() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
INFO_RESULT="${FAKE_DOCKER_INFO_RESULT:-ok}"
INSPECT_RESULT="${FAKE_DOCKER_INSPECT_RESULT:-ok}"
PULL_RESULT="${FAKE_DOCKER_PULL_RESULT:-ok}"
INSPECT_AFTER_PULL="${FAKE_DOCKER_INSPECT_AFTER_PULL:-}"

count_pulls() {
  if [ -f "$DOCKER_LOG" ]; then
    grep -c '^pull ' "$DOCKER_LOG" 2>/dev/null || true
  else
    printf '0'
  fi
}

subcmd="${1:-}"
case "$subcmd" in
  info) [ "$INFO_RESULT" = "ok" ] && exit 0 || exit 1 ;;
  image)
    action="${2:-}"
    case "$action" in
      inspect)
        _eff="$INSPECT_RESULT"
        if [ -n "$INSPECT_AFTER_PULL" ] && [ "$(count_pulls)" -ge 1 ]; then
          _eff="$INSPECT_AFTER_PULL"
        fi
        shift 2
        _iref=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --format) shift 2 ;;
            *) _iref="$1"; shift ;;
          esac
        done
        printf 'image inspect %s\n' "$_iref" >> "$DOCKER_LOG"
        [ "$_eff" = "ok" ] && exit 0 || exit 1
        ;;
      *) exit 0 ;;
    esac
    ;;
  pull)
    printf 'pull %s\n' "${2:-}" >> "$DOCKER_LOG"
    [ "$PULL_RESULT" = "ok" ] && exit 0 || exit 1
    ;;
  *) exit 0 ;;
esac
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
  export BATS_TEST_TMPDIR
}

seed_crystalium_lock_for_refresh() {
  local digest="sha256:84d450ed7488ad79ed8f1b56e6a47d92e95d92e4c6de34cc79cc876630cdb3e5"
  cat > eidolons.mcp.lock <<EOF
# eidolons.mcp.lock
generated_at: "2026-05-19T00:00:00Z"
eidolons_cli_version: "1.3.0"
catalogue_version: "1.2"
mcps:
  - name: crystalium
    kind: oci-image
    version: "1.2.0"
    source:
      image: "ghcr.io/rynaro/crystalium"
    integrity:
      algo: oci-digest
      value: "${digest}"
    target: ".mcp.json"
    hosts_wired:
      - ".mcp.json"
    installed_at: "2026-05-01T00:00:00Z"
EOF
}

@test "mcp refresh crystalium: routes through generic pull driver (not atlas-aci hardcode)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_refresh
  seed_crystalium_lock_for_refresh

  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_refresh.sh" crystalium
  [ "$status" -eq 0 ]

  # Lockfile must still be valid.
  [ -f "eidolons.mcp.lock" ]
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' && yaml_to_json eidolons.mcp.lock | jq '.mcps | length'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "mcp refresh crystalium: --image-digest override routes through generic driver" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_refresh
  seed_crystalium_lock_for_refresh

  local override_digest="sha256:1111111111111111111111111111111111111111111111111111111111111111"
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_refresh.sh" crystalium --image-digest "$override_digest"
  [ "$status" -eq 0 ]

  # Lockfile must be updated.
  [ -f "eidolons.mcp.lock" ]
}
