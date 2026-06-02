#!/usr/bin/env bats
#
# cli/tests/mcp_pull.bats — tests for 'eidolons mcp pull <name>'.
#
# Covers: S1, S2, S3, S14, S15, E1, E2, E4, E9.
#
# These tests exercise the generic mcp pull subcommand (cli/src/mcp_pull.sh)
# via mcp_driver_oci_image_pull in lib_mcp.sh. Docker is stubbed via the
# inline fake-docker harness pattern from mcp_atlas_aci_pull.bats.
#
# Primary test subject: crystalium (exercises the generic non-atlas-aci path).
# atlas-aci is also tested for --build-locally (S14, P0 path).
#
# Control env-vars read at shim invocation time (not at write time):
#   FAKE_DOCKER_INFO_RESULT            ok (default) / fail
#   FAKE_DOCKER_INSPECT_RESULT         ok / fail (default: fail)
#   FAKE_DOCKER_PULL_RESULT            ok / fail (default: fail)
#   FAKE_DOCKER_INSPECT_AFTER_PULL     ok / fail (optional)
#   FAKE_DOCKER_BUILD_RESULT           ok / fail (default: ok)
#   FAKE_DOCKER_REPODIGEST             string (for image inspect RepoDigest format output)
#   FAKE_DOCKER_SIZE                   string (for image inspect Size format output)
#
# Every docker invocation is logged to $BATS_TEST_TMPDIR/docker.log.
# Bash 3.2 compatible: no associative arrays, no ${var,,}, no readarray.
# See CLAUDE.md §"Bash 3.2 compatibility".

load helpers

# ─── Fake-docker harness ───────────────────────────────────────────────────

setup_fake_docker() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"

  # Write the docker shim. Reads FAKE_DOCKER_* vars at invocation time.
  # Extended with REPODIGEST and SIZE support for mcp images tests.
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
set -u

DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"

INFO_RESULT="${FAKE_DOCKER_INFO_RESULT:-ok}"
INSPECT_RESULT="${FAKE_DOCKER_INSPECT_RESULT:-fail}"
PULL_RESULT="${FAKE_DOCKER_PULL_RESULT:-fail}"
BUILD_RESULT="${FAKE_DOCKER_BUILD_RESULT:-ok}"
INSPECT_AFTER_PULL="${FAKE_DOCKER_INSPECT_AFTER_PULL:-}"
REPODIGEST="${FAKE_DOCKER_REPODIGEST:-}"
SIZE="${FAKE_DOCKER_SIZE:-}"

count_pulls() {
  if [ -f "$DOCKER_LOG" ]; then
    grep -c '^pull ' "$DOCKER_LOG" 2>/dev/null || true
  else
    printf '0'
  fi
}

subcmd="${1:-}"
case "$subcmd" in
  info)
    printf 'info\n' >> "$DOCKER_LOG"
    [ "$INFO_RESULT" = "ok" ] && exit 0 || exit 1
    ;;
  image)
    action="${2:-}"
    ref="${3:-}"
    fmt_arg="${4:-}"
    case "$action" in
      inspect)
        # Handle: docker image inspect [--format 'FMT'] <ref>
        _ifmt=""
        _iref=""
        shift 2  # remove 'image' 'inspect'
        while [ $# -gt 0 ]; do
          case "$1" in
            --format) _ifmt="${2:-}"; shift 2 ;;
            *) _iref="$1"; shift ;;
          esac
        done
        printf 'image inspect %s\n' "$_iref" >> "$DOCKER_LOG"
        _eff_inspect="$INSPECT_RESULT"
        if [ -n "$INSPECT_AFTER_PULL" ] && [ "$(count_pulls)" -ge 1 ]; then
          _eff_inspect="$INSPECT_AFTER_PULL"
        fi
        if [ "$_eff_inspect" = "ok" ]; then
          case "$_ifmt" in
            *RepoDigests*) printf '%s\n' "$REPODIGEST" ;;
            *Size*) printf '%s\n' "$SIZE" ;;
          esac
          exit 0
        else
          exit 1
        fi
        ;;
      *)
        printf 'image %s\n' "$action" >> "$DOCKER_LOG"
        exit 0
        ;;
    esac
    ;;
  pull)
    ref="${2:-}"
    printf 'pull %s\n' "$ref" >> "$DOCKER_LOG"
    [ "$PULL_RESULT" = "ok" ] && exit 0 || exit 1
    ;;
  build)
    printf 'build %s\n' "$*" >> "$DOCKER_LOG"
    [ "$BUILD_RESULT" = "ok" ] && exit 0 || exit 1
    ;;
  *)
    printf '%s\n' "$*" >> "$DOCKER_LOG"
    exit 0
    ;;
