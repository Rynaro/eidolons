#!/usr/bin/env bats
#
# mcp_atlas_aci_pull.bats — tests for cli/src/mcp_atlas_aci_pull.sh.
#
# These tests exercise the 'eidolons mcp atlas-aci pull' subcommand directly
# (not via the CLI dispatcher) so no running Docker daemon is needed. The
# fake-docker harness is inlined here — same pattern as mcp_atlas_aci.bats
# (T5), scoped to this file to keep the diff bounded.
#
# Decision (per task prompt): T5 inlined the fake-docker harness inside
# mcp_atlas_aci.bats rather than lifting to helpers.bash. This file follows
# the same convention: the harness is copied and extended here. No shared
# mutation of helpers.bash.
#
# Harness additions over mcp_atlas_aci.bats:
#   FAKE_DOCKER_INSPECT_AFTER_PULL  (ok|fail, optional)
#     When set, the shim checks how many 'pull' lines are in docker.log.
#     If >= 1, inspect returns AFTER_PULL result; else returns the base
#     FAKE_DOCKER_INSPECT_RESULT. Lets you simulate "image absent before
#     pull, present after pull".
#
# Control env-vars read at shim invocation time (not at write time):
#   FAKE_DOCKER_INFO_RESULT            ok (default) / fail
#   FAKE_DOCKER_INSPECT_RESULT         ok / fail (default fail — pull tests
#                                      that want "already present" must
#                                      override to ok)
#   FAKE_DOCKER_PULL_RESULT            ok / fail (default fail)
#   FAKE_DOCKER_INSPECT_AFTER_PULL     ok / fail (optional; see above)
#
# Every docker invocation is logged to $BATS_TEST_TMPDIR/docker.log,
# one line per invocation (e.g. "info", "image inspect <ref>", "pull <ref>").
#
# Bash 3.2 compatible: no associative arrays, no ${var,,}, no readarray.
# See CLAUDE.md §"Bash 3.2 compatibility".

load helpers

# ─── Fake-docker harness ───────────────────────────────────────────────────

setup_fake_docker() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"

  # Write the docker shim. Uses only POSIX sh / bash 3.2 features.
  # CRITICAL: the shim reads FAKE_DOCKER_* vars at invocation time (not at
  # write time) so tests can override them after setup() and the shim
  # honours the new values on its next invocation.
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
# Fake docker shim — controlled by FAKE_DOCKER_* env vars.
# Logs every invocation to $BATS_TEST_TMPDIR/docker.log.
# Extended for T7/T9: tracks 'build' invocations via FAKE_DOCKER_BUILD_RESULT.
set -u

DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"

# Default control vars (safe values for the happy path).
INFO_RESULT="${FAKE_DOCKER_INFO_RESULT:-ok}"
INSPECT_RESULT="${FAKE_DOCKER_INSPECT_RESULT:-fail}"
PULL_RESULT="${FAKE_DOCKER_PULL_RESULT:-fail}"
BUILD_RESULT="${FAKE_DOCKER_BUILD_RESULT:-ok}"
INSPECT_AFTER_PULL="${FAKE_DOCKER_INSPECT_AFTER_PULL:-}"

# Helper: count how many 'pull' lines are already in the log.
count_pulls() {
  if [ -f "$DOCKER_LOG" ]; then
    grep -c '^pull ' "$DOCKER_LOG" 2>/dev/null || true
  else
    printf '0'
  fi
}

# Dispatch on the sub-command.
subcmd="${1:-}"
case "$subcmd" in
  info)
    printf 'info\n' >> "$DOCKER_LOG"
    if [ "$INFO_RESULT" = "ok" ]; then
      exit 0
    else
      exit 1
    fi
    ;;
  image)
    action="${2:-}"
    ref="${3:-}"
    case "$action" in
      inspect)
        printf 'image inspect %s\n' "$ref" >> "$DOCKER_LOG"
        # Determine effective inspect result: if AFTER_PULL is set and at
        # least one pull has already been logged, use AFTER_PULL result.
        effective_inspect="$INSPECT_RESULT"
        if [ -n "$INSPECT_AFTER_PULL" ] && [ "$(count_pulls)" -ge 1 ]; then
          effective_inspect="$INSPECT_AFTER_PULL"
        fi
        if [ "$effective_inspect" = "ok" ]; then
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
    if [ "$PULL_RESULT" = "ok" ]; then
      exit 0
    else
      exit 1
    fi
    ;;
  build)
    # Log all arguments so tests can assert on the build URL and tag.
    printf 'build %s\n' "$*" >> "$DOCKER_LOG"
    if [ "$BUILD_RESULT" = "ok" ]; then
      exit 0
    else
      exit 1
    fi
    ;;
  *)
    printf '%s\n' "$*" >> "$DOCKER_LOG"
    exit 0
    ;;
