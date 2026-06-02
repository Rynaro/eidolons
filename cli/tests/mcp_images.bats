#!/usr/bin/env bats
#
# cli/tests/mcp_images.bats — tests for 'eidolons mcp images'.
#
# Covers: S8, S9, S10, S11, S12, E5, E6.
#
# Uses an inline fake-docker harness (per-file convention, do NOT lift to
# helpers.bash). Extended with REPODIGEST and SIZE support for drift detection.
#
# Control env-vars read at shim invocation time:
#   FAKE_DOCKER_INFO_RESULT            ok (default) / fail
#   FAKE_DOCKER_INSPECT_RESULT         ok / fail (default: ok — images tests
#                                      usually want docker present with images)
#   FAKE_DOCKER_REPODIGEST             string returned by 'image inspect --format
#                                      {{index .RepoDigests 0}}'
#   FAKE_DOCKER_SIZE                   string returned by 'image inspect --format
#                                      {{.Size}}'
#
# Bash 3.2 compatible: no associative arrays, no ${var,,}, no readarray.
# See CLAUDE.md §"Bash 3.2 compatibility".

load helpers

# ─── Fake-docker harness ───────────────────────────────────────────────────

setup_fake_docker() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"

  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
set -u

DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"

INFO_RESULT="${FAKE_DOCKER_INFO_RESULT:-ok}"
INSPECT_RESULT="${FAKE_DOCKER_INSPECT_RESULT:-ok}"
REPODIGEST="${FAKE_DOCKER_REPODIGEST:-}"
SIZE="${FAKE_DOCKER_SIZE:-}"

subcmd="${1:-}"
case "$subcmd" in
  info)
    printf 'info\n' >> "$DOCKER_LOG"
    [ "$INFO_RESULT" = "ok" ] && exit 0 || exit 1
    ;;
  image)
    action="${2:-}"
    case "$action" in
      inspect)
        _ifmt=""
        _iref=""
        shift 2
        while [ $# -gt 0 ]; do
          case "$1" in
            --format) _ifmt="${2:-}"; shift 2 ;;
            *) _iref="$1"; shift ;;
          esac
        done
        printf 'image inspect %s\n' "$_iref" >> "$DOCKER_LOG"
        if [ "$INSPECT_RESULT" = "ok" ]; then
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
    printf 'pull %s\n' "${2:-}" >> "$DOCKER_LOG"
    exit 0
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

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  mkdir -p "$EIDOLONS_HOME"
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"

  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok
  unset FAKE_DOCKER_REPODIGEST || true
  unset FAKE_DOCKER_SIZE || true

  setup_fake_docker
}

teardown() {
  cd "$EIDOLONS_ROOT"
}

# Pinned digest for atlas-aci stable.
ATLAS_ACI_PINNED="sha256:386677f06b0ce23cb4883f6c0f91d8eac22328cd7d9451ae241e2f183207ad96"
# Pinned digest for crystalium stable.
CRYSTALIUM_PINNED="sha256:84d450ed7488ad79ed8f1b56e6a47d92e95d92e4c6de34cc79cc876630cdb3e5"

# ─── Basic invocation ─────────────────────────────────────────────────────

@test "mcp images: --help exits 0" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh" --help
  [ "$status" -eq 0 ]
}

@test "mcp images: unknown option exits 2" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh" --unknown
  [ "$status" -eq 2 ]
}

@test "mcp images: always exits 0 even with docker present" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh"
  [ "$status" -eq 0 ]
}

# ─── Table header always printed ─────────────────────────────────────────

@test "mcp images: table header always printed" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NAME" ]]
  [[ "$output" =~ "PRESENT" ]]
  [[ "$output" =~ "DRIFT" ]]
}

# ─── E6: Multiple OCI MCPs listed; junction NOT listed ───────────────────

@test "E6 mcp images: lists atlas-aci and crystalium, omits junction" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh"
  [ "$status" -eq 0 ]

  [[ "$output" =~ "atlas-aci" ]]
  [[ "$output" =~ "crystalium" ]]

  # Junction (binary kind) must NOT appear as a data row.
  # It appears in the wider output only as part of the header/separator, not as a row.
  # We check that the word "junction" does not appear as a table row.
  run grep -c '^junction' <<< "$output" || true
  [ "${output:-0}" -eq 0 ]
}

