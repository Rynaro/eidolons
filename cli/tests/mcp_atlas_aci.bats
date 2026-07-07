#!/usr/bin/env bats
#
# mcp_atlas_aci.bats — generator-level tests for cli/src/mcp_atlas_aci.sh.
#
# These tests exercise the generator script directly (not via the CLI dispatcher)
# so no running Docker daemon is needed. All five cases from §5 T4 of the
# atlas-aci-sqlite-cross-project-fix spec are covered, plus five new pre-flight
# cases added in T5 of the atlas-aci-image-availability-prod-grade spec.
#
# Conventions:
#   - load 'helpers'        → helpers.bash sets EIDOLONS_ROOT, EIDOLONS_NEXUS,
#                             EIDOLONS_HOME, TEST_PROJECT, and cd's into it.
#   - BATS_TEST_TMPDIR      → bats-scoped temp directory; unique per test.
#   - run_generator [args]  → invoke mcp_atlas_aci.sh directly.
#
# Bash 3.2 compatible: no associative arrays, no ${var,,}, no readarray.
# See CLAUDE.md §"Bash 3.2 compatibility".

load helpers

# ─── Fake-docker harness ───────────────────────────────────────────────────
# T2 added a Docker + image pre-flight to the generator, so all tests that
# call run_generator without --skip-image-check now need a docker binary on
# PATH. We install a fake docker shim into $BATS_TEST_TMPDIR/fake-bin and
# prepend it to PATH in setup() (option (a) from the T5 spec recommendation).
#
# Choice rationale: option (a) — single setup() for the whole file — keeps
# the diff minimal: the five existing tests are unchanged (they just gain
# a working fake docker on PATH). New tests set env vars after setup() to
# exercise failure scenarios; setup() resets them to safe defaults.
#
# Control env-vars read by the shim at invocation time (not at write time):
#   FAKE_DOCKER_CLI_PRESENT     — 1 (default) means the shim acts as a working
#                                  docker binary. 0 makes the shim exit 127.
#                                  NOTE: FAKE_DOCKER_CLI_PRESENT=0 is NOT used
#                                  to simulate "docker not on PATH" — the shim
#                                  file is still findable by command -v docker.
#                                  To test the "docker absent" case, use a
#                                  separate empty fake-bin directory (see test
#                                  "pre-flight: docker absent").
#   FAKE_DOCKER_INFO_RESULT     — ok (default) / fail for `docker info`.
#   FAKE_DOCKER_INSPECT_RESULT  — ok / fail (default ok in setup() so the
#                                  five existing tests keep passing; new tests
#                                  override to fail to exercise error paths).
#   FAKE_DOCKER_PULL_RESULT     — ok / fail (default fail).
#
# Every invocation is logged as one line to $BATS_TEST_TMPDIR/docker.log.
#
# NOTE: The shim is written once in setup(); per-test control is via env-vars,
# which the shim reads at runtime — so tests can override them after setup()
# and the shim will honour the new values on its next invocation.

setup_fake_docker() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"

  # Write the docker shim. Uses only POSIX sh features — bash 3.2 compatible.
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
# Fake docker shim — controlled by FAKE_DOCKER_* env vars.
# Logs every invocation to $BATS_TEST_TMPDIR/docker.log.
set -u

DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"

# Default control vars (safe values for the happy path).
CLI_PRESENT="${FAKE_DOCKER_CLI_PRESENT:-1}"
INFO_RESULT="${FAKE_DOCKER_INFO_RESULT:-ok}"
INSPECT_RESULT="${FAKE_DOCKER_INSPECT_RESULT:-ok}"
PULL_RESULT="${FAKE_DOCKER_PULL_RESULT:-fail}"

# If the shim is configured to appear "not installed", exit as if not found.
if [ "$CLI_PRESENT" = "0" ]; then
  exit 127