esac
SHIM

  chmod +x "$fake_bin/docker"

  # Prepend fake-bin to PATH so the pull script finds our shim first.
  export PATH="$fake_bin:$PATH"
  export BATS_TEST_TMPDIR
}

# File-level setup: runs before every @test.
setup() {
  # Establish EIDOLONS_NEXUS, EIDOLONS_HOME, and a tmp project dir — same
  # pattern as mcp_atlas_aci.bats.
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  mkdir -p "$EIDOLONS_HOME"
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"

  # Defaults for the fake-docker shim.
  # INSPECT_RESULT defaults to fail so pull tests that want "already present"
  # must explicitly override to ok. AFTER_PULL is unset by default.
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=fail
  export FAKE_DOCKER_BUILD_RESULT=ok
  unset FAKE_DOCKER_INSPECT_AFTER_PULL

  setup_fake_docker
}

teardown() {
  cd "$EIDOLONS_ROOT"
}

# ─── Helper: invoke the pull script directly ──────────────────────────────
# We invoke cli/src/mcp_atlas_aci_pull.sh directly (bypassing cli/eidolons)
# so the test does not depend on the dispatcher wiring from T7.
#
# A non-placeholder test digest is always injected (unless the caller already
# passes --image-digest or --build-locally) so existing tests continue to
# exercise pull logic without triggering the bootstrap-digest guard (H2).
# Tests that specifically test the bootstrap guard must call the script
# directly with bash without --image-digest to trigger IMAGE_DIGEST_EXPLICIT=false.
TEST_IMAGE_DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

run_pull() {
  # Inject TEST_IMAGE_DIGEST unless the caller already supplies --image-digest
  # or --build-locally (the latter also bypasses the bootstrap guard).
  local _has_digest=false _has_build=false _arg
  for _arg in "$@"; do
    case "$_arg" in
      --image-digest) _has_digest=true ;;
      --build-locally) _has_build=true ;;
    esac
  done
  if [ "$_has_digest" = "false" ] && [ "$_has_build" = "false" ]; then
    run bash "$EIDOLONS_ROOT/cli/src/mcp_atlas_aci_pull.sh" --image-digest "$TEST_IMAGE_DIGEST" "$@"
  else
    run bash "$EIDOLONS_ROOT/cli/src/mcp_atlas_aci_pull.sh" "$@"
  fi
}

# ─── Case 1: image already present ────────────────────────────────────────
@test "pull: image already present → exits 0, no docker pull invoked, stderr says already present" {
  # Override: image inspect succeeds immediately — the image is in the local
  # store; the pull sequence should exit 0 without invoking docker pull.
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok

  run_pull

  # Must succeed.
  [ "$status" -eq 0 ]

  # stderr (captured in $output by bats 'run') must mention "already present".
  [[ "$output" =~ "already present" ]]

  # docker.log must NOT contain any 'pull' line — docker pull was not called.
  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
  # Use grep -q with negation: true if NO pull line exists.
  run grep -q '^pull ' "$log"
  [ "$status" -ne 0 ]
}

# ─── Case 2: image absent + pull succeeds ─────────────────────────────────
@test "pull: image absent + pull succeeds → exits 0, docker.log contains pull line" {
  # Pre-pull inspect fails (image absent); pull returns ok; post-pull inspect
  # returns ok (simulated via FAKE_DOCKER_INSPECT_AFTER_PULL).
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=ok
  export FAKE_DOCKER_INSPECT_AFTER_PULL=ok

  run_pull

  # Must succeed.
  [ "$status" -eq 0 ]

  # stderr must confirm the image was pulled and verified.
  [[ "$output" =~ "pulled and verified" ]]

  # docker.log must contain a 'pull <ref>' line.
  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
  run grep -c '^pull ' "$log"
  [ "$output" -ge 1 ]
}