esac
SHIM

  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
  export BATS_TEST_TMPDIR
}

# File-level setup.
setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  mkdir -p "$EIDOLONS_HOME"
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"

  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=fail
  export FAKE_DOCKER_BUILD_RESULT=ok
  unset FAKE_DOCKER_INSPECT_AFTER_PULL || true
  unset FAKE_DOCKER_REPODIGEST || true
  unset FAKE_DOCKER_SIZE || true

  setup_fake_docker
}

teardown() {
  cd "$EIDOLONS_ROOT"
}

# Test digest for crystalium pinned stable.
CRYSTALIUM_DIGEST="sha256:84d450ed7488ad79ed8f1b56e6a47d92e95d92e4c6de34cc79cc876630cdb3e5"
ATLAS_ACI_DIGEST="sha256:386677f06b0ce23cb4883f6c0f91d8eac22328cd7d9451ae241e2f183207ad96"

# ─── S1: image already present (idempotent no-op) ──────────────────────────

@test "S1 mcp pull crystalium: image already present → exit 0, no docker pull, stderr says already present" {
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" crystalium

  [ "$status" -eq 0 ]
  [[ "$output" =~ "already present" ]]

  local log="$BATS_TEST_TMPDIR/docker.log"
  run grep -q '^pull ' "$log" 2>/dev/null || true
  [ "$status" -ne 0 ]
}

# ─── S2: image missing, pull succeeds ─────────────────────────────────────

@test "S2 mcp pull crystalium: image absent + pull succeeds → exit 0, pull line in docker.log" {
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=ok
  export FAKE_DOCKER_INSPECT_AFTER_PULL=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" crystalium

  [ "$status" -eq 0 ]
  [[ "$output" =~ "pulled and verified" ]]

  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
  run grep -c '^pull ' "$log"
  [ "$output" -ge 1 ]
}

# ─── S3: offline + not buildable (crystalium has no source.build) ─────────

@test "S3 mcp pull crystalium: offline + not buildable → exit 1, fallback WITHOUT --build-locally line" {
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=fail

  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" crystalium

  [ "$status" -eq 1 ]

  local pull_output="$output"

  # Must NOT list --build-locally as an alternative (crystalium is pull-only).
  run grep -q "build-locally" <<< "$pull_output"
  [ "$status" -ne 0 ]

  # Must list the tarball alternative.
  run grep -q "docker load -i" <<< "$pull_output"
  [ "$status" -eq 0 ]

  # Must list the private mirror alternative.
  run grep -q "docker pull <registry>" <<< "$pull_output"
  [ "$status" -eq 0 ]
}

# ─── E1: Docker CLI absent ────────────────────────────────────────────────

@test "E1 mcp pull: docker CLI absent → exit 1, actionable message" {
  # Simulate "docker not installed" robustly on every runner (including hosts
  # where a real docker exists, e.g. /usr/local/bin): build a PATH that mirrors
  # every executable currently on PATH EXCEPT docker, then point PATH at it
  # exclusively. command -v docker then finds nothing regardless of host.
  # (The generic pull resolves the catalogue before the docker check, so the
  # restricted PATH must still carry yq/jq/sed/etc. — hence the symlink farm.)
  local nodoc="$BATS_TEST_TMPDIR/nodoc-bin"
  mkdir -p "$nodoc"
  local _dirs d f b
  IFS=':' read -ra _dirs <<< "$PATH"
  for d in "${_dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -e "$f" ] || continue
      b="$(basename "$f")"
      [ "$b" = "docker" ] && continue
      [ -e "$nodoc/$b" ] || ln -s "$f" "$nodoc/$b" 2>/dev/null || true
    done
  done

  local _saved_path="$PATH"
  PATH="$nodoc"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" crystalium
  PATH="$_saved_path"

  [ "$status" -ne 0 ]
  [[ "$output" =~ "not installed" ]]
}

# ─── E2: Docker daemon down ───────────────────────────────────────────────