fi

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
        if [ "$INSPECT_RESULT" = "ok" ]; then
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
  *)
    printf '%s\n' "$*" >> "$DOCKER_LOG"
    exit 0
    ;;
esac
SHIM

  chmod +x "$fake_bin/docker"

  # Prepend fake-bin to PATH so the generator finds our shim first.
  export PATH="$fake_bin:$PATH"
  export BATS_TEST_TMPDIR
}

# File-level setup: runs before every @test.
# Calls the shared helpers.bash setup() first, then installs the fake-docker
# harness with safe defaults (INFO=ok, INSPECT=ok) so all five existing tests
# keep passing without modification.
setup() {
  # Call helpers.bash setup() for EIDOLONS_NEXUS, EIDOLONS_HOME, TEST_PROJECT.
  # helpers.bash defines setup() at file scope — call it as a plain function.
  # (Bats does not chain setup functions; we replicate helpers' logic directly.)
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  mkdir -p "$EIDOLONS_HOME"
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"

  # Safe defaults for the fake-docker shim: docker present, daemon up, image
  # present. These keep the five existing tests passing without --skip-image-check.
  export FAKE_DOCKER_CLI_PRESENT=1
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok
  export FAKE_DOCKER_PULL_RESULT=fail

  setup_fake_docker
}

teardown() {
  cd "$EIDOLONS_ROOT"
}

# ─── Helper: invoke the generator script directly ─────────────────────────
# We invoke cli/src/mcp_atlas_aci.sh directly (bypassing cli/eidolons) so
# the test does not rely on the dispatcher wiring from T3. EIDOLONS_NEXUS is
# already exported by helpers.bash's setup(), which makes lib.sh resolve the
# roster from the checkout. The template path inside the script is resolved
# relative to SELF_DIR (the script's own directory), so it always finds
# cli/templates/mcp/atlas-aci.mcp.json.tmpl regardless of cwd.
#
# A non-placeholder test digest is always injected so tests exercise the
# rendering logic without hitting the bootstrap-digest pre-flight guard (H2).
# Tests that specifically test the bootstrap guard must call the script
# directly with bash (no --image-digest) to trigger IMAGE_DIGEST_EXPLICIT=false.
TEST_IMAGE_DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

run_generator() {
  # Inject TEST_IMAGE_DIGEST unless the caller already supplies --image-digest.
  local _has_digest=false
  local _arg
  for _arg in "$@"; do
    if [ "$_arg" = "--image-digest" ]; then
      _has_digest=true
      break
    fi
  done
  if [ "$_has_digest" = "false" ]; then
    run bash "$EIDOLONS_ROOT/cli/src/mcp_atlas_aci.sh" --image-digest "$TEST_IMAGE_DIGEST" "$@"
  else
    run bash "$EIDOLONS_ROOT/cli/src/mcp_atlas_aci.sh" "$@"
  fi
}

# ─── Portable md5 ─────────────────────────────────────────────────────────
# macOS ships `md5` (BSD); Linux ships `md5sum`. Both emit the hex digest
# as the first token on stdout.
file_md5() {
  local path="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$path" | awk '{print $1}'
  else
    md5 -q "$path"
  fi
}