# ─── S8: present + no drift ───────────────────────────────────────────────

@test "S8 mcp images: atlas-aci present at pinned digest → PRESENT=yes, DRIFT=no" {
  # Simulate: inspect succeeds, RepoDigest == pinned digest.
  export FAKE_DOCKER_INSPECT_RESULT=ok
  export FAKE_DOCKER_REPODIGEST="ghcr.io/rynaro/atlas-aci@${ATLAS_ACI_PINNED}"
  export FAKE_DOCKER_SIZE="431000000"

  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh"
  [ "$status" -eq 0 ]

  local img_output="$output"
  run grep "atlas-aci" <<< "$img_output"
  [ "$status" -eq 0 ]

  # PRESENT=yes and DRIFT=no in the atlas-aci row.
  run grep -E "atlas-aci.*yes" <<< "$img_output"
  [ "$status" -eq 0 ]

  run grep -E "atlas-aci.*no" <<< "$img_output"
  [ "$status" -eq 0 ]
}

# ─── S9: drift (local != pinned) ──────────────────────────────────────────

@test "S9 mcp images: crystalium present at different digest → DRIFT=yes" {
  # Simulate: inspect succeeds, but RepoDigest is a different (stale) digest.
  local stale_digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  export FAKE_DOCKER_INSPECT_RESULT=ok
  export FAKE_DOCKER_REPODIGEST="ghcr.io/rynaro/crystalium@${stale_digest}"
  export FAKE_DOCKER_SIZE="100000000"

  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh"
  [ "$status" -eq 0 ]

  local img_output="$output"
  run grep -E "crystalium.*yes" <<< "$img_output"
  [ "$status" -eq 0 ]
}

# ─── S10: missing image ───────────────────────────────────────────────────

@test "S10 mcp images: crystalium image absent → PRESENT=no, DRIFT=unknown" {
  export FAKE_DOCKER_INSPECT_RESULT=fail

  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh"
  [ "$status" -eq 0 ]

  local img_output="$output"
  run grep -E "crystalium.*no " <<< "$img_output"
  [ "$status" -eq 0 ]
}

# ─── S11: docker absent ───────────────────────────────────────────────────

@test "S11 mcp images: docker not on PATH → exit 0, PRESENT=(n/a), junction NOT listed" {
  # Remove fake docker so docker is not on PATH.
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  rm -f "$fake_bin/docker"

  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh"
  [ "$status" -eq 0 ]

  local img_output="$output"
  # OCI MCP rows should show (n/a) or unknown.
  run grep -E "\(n/a\)|unknown" <<< "$img_output"
  [ "$status" -eq 0 ]

  # Junction must NOT appear as a data row.
  run grep -c '^junction' <<< "$img_output" || true
  [ "${output:-0}" -eq 0 ]
}

# ─── S12: --json valid array, junction absent ─────────────────────────────

@test "S12 mcp images --json: valid JSON array, one object per oci-image MCP, junction absent" {
  export FAKE_DOCKER_INSPECT_RESULT=ok
  export FAKE_DOCKER_REPODIGEST="ghcr.io/rynaro/atlas-aci@${ATLAS_ACI_PINNED}"
  export FAKE_DOCKER_SIZE="431000000"

  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh" --json

  [ "$status" -eq 0 ]

  local json_output="$output"

  # stdout must be valid JSON array.
  run jq -e 'type == "array"' <<< "$json_output"
  [ "$status" -eq 0 ]

  # Every element has the expected keys.
  run jq -e '.[0] | has("name") and has("image") and has("present") and has("drift")' <<< "$json_output"
  [ "$status" -eq 0 ]

  # junction must not appear in the array.
  run jq -e '[.[].name] | contains(["junction"]) | not' <<< "$json_output"
  [ "$status" -eq 0 ]
}

@test "mcp images --json: docker absent → valid JSON array, exit 0" {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  rm -f "$fake_bin/docker"

  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh" --json

  [ "$status" -eq 0 ]

  local json_output="$output"

  # Must be parseable JSON array.
  run jq -e 'type == "array"' <<< "$json_output"
  [ "$status" -eq 0 ]
}