# ─── Case 3: image absent + pull fails ────────────────────────────────────
@test "pull: image absent + pull fails → exits 1, stderr contains all three alternatives" {
  # Both inspect and pull fail — the three-alternatives block must appear.
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=fail

  run_pull

  # Must fail.
  [ "$status" -eq 1 ]

  # Save output before nested 'run' calls (each 'run' overwrites $output).
  local pull_output="$output"

  # stderr must list alternative #1 as --build-locally (T8: GHCR is now the
  # default; --build-locally is the promoted escape hatch in the fallback block).
  run grep -q "build-locally" <<< "$pull_output"
  [ "$status" -eq 0 ]

  # stderr must list alternative #2: load from tarball.
  run grep -q "docker load -i" <<< "$pull_output"
  [ "$status" -eq 0 ]

  # stderr must list alternative #3: pull from a private registry.
  run grep -q "docker pull <registry>/atlas-aci" <<< "$pull_output"
  [ "$status" -eq 0 ]
}

# ─── Case 4: docker daemon down ───────────────────────────────────────────
@test "pull: docker daemon down → exits 1, stderr names daemon, no pull invoked" {
  # Docker CLI is present but docker info fails — daemon is down.
  export FAKE_DOCKER_INFO_RESULT=fail
  # Inspect and pull would succeed if reached, but they must NOT be called
  # because the daemon check gates further execution.
  export FAKE_DOCKER_INSPECT_RESULT=ok
  export FAKE_DOCKER_PULL_RESULT=ok

  run_pull

  # Must fail.
  [ "$status" -eq 1 ]

  # stderr must mention the daemon (from atlas_aci_check_docker_daemon in
  # cli/src/lib_mcp_atlas_aci.sh).
  [[ "$output" =~ "Docker daemon" ]]

  # docker.log must NOT contain any 'pull' line — daemon check fired first.
  local log="$BATS_TEST_TMPDIR/docker.log"
  # If the log file exists, assert no pull line is present.
  # If it does not exist at all, docker was never invoked past 'info' — also fine.
  if [ -f "$log" ]; then
    run grep -q '^pull ' "$log"
    [ "$status" -ne 0 ]
  fi
}