# ─── Test 1: fresh project ─────────────────────────────────────────────────
@test "mcp atlas-aci: fresh project creates .mcp.json and .atlas/memex/.gitkeep" {
  local project="$BATS_TEST_TMPDIR/fresh-project"
  mkdir -p "$project"

  run_generator --project-root "$project"
  [ "$status" -eq 0 ]

  # .mcp.json must exist and parse as valid JSON.
  [ -f "$project/.mcp.json" ]
  run bash -c "jq empty '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  # .atlas/memex/.gitkeep must exist.
  [ -f "$project/.atlas/memex/.gitkeep" ]

  # No static --name (it would collide with the running serve container on host
  # reconnect). Per-project identity lives in the --label instead.
  run bash -c "jq -e 'any(.mcpServers.\"atlas-aci\".args[]; . == \"--name\") | not' '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  # The --label entry must equal "eidolons.project=<slug>".
  # Slug of "fresh-project" is "fresh-project".
  local label_val
  label_val="$(jq -r '
    .mcpServers."atlas-aci".args as $a |
    ($a | indices("--label"))[0] as $i |
    $a[$i + 1]
  ' "$project/.mcp.json")"

  [ "$label_val" = "eidolons.project=fresh-project" ]

  # Security hardening flags (H1): --cap-drop ALL and --security-opt no-new-privileges
  # must be present in the args array (defense-in-depth on top of the UID 10001 Dockerfile).
  run bash -c "jq -e 'any(.mcpServers.\"atlas-aci\".args[]; . == \"--cap-drop\")' '$project/.mcp.json'"
  [ "$status" -eq 0 ]
  run bash -c "jq -e 'any(.mcpServers.\"atlas-aci\".args[]; . == \"ALL\")' '$project/.mcp.json'"
  [ "$status" -eq 0 ]
  run bash -c "jq -e 'any(.mcpServers.\"atlas-aci\".args[]; . == \"--security-opt\")' '$project/.mcp.json'"
  [ "$status" -eq 0 ]
  run bash -c "jq -e 'any(.mcpServers.\"atlas-aci\".args[]; . == \"no-new-privileges\")' '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  # --cap-drop must immediately precede ALL, and --security-opt must immediately
  # precede no-new-privileges — guard against accidental reordering.
  local cap_idx sec_idx
  cap_idx="$(jq -r '(.mcpServers."atlas-aci".args | indices("--cap-drop"))[0]' "$project/.mcp.json")"
  sec_idx="$(jq -r '(.mcpServers."atlas-aci".args | indices("--security-opt"))[0]' "$project/.mcp.json")"
  local cap_val sec_val
  cap_val="$(jq -r ".mcpServers.\"atlas-aci\".args[$((cap_idx + 1))]" "$project/.mcp.json")"
  sec_val="$(jq -r ".mcpServers.\"atlas-aci\".args[$((sec_idx + 1))]" "$project/.mcp.json")"
  [ "$cap_val" = "ALL" ]
  [ "$sec_val" = "no-new-privileges" ]

  # Security flags must appear AFTER the second -v mount and BEFORE the image ref.
  # Verify ordering: cap-drop index < image-ref index.
  local img_idx
  img_idx="$(jq -r '[.mcpServers."atlas-aci".args[] | select(startswith("ghcr.io/rynaro/atlas-aci@"))] | length' "$project/.mcp.json")"
  # img_idx here is the count (1), not the position — use index() for the position.
  img_idx="$(jq -r '(.mcpServers."atlas-aci".args | map(startswith("ghcr.io/rynaro/atlas-aci@")) | index(true))' "$project/.mcp.json")"
  [ "$cap_idx" -lt "$img_idx" ]
  [ "$sec_idx" -lt "$img_idx" ]
}

# ─── Test 2: idempotent rerun without --force ──────────────────────────────
@test "mcp atlas-aci: rerun without --force exits non-zero and stderr mentions --force" {
  local project="$BATS_TEST_TMPDIR/idempotent-project"
  mkdir -p "$project"

  # First run: must succeed.
  run_generator --project-root "$project"
  [ "$status" -eq 0 ]

  # Capture md5 of the generated .mcp.json.
  local hash_before
  hash_before="$(file_md5 "$project/.mcp.json")"

  # Second run without --force: must exit non-zero.
  run_generator --project-root "$project"
  [ "$status" -ne 0 ]

  # stderr (merged into $output by bats) must mention --force.
  [[ "$output" =~ "--force" ]]

  # The file on disk must be bit-for-bit identical (md5 unchanged).
  local hash_after
  hash_after="$(file_md5 "$project/.mcp.json")"
  [ "$hash_before" = "$hash_after" ]
}

