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

# Pinned digest for atlas-aci stable (2.0.0). Must track roster/mcps.yaml's
# versions.pins.stable digest — S8 asserts "present at the stable digest ⇒ no drift",
# so a stale value here makes the drift check pass vacuously.
ATLAS_ACI_PINNED="sha256:e2542ef8d569882c560065f0bcaed9ef2a7398e7e61765e25b142a3c93ec7cf7"
# Pinned digest for crystalium stable.
CRYSTALIUM_PINNED="sha256:84d450ed7488ad79ed8f1b56e6a47d92e95d92e4c6de34cc79cc876630cdb3e5"

# ─── Guard: the fixture pin must track the catalogue ──────────────────────

@test "S8-guard: ATLAS_ACI_PINNED tracks roster/mcps.yaml versions.pins.stable" {
  # A hardcoded digest is a proxy for "the catalogue's stable digest". If a version
  # bump edits roster/mcps.yaml but forgets this file, S8 keeps passing — it would be
  # asserting "present at the stable digest ⇒ no drift" against a digest nothing pins
  # any more. Derive it instead of trusting the constant. Pure awk: bash 3.2 safe.
  local blk stable digest
  blk="$(awk '/^  - name: atlas-aci$/,/^  - name: junction$/' "$EIDOLONS_ROOT/roster/mcps.yaml")"
  stable="$(printf '%s\n' "$blk" | awk '/^      pins:/{f=1;next} f&&/stable:/{gsub(/"/,"");print $2;exit}')"
  digest="$(printf '%s\n' "$blk" | awk -v v="\"$stable\":" '$1==v{f=1;next} f&&/digest:/{gsub(/"/,"");print $2;exit}')"
  [ -n "$stable" ]
  [ -n "$digest" ]
  [ "$digest" = "$ATLAS_ACI_PINNED" ]
}

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
  # Make docker truly absent regardless of host: a `rm -f fake-bin/docker`
  # alone leaks a real host docker (which makes PRESENT=yes when an image
  # happens to be pulled locally). Build a PATH mirroring every executable
  # EXCEPT docker, then point PATH at it exclusively. mcp_images resolves the
  # catalogue (yq/jq) before checking docker, so the full toolset is mirrored.
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
  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh"
  PATH="$_saved_path"
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