# ─── Case 5: --image-digest override is honored ───────────────────────────
@test "pull: --image-digest override is honored — docker.log contains inspect for the override ref" {
  # The custom digest must appear in the docker.log 'image inspect' line,
  # not the script's default digest. We set inspect to fail so the script
  # calls docker pull (which also uses the override ref) and then exits 1
  # with the three-alternatives block — the exact inspect ref is what we
  # care about.
  local custom_digest="sha256:1111111111111111111111111111111111111111111111111111111111111111"
  local custom_ref="ghcr.io/rynaro/atlas-aci@${custom_digest}"

  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=fail

  run_pull --image-digest "$custom_digest"

  # The command exits 1 (pull fails), but that is expected — we care about
  # what refs were used, not the exit code here.
  [ "$status" -eq 1 ]

  # docker.log must contain an 'image inspect' line referencing the override.
  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
  run grep "image inspect ${custom_ref}" "$log"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# T7/T8 tests — GHCR happy path + --build-locally flag
# ═══════════════════════════════════════════════════════════════════════════

# ─── Case 6: GHCR happy path ──────────────────────────────────────────────
@test "pull: GHCR happy path → exits 0, success message on stderr" {
  # pull succeeds; post-pull inspect returns ok via INSPECT_AFTER_PULL.
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=ok
  export FAKE_DOCKER_INSPECT_AFTER_PULL=ok

  run_pull

  [ "$status" -eq 0 ]

  # Save output before nested 'run' calls (each 'run' overwrites $output).
  local pull_output="$output"

  # stderr must confirm the image was pulled and verified.
  run grep -q "pulled and verified" <<< "$pull_output"
  [ "$status" -eq 0 ]

  # Success message must mention the registry-prefixed ref.
  run grep -q "ghcr.io/rynaro/atlas-aci" <<< "$pull_output"
  [ "$status" -eq 0 ]
}

# ─── Case 7: pull failure shows --build-locally as alternative #1 ─────────
@test "pull: GHCR pull failure → exits 1, fallback block lists --build-locally as alt #1" {
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=fail

  run_pull

  [ "$status" -eq 1 ]

  # Save output before nested 'run' calls (each 'run' overwrites $output).
  local pull_output="$output"

  # Alternative #1 in the fallback block must be --build-locally (T8 promotion).
  run grep -q "build-locally" <<< "$pull_output"
  [ "$status" -eq 0 ]

  # Must NOT show the old "git clone ... docker build -t atlas-aci" manual steps.
  run grep -q "git clone" <<< "$pull_output"
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# T9 — P0 invariant test — --build-locally code path is non-removable
# ═══════════════════════════════════════════════════════════════════════════

# ─── Case 8: --build-locally invokes docker build (P0 invariant — local-build path is non-removable) ─
@test "pull --build-locally: invokes docker build (P0 invariant — local-build path is non-removable)" {
  # P0 invariant: this test asserts the --build-locally escape hatch exists
  # and actually invokes 'docker build' against the atlas-aci git URL.
  # If a future contributor removes the --build-locally handler, this test
  # will fail loudly, surfacing "P0 invariant" in the CI diff.
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_BUILD_RESULT=ok

  run_pull --build-locally

  [ "$status" -eq 0 ]

  # Save output before nested 'run' calls (each 'run' overwrites $output).
  local pull_output="$output"

  # docker.log must contain a 'build' line that references the atlas-aci git URL
  # with the mcp-server context path — this is the canonical build invocation.
  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
  run grep -E '^build .*atlas-aci\.git#.*:mcp-server' "$log"
  [ "$status" -eq 0 ]

  # stderr must warn about the digest-mismatch trade-off (R-NEW-4).
  run grep -q "cannot match the upstream" <<< "$pull_output"
  [ "$status" -eq 0 ]
}

# ─── Case 9: removing --build-locally handler causes this test to fail ────
@test "pull --build-locally: handler must exist in script source (P0 invariant guard)" {
  # This test directly inspects the script source to assert that the
  # --build-locally handler is present. If a contributor removes the
  # flag handler, this test fails with a clear message about the P0 invariant.
  local script="$EIDOLONS_ROOT/cli/src/mcp_atlas_aci_pull.sh"
  run grep -q "\-\-build-locally" "$script"
  [ "$status" -eq 0 ]

  # The P0 invariant comment must also be present in the source.
  run grep -q "INVARIANT (P0)" "$script"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# H2 tests — bootstrap-digest pre-flight refusal
# ═══════════════════════════════════════════════════════════════════════════

# ─── H2 Case 1: placeholder digest → pull refuses with helpful message ─────
# Once a real digest is pinned in the source, the bootstrap guard is dormant
# in normal use. To keep regression coverage for the guard (so the H2 design
# is enforced if a contributor accidentally re-introduces the placeholder),
# we override the source's `DEFAULT_IMAGE_DIGEST="${DEFAULT_IMAGE_DIGEST:-…}"`
# fallback by setting the env var. Cross-platform clean (no fixture/symlink).
@test "bootstrap-digest: placeholder digest → pull refuses with helpful message" {
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok

  local placeholder="sha256:0000000000000000000000000000000000000000000000000000000000000000"

  DEFAULT_IMAGE_DIGEST="$placeholder" run bash "$EIDOLONS_ROOT/cli/src/mcp_atlas_aci_pull.sh"

  [ "$status" -ne 0 ]
  [[ "$output" =~ "bootstrap placeholder" ]]
  [[ "$output" =~ "build-locally" ]]

  # docker.log must NOT contain any docker invocations — guard fires before
  # any docker call.
  local log="$BATS_TEST_TMPDIR/docker.log"
  if [ -f "$log" ]; then
    local line_count
    line_count="$(wc -l < "$log" | tr -d ' ')"
    [ "$line_count" -eq 0 ]
  fi
}

# ─── H2 Case 2: --image-digest real digest bypasses bootstrap guard ─────────
@test "bootstrap-digest: --image-digest with real digest bypasses guard, pull proceeds" {
  # Image inspect fails (image absent); pull also fails — we just want to
  # confirm the bootstrap guard does NOT fire for an explicit real digest.
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=fail

  local real_digest="sha256:1111111111111111111111111111111111111111111111111111111111111111"
  run_pull --image-digest "$real_digest"

  # Pull fails (expected with fake docker) but the error must be about the
  # image pull, NOT about the bootstrap placeholder.
  [ "$status" -ne 0 ]
  [[ ! "$output" =~ "bootstrap placeholder" ]]

  # docker.log must show that docker was actually invoked (guard did not block).
  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
}

# ─── H2 Case 3: --build-locally bypasses bootstrap guard ────────────────────
@test "bootstrap-digest: --build-locally bypasses guard, build proceeds" {
  # --build-locally skips the bootstrap guard — the build path does not
  # require a real registry digest.
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_BUILD_RESULT=ok

  # Invoke with default digest (placeholder) + --build-locally.
  run_pull --build-locally

  # Must succeed via the local-build path.
  [ "$status" -eq 0 ]

  # stderr must NOT mention the bootstrap placeholder.
  [[ ! "$output" =~ "bootstrap placeholder" ]]

  # docker.log must contain a build line.
  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
  run grep -E '^build .*atlas-aci' "$log"
  [ "$status" -eq 0 ]
}