@test "E2 mcp pull: docker daemon down → exit 1, no pull invoked" {
  export FAKE_DOCKER_INFO_RESULT=fail
  export FAKE_DOCKER_INSPECT_RESULT=ok
  export FAKE_DOCKER_PULL_RESULT=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" crystalium

  [ "$status" -eq 1 ]
  [[ "$output" =~ "daemon" ]]

  local log="$BATS_TEST_TMPDIR/docker.log"
  if [ -f "$log" ]; then
    run grep -q '^pull ' "$log"
    [ "$status" -ne 0 ]
  fi
}

# ─── E9: bootstrap-placeholder digest, no override ────────────────────────

@test "E9 mcp pull: bootstrap-placeholder digest → exit 2 with guard message" {
  # Use a mocked catalogue with a placeholder digest.
  # We can do this by testing the driver directly with a fake catalogue.
  # For this, we override the catalogue to contain a placeholder digest for crystalium.
  # The CLI reads the catalogue from $NEXUS/roster/mcps.yaml — write the fake
  # there and point EIDOLONS_NEXUS at this tmp dir (libs still load from the
  # script's own dir, so only the catalogue is overridden).
  mkdir -p "$BATS_TEST_TMPDIR/roster"
  local fake_cat="$BATS_TEST_TMPDIR/roster/mcps.yaml"
  cat > "$fake_cat" <<'EOF'
catalogue_version: "1.2"
updated_at: "2026-06-02T00:00:00Z"
mcps:
  - name: crystalium
    display_name: "CRYSTALIUM"
    scope: system
    kind: oci-image
    description: "Test"
    source:
      type: ghcr
      image: "ghcr.io/rynaro/crystalium"
    versions:
      latest: "1.0.0"
      pins:
        stable: "1.0.0"
      releases:
        "1.0.0":
          digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000"
          released_at: "2026-06-02T00:00:00Z"
    install:
      template: "cli/templates/mcp/crystalium.mcp.json.tmpl"
    health:
      probes:
        - docker_cli
EOF

  EIDOLONS_NEXUS="$BATS_TEST_TMPDIR" run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" crystalium

  [ "$status" -eq 2 ]
  [[ "$output" =~ "bootstrap placeholder" ]] || [[ "$output" =~ "placeholder" ]]
}

# ─── S14: --build-locally gating ──────────────────────────────────────────

@test "S14a mcp pull crystalium --build-locally: exit 2, 'does not declare a buildable source'" {
  export FAKE_DOCKER_INFO_RESULT=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" crystalium --build-locally

  [ "$status" -eq 2 ]
  [[ "$output" =~ "buildable source" ]]
}

@test "S14b mcp pull atlas-aci --build-locally: invokes docker build (P0 path preserved)" {
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_BUILD_RESULT=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" atlas-aci --build-locally

  [ "$status" -eq 0 ]

  local pull_output="$output"

  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
  run grep -E '^build .*atlas-aci\.git#.*:mcp-server' "$log"
  [ "$status" -eq 0 ]

  # Warn about digest-mismatch tradeoff.
  run grep -q "cannot match" <<< "$pull_output"
  [ "$status" -eq 0 ]
}

# ─── S15: wrong kind / bad usage ─────────────────────────────────────────

@test "S15a mcp pull junction: exit 2 (wrong kind)" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" junction

  [ "$status" -eq 2 ]
  [[ "$output" =~ "oci-image" ]]
}

@test "S15b mcp pull nonexistent: exit 2 (not found in catalogue)" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" no-such-mcp

  [ "$status" -eq 2 ]
  [[ "$output" =~ "not found" ]]
}

@test "S15c mcp pull atlas-aci --git-ref foo (no --build-locally): exit 2" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" atlas-aci --git-ref main

  [ "$status" -eq 2 ]
  [[ "$output" =~ "--build-locally" ]]
}

@test "mcp pull: no args → exit 2, usage on stderr" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh"
  [ "$status" -eq 2 ]
}

@test "mcp pull: --help exits 0" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" --help
  [ "$status" -eq 0 ]
}

@test "mcp pull: --image-digest override honored (pull uses override digest)" {
  local custom_digest="sha256:1111111111111111111111111111111111111111111111111111111111111111"

  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=fail

  run bash "$EIDOLONS_ROOT/cli/src/mcp_pull.sh" crystalium --image-digest "$custom_digest"

  # Pull fails but we care that the custom ref was used.
  [ "$status" -eq 1 ]

  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
  run grep "ghcr.io/rynaro/crystalium@${custom_digest}" "$log"
  [ "$status" -eq 0 ]
}