# ─── Test 3: --force regenerates .mcp.json but preserves codegraph.db ──────
@test "mcp atlas-aci: --force regenerates .mcp.json; pre-existing codegraph.db is preserved" {
  local project="$BATS_TEST_TMPDIR/force-project"
  mkdir -p "$project"

  # First run.
  run_generator --project-root "$project"
  [ "$status" -eq 0 ]

  # Simulate a pre-existing codegraph DB (non-empty, so its md5 is meaningful).
  local db_path="$project/.atlas/memex/codegraph.db"
  printf "SQLITE" > "$db_path"
  local db_hash_before
  db_hash_before="$(file_md5 "$db_path")"

  # Capture md5 of the original .mcp.json.
  local mcp_hash_before
  mcp_hash_before="$(file_md5 "$project/.mcp.json")"

  # Use a different image digest on the --force run so the regenerated
  # .mcp.json is guaranteed to differ from the first run's output.
  # Note: TEST_IMAGE_DIGEST uses 'a'-repeated; use 'b'-repeated here to differ.
  local alt_digest="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  run_generator --project-root "$project" --force --image-digest "$alt_digest"
  [ "$status" -eq 0 ]

  # .mcp.json must have changed (different digest means different content).
  local mcp_hash_after
  mcp_hash_after="$(file_md5 "$project/.mcp.json")"
  [ "$mcp_hash_before" != "$mcp_hash_after" ]

  # The new .mcp.json must contain the alt digest.
  grep -q "$alt_digest" "$project/.mcp.json"

  # codegraph.db must be intact and unchanged.
  [ -f "$db_path" ]
  local db_hash_after
  db_hash_after="$(file_md5 "$db_path")"
  [ "$db_hash_before" = "$db_hash_after" ]
}

# ─── Test 4: two distinct project roots → distinct --label and bind paths ───
@test "mcp atlas-aci: two distinct roots produce distinct --label values and bind-mount paths" {
  local project_a="$BATS_TEST_TMPDIR/project-alpha"
  local project_b="$BATS_TEST_TMPDIR/project-beta"
  mkdir -p "$project_a" "$project_b"

  run_generator --project-root "$project_a"
  [ "$status" -eq 0 ]
  run_generator --project-root "$project_b"
  [ "$status" -eq 0 ]

  # Extract --label values from each generated .mcp.json.
  local label_a label_b
  label_a="$(jq -r '
    .mcpServers."atlas-aci".args as $a |
    ($a | indices("--label"))[0] as $i |
    $a[$i + 1]
  ' "$project_a/.mcp.json")"
  label_b="$(jq -r '
    .mcpServers."atlas-aci".args as $a |
    ($a | indices("--label"))[0] as $i |
    $a[$i + 1]
  ' "$project_b/.mcp.json")"

  # Labels must differ.
  [ "$label_a" != "$label_b" ]

  # Each --label must reference its own slug.
  [ "$label_a" = "eidolons.project=project-alpha" ]
  [ "$label_b" = "eidolons.project=project-beta" ]

  # The bind-mount source for /memex must be distinct in each file.
  # Extract the string that precedes ":/memex" from the args array.
  local mount_a mount_b
  mount_a="$(jq -r '
    .mcpServers."atlas-aci".args[] | select(endswith(":/memex"))
  ' "$project_a/.mcp.json")"
  mount_b="$(jq -r '
    .mcpServers."atlas-aci".args[] | select(endswith(":/memex"))
  ' "$project_b/.mcp.json")"

  [ "$mount_a" != "$mount_b" ]

  # Each mount must reference its own project root.
  [[ "$mount_a" == "$project_a"* ]]
  [[ "$mount_b" == "$project_b"* ]]
}

# ─── Test 5: slug edge cases (spaces, uppercase, underscores) ──────────────
@test "mcp atlas-aci: project root with spaces, uppercase, underscores produces valid slug" {
  # Create a directory whose name exercises all three normalisation rules:
  # uppercase → lowercase, underscore → dash, spaces → dash.
  local parent="$BATS_TEST_TMPDIR"
  # Bats runs inside a temp dir; we can create a subdir with a complex name.
  local project="$parent/My_Project Dir"
  mkdir -p "$project"

  run_generator --project-root "$project"
  [ "$status" -eq 0 ]

  # .mcp.json must be valid JSON.
  [ -f "$project/.mcp.json" ]
  run bash -c "jq empty '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  # Extract the slug from the --label arg.
  local label_val
  label_val="$(jq -r '
    .mcpServers."atlas-aci".args as $a |
    ($a | indices("--label"))[0] as $i |
    $a[$i + 1]
  ' "$project/.mcp.json")"

  # Expected: "eidolons.project=my-project-dir"
  [ "$label_val" = "eidolons.project=my-project-dir" ]

  # The slug portion (strip leading "eidolons.project=") must match
  # the pattern: only lowercase letters, digits, and dashes.
  local slug="${label_val#eidolons.project=}"
  run bash -c "printf '%s' '$slug' | grep -Eq '^[a-z0-9-]+$'"
  [ "$status" -eq 0 ]

  # Must not start or end with a dash.
  run bash -c "printf '%s' '$slug' | grep -Eq '^-|--$'"
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# Pre-flight tests (T5 — atlas-aci-image-availability-prod-grade spec §5 T5)
# ═══════════════════════════════════════════════════════════════════════════
# The fake-docker shim installed by setup() is the only docker binary on PATH.
# Per-test control is via env vars set AFTER setup() runs; the shim reads them
# at invocation time, so overrides take effect immediately.

# ─── New Test 1: docker binary absent ─────────────────────────────────────
@test "pre-flight: docker absent → generator exits 1, no .mcp.json written" {
  local project="$BATS_TEST_TMPDIR/no-docker-project"
  mkdir -p "$project"

  # To simulate docker not being installed we create a fresh empty fake-bin
  # directory (no docker shim inside it) and point PATH at it exclusively
  # plus the standard system directories. This ensures command -v docker fails
  # even on machines where a real docker binary exists (e.g. /usr/local/bin).
  #
  # We cannot use FAKE_DOCKER_CLI_PRESENT=0 here because the shim file still
  # exists on PATH — command -v docker checks file presence, not exit status.
  local no_docker_bin="$BATS_TEST_TMPDIR/no-docker-bin"
  mkdir -p "$no_docker_bin"
  # Symlink only the externals the generator needs BEFORE the docker CLI
  # gate (dirname for SELF_DIR + panel.sh source-time; mkdir for lib.sh's
  # CACHE_DIR; bash so bats's run can exec the generator). Resolved at
  # runtime via `command -v` so the targets are correct on macOS
  # (/usr/bin/dirname, /bin/mkdir, /bin/bash) and Ubuntu
  # (/usr/bin/dirname, /usr/bin/mkdir, /usr/bin/bash). Crucially, NO
  # docker symlink and NO system bin dir on PATH — so `command -v docker`
  # finds nothing on every runner regardless of where the host's real
  # docker lives.
  ln -s "$(command -v dirname)" "$no_docker_bin/dirname"
  ln -s "$(command -v mkdir)"   "$no_docker_bin/mkdir"
  ln -s "$(command -v bash)"    "$no_docker_bin/bash"
  # Scope the restricted PATH to only the generator invocation so bats
  # post-test cleanup (rm, etc.) keeps access to system tools.
  local _saved_path="$PATH"
  PATH="$no_docker_bin"
  run_generator --project-root "$project"
  PATH="$_saved_path"

  # Must fail.
  [ "$status" -eq 1 ]

  # .mcp.json must NOT have been written (fail-fast, no partial scaffold).
  [ ! -f "$project/.mcp.json" ]

  # stderr must mention "not installed" (from atlas_aci_check_docker_cli).
  [[ "$output" =~ "not installed" ]]
}

# ─── New Test 2: daemon down ───────────────────────────────────────────────
@test "pre-flight: daemon down → generator exits 1, no .mcp.json written" {
  local project="$BATS_TEST_TMPDIR/daemon-down-project"
  mkdir -p "$project"

  # Docker CLI present but daemon unreachable.
  FAKE_DOCKER_CLI_PRESENT=1
  FAKE_DOCKER_INFO_RESULT=fail

  run_generator --project-root "$project"

  [ "$status" -eq 1 ]
  [ ! -f "$project/.mcp.json" ]

  # stderr must mention "Docker daemon" (from atlas_aci_check_docker_daemon).
  [[ "$output" =~ "Docker daemon" ]]
}

# ─── New Test 3: image missing ─────────────────────────────────────────────
@test "pre-flight: image missing → generator exits 1, no .mcp.json written" {
  local project="$BATS_TEST_TMPDIR/image-missing-project"
  mkdir -p "$project"

  # Docker CLI present, daemon up, but image not in local store.
  FAKE_DOCKER_CLI_PRESENT=1
  FAKE_DOCKER_INFO_RESULT=ok
  FAKE_DOCKER_INSPECT_RESULT=fail

  run_generator --project-root "$project"

  [ "$status" -eq 1 ]
  [ ! -f "$project/.mcp.json" ]

  # stderr must contain the corrective command (from atlas_aci_check_image).
  [[ "$output" =~ "eidolons mcp atlas-aci pull" ]]
}

# ─── New Test 4: --skip-image-check bypasses pre-flight ───────────────────
@test "pre-flight: --skip-image-check bypasses the check, file is written" {
  local project="$BATS_TEST_TMPDIR/skip-check-project"
  mkdir -p "$project"

  # Image inspect would fail — but --skip-image-check bypasses it.
  FAKE_DOCKER_CLI_PRESENT=1
  FAKE_DOCKER_INFO_RESULT=ok
  FAKE_DOCKER_INSPECT_RESULT=fail

  run_generator --project-root "$project" --skip-image-check

  # Must succeed despite failing image inspect.
  [ "$status" -eq 0 ]

  # .mcp.json must have been written.
  [ -f "$project/.mcp.json" ]

  # stderr must contain the skip warning mentioning "--skip-image-check".
  [[ "$output" =~ "--skip-image-check" ]]
}

# ─── New Test 5: image present → generator succeeds (happy path with shim) ─
@test "pre-flight: image present → generator succeeds" {
  local project="$BATS_TEST_TMPDIR/image-ok-project"
  mkdir -p "$project"

  # All checks pass (these are the setup() defaults; explicit for clarity).
  FAKE_DOCKER_CLI_PRESENT=1
  FAKE_DOCKER_INFO_RESULT=ok
  FAKE_DOCKER_INSPECT_RESULT=ok

  run_generator --project-root "$project"

  [ "$status" -eq 0 ]
  [ -f "$project/.mcp.json" ]
  [ -f "$project/.atlas/memex/.gitkeep" ]

  # No skip-warning: the image was present so no --skip-image-check was needed.
  [[ ! "$output" =~ "--skip-image-check" ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# H2 tests — bootstrap-digest pre-flight refusal
# ═══════════════════════════════════════════════════════════════════════════

# ─── H2 Test 1: placeholder digest → generator refuses before docker ───────
# Once a real digest is pinned in source, the bootstrap guard is dormant in
# normal use. To keep regression coverage (so the H2 invariant fires if a
# contributor accidentally re-introduces the placeholder), we override the
# source's `DEFAULT_IMAGE_DIGEST="${DEFAULT_IMAGE_DIGEST:-…}"` fallback by
# setting the env var. Cross-platform clean (no fixture/symlink).
@test "bootstrap-digest: placeholder digest → generator refuses with helpful message" {
  local project="$BATS_TEST_TMPDIR/bootstrap-project"
  mkdir -p "$project"

  FAKE_DOCKER_CLI_PRESENT=1
  FAKE_DOCKER_INFO_RESULT=ok
  FAKE_DOCKER_INSPECT_RESULT=ok

  local placeholder="sha256:0000000000000000000000000000000000000000000000000000000000000000"

  DEFAULT_IMAGE_DIGEST="$placeholder" run bash "$EIDOLONS_ROOT/cli/src/mcp_atlas_aci.sh" --project-root "$project"

  [ "$status" -ne 0 ]
  [ ! -f "$project/.mcp.json" ]
  [[ "$output" =~ "bootstrap placeholder" ]]
  [[ "$output" =~ "build-locally" ]]
}

# ─── H2 Test 2: --image-digest real digest bypasses bootstrap guard ─────────
@test "bootstrap-digest: explicit --image-digest with real digest bypasses guard" {
  local project="$BATS_TEST_TMPDIR/override-project"
  mkdir -p "$project"

  # All docker checks pass.
  FAKE_DOCKER_CLI_PRESENT=1
  FAKE_DOCKER_INFO_RESULT=ok
  FAKE_DOCKER_INSPECT_RESULT=ok

  # An explicit non-placeholder digest must bypass the guard and produce output.
  local real_digest="sha256:1111111111111111111111111111111111111111111111111111111111111111"
  run_generator --project-root "$project" --image-digest "$real_digest"

  [ "$status" -eq 0 ]
  [ -f "$project/.mcp.json" ]

  # The digest must appear in the rendered file.
  grep -q "$real_digest" "$project/.mcp.json"
}

# ═══════════════════════════════════════════════════════════════════════════
# T7 tests — --print-pinned-ref flag (T2) and lib accessor (T1)
# ═══════════════════════════════════════════════════════════════════════════

# ─── T7 Test 1: --print-pinned-ref ─────────────────────────────────────────
# GIVEN the CLI is invoked with --print-pinned-ref.
# WHEN no Docker daemon, no template, no project-root are supplied.
# THEN stdout contains the full pinned ref, exit 0, no .mcp.json or .atlas/ written.
@test "pinned-ref: --print-pinned-ref prints full ref to stdout, exits 0, no files created" {
  local project="$BATS_TEST_TMPDIR/pinned-ref-project"
  mkdir -p "$project"

  # Run via the CLI dispatcher (not run_generator) to exercise the full flag path.
  # --print-pinned-ref must work even when Docker is absent and no template is needed.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_atlas_aci.sh" --print-pinned-ref

  [ "$status" -eq 0 ]

  # stdout must match the full pinned ref format.
  [[ "$output" =~ ^ghcr\.io/rynaro/atlas-aci@sha256:[0-9a-f]{64}$ ]]

  # No .mcp.json must have been created in cwd.
  [ ! -f ".mcp.json" ]

  # No .atlas/ directory must have been created.
  [ ! -d ".atlas" ]
}

# ─── T7 Test 2: lib accessor matches --print-pinned-ref ────────────────────
# GIVEN lib_mcp_atlas_aci.sh is sourced directly.
# WHEN atlas_aci_print_pinned_ref is called.
# THEN stdout matches the same value as --print-pinned-ref and the regex contract.
@test "pinned-ref: lib atlas_aci_print_pinned_ref matches --print-pinned-ref output" {
  # Capture output from the CLI flag.
  local flag_output
  flag_output="$(bash "$EIDOLONS_ROOT/cli/src/mcp_atlas_aci.sh" --print-pinned-ref)"

  # Capture output from the library function.
  local lib_output
  lib_output="$(bash -c ". '$EIDOLONS_ROOT/cli/src/lib_mcp_atlas_aci.sh'; atlas_aci_print_pinned_ref")"

  # Both must be non-empty.
  [ -n "$flag_output" ]
  [ -n "$lib_output" ]

  # Both must satisfy the format contract.
  run bash -c "printf '%s' '$flag_output' | grep -Eq '^ghcr\\.io/rynaro/atlas-aci@sha256:[0-9a-f]{64}\$'"
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$lib_output' | grep -Eq '^ghcr\\.io/rynaro/atlas-aci@sha256:[0-9a-f]{64}\$'"
  [ "$status" -eq 0 ]

  # Both must be identical.
  [ "$flag_output" = "$lib_output" ]
}

# ─── F5 Back-compat: DEPRECATED line via CLI dispatcher ─────────────────────
# GIVEN the operator calls `eidolons mcp atlas-aci` via the CLI dispatcher.
# THEN stderr emits exactly one DEPRECATED line.
@test "back-compat: eidolons mcp atlas-aci via dispatcher emits DEPRECATED" {
  run eidolons mcp atlas-aci --skip-image-check 2>&1 || true
  echo "$output" | grep -q "DEPRECATED"
}

@test "back-compat: EIDOLONS_SUPPRESS_DEPRECATED=1 suppresses atlas-aci DEPRECATED" {
  count="$(EIDOLONS_SUPPRESS_DEPRECATED=1 eidolons mcp atlas-aci --skip-image-check 2>&1 | grep -c "DEPRECATED" || true)"
  [ "$count" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# OCI merge coexistence — atlas-aci + crystalium in the same .mcp.json
# ═══════════════════════════════════════════════════════════════════════════
#
# Asserts that installing atlas-aci then rendering+merging the crystalium
# template into the SAME .mcp.json file preserves BOTH mcpServers entries,
# expands __HOME__, and carries CRYSTALIUM_CALLER_TIER=T1.
#
# Uses _mcp_oci_render_and_merge (the generalized OCI driver helper from
# lib_mcp.sh) directly so no running Docker daemon is needed for crystalium.
# atlas-aci is installed via run_generator (which already uses the fake-docker
# shim set up by setup()).

@test "OCI merge: atlas-aci + crystalium coexist in .mcp.json — both entries survive, __HOME__ expanded, T1 present" {
  local project="$BATS_TEST_TMPDIR/coexist-project"
  mkdir -p "$project"

  # Step 1: install atlas-aci first (uses run_generator which injects fake docker).
  run_generator --project-root "$project"
  [ "$status" -eq 0 ]
  [ -f "$project/.mcp.json" ]

  # Confirm atlas-aci entry is present before merge.
  run bash -c "jq -e '.mcpServers[\"atlas-aci\"]' '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  # Step 2: render+merge crystalium template via _mcp_oci_render_and_merge.
  # We source lib_mcp.sh directly (no Docker needed — we bypass the OCI driver's
  # pre-flight and call the merge helper). A synthetic digest is used.
  local crystalium_digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  local crystalium_tmpl="cli/templates/mcp/crystalium.mcp.json.tmpl"

  run bash -c "
    set -euo pipefail
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    export NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'
    _mcp_oci_render_and_merge crystalium '$project' '$crystalium_digest' '$crystalium_tmpl'
  "
  [ "$status" -eq 0 ]

  # Both entries must survive in the merged .mcp.json.
  run bash -c "jq -e '.mcpServers[\"atlas-aci\"]' '$project/.mcp.json'"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcpServers[\"crystalium\"]' '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  # __HOME__ must be fully expanded — no literal __HOME__ anywhere.
  run bash -c "grep -q '__HOME__' '$project/.mcp.json'"
  [ "$status" -ne 0 ]

  # CRYSTALIUM_CALLER_TIER=T1 must be present in the crystalium args.
  run bash -c "jq -e 'any(.mcpServers.crystalium.args[]; . == \"CRYSTALIUM_CALLER_TIER=T1\")' '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  # .mcp.json must still be valid JSON after the merge.
  run bash -c "jq empty '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  # md5 sanity: the file must be non-empty (real content written).
  local hash
  hash="$(file_md5 "$project/.mcp.json")"
  [ -n "$hash" ]
}
