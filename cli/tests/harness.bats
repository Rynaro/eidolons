#!/usr/bin/env bats
#
# cli/tests/harness.bats — bats coverage for 'eidolons harness' subcommands (F7-4)
#
# Design:
#   - Network calls (curl to GitHub install.sh) are intercepted by placing a
#     fake 'curl' on PATH that emits a stub installer script. The stub creates
#     $JUNCTION_INSTALL_DIR/junction (executable) instead of a real binary.
#   - 'gh' is shadowed by a fake that echoes a pinned version tag so the
#     resolve step is deterministic.
#   - All tests rely on helpers.bash for setup/teardown (isolated tmp home).
#   - Sync tests reuse seed_manifest + fake-git from helpers.bash to avoid
#     network access; we directly seed the cache dir to simulate a Junction
#     installation for the sync marker tests.

load helpers

# ─── Helpers ──────────────────────────────────────────────────────────────────

FAKE_JUNCTION_VERSION="0.1.0"

# setup_fake_curl_and_gh
# Places fake 'curl' and 'gh' on PATH so harness install doesn't hit the network.
# fake curl: echoes a tiny install.sh that writes a stub junction binary.
# fake gh:   echoes a pinned release tag for junction.
setup_fake_curl_and_gh() {
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$FAKE_BIN"

  # fake curl: emit a stub installer that creates $JUNCTION_INSTALL_DIR/junction
  cat > "$FAKE_BIN/curl" <<'CURL'
#!/usr/bin/env bash
# Fake curl for harness tests — outputs a stub junction installer.
# Strip the -fsSL flag and URL; just print the stub to stdout.
cat <<'INSTALLER'
#!/usr/bin/env bash
# Stub junction installer (emitted by fake curl in harness.bats)
DEST="${JUNCTION_INSTALL_DIR:-/usr/local/bin}"
mkdir -p "$DEST"
cat > "$DEST/junction" <<'JBIN'
#!/usr/bin/env bash
# Stub junction binary
if [[ "${1:-}" == "verify" ]]; then
  echo "junction verify: pass-through ok"
  exit 0
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "junction 0.1.0"
  exit 0
fi
echo "junction stub: $*"
JBIN
chmod +x "$DEST/junction"
INSTALLER
CURL
  chmod +x "$FAKE_BIN/curl"

  # fake gh: echo the pinned release tag
  cat > "$FAKE_BIN/gh" <<GHSCRIPT
#!/usr/bin/env bash
# Fake gh for harness tests: always returns the pinned junction version tag
echo "v${FAKE_JUNCTION_VERSION}"
GHSCRIPT
  chmod +x "$FAKE_BIN/gh"

  export PATH="$FAKE_BIN:$PATH"
}

# seed_junction_cache [version]
# Directly creates a fake Junction cache dir with a stub binary.
# Used to simulate a pre-existing install without going through 'harness install'.
seed_junction_cache() {
  local ver="${1:-$FAKE_JUNCTION_VERSION}"
  local cache_dir="$EIDOLONS_HOME/cache/junction@${ver}"
  mkdir -p "$cache_dir"
  cat > "$cache_dir/junction" <<'JSTUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "verify" ]]; then
  echo "junction verify: pass-through ok"
  exit 0
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "junction 0.1.0"
  exit 0
fi
echo "junction stub: $*"
JSTUB
  chmod +x "$cache_dir/junction"
}

# ─── F7-1: Dispatcher wiring ──────────────────────────────────────────────────

@test "harness: dispatched from main CLI (help prints)" {
  run eidolons harness --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "eidolons harness" ]]
  [[ "$output" =~ install ]]
  [[ "$output" =~ uninstall ]]
}

@test "harness: unknown subcommand exits 2 with list of available subcommands" {
  run eidolons harness bogus-subcommand
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Unknown harness subcommand" ]]
  [[ "$output" =~ install ]]
}

@test "harness: no subcommand exits 2 with usage hint" {
  run eidolons harness
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Available subcommands" ]]
}

# ─── F7-2a: harness install ───────────────────────────────────────────────────

@test "harness install: creates cache dir and junction binary" {
  setup_fake_curl_and_gh
  run eidolons harness install
  [ "$status" -eq 0 ]
  # Cache dir must exist.
  local cache_dir="$EIDOLONS_HOME/cache/junction@${FAKE_JUNCTION_VERSION}"
  [ -d "$cache_dir" ]
  # Junction binary must be executable.
  [ -x "$cache_dir/junction" ]
}

@test "harness install: second run is idempotent (no re-install, reports already installed)" {
  setup_fake_curl_and_gh
  # First install.
  run eidolons harness install
  [ "$status" -eq 0 ]
  local cache_dir="$EIDOLONS_HOME/cache/junction@${FAKE_JUNCTION_VERSION}"
  local bin="$cache_dir/junction"
  # Capture the binary's inode via `ls -di` (POSIX; works on both Linux and
  # BSD/macOS without per-OS branching). Previous attempts used
  # `stat -f '%m' || stat -c '%Y'` which silently misbehaves on Linux:
  # `stat -f` there means "stat the filesystem" — it exits 1 (firing the
  # fallback) but ALSO writes filesystem info (including a fluctuating
  # "Free blocks" count) to stdout, which command-substitution merged with
  # the fallback's output. Under bats --jobs N filesystem load, the Free
  # count changed between the two reads and the assertion mis-failed.
  # Inode comparison is also strictly tighter than mtime: only a
  # delete+recreate of the file changes the inode, which is exactly the
  # invariant the test means to check.
  local inode1
  inode1="$(ls -di "$bin" | awk '{print $1}')"

  # Second install — must be a no-op.
  run eidolons harness install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "already installed" ]]
  local inode2
  inode2="$(ls -di "$bin" | awk '{print $1}')"
  [ "$inode1" = "$inode2" ]
}

@test "harness install <bad-version>: graceful error, non-zero exit" {
  setup_fake_curl_and_gh
  # Override fake curl to simulate a failed install for any version.
  # We do this by making the fake curl emit an installer that always exits non-zero.
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin"
  cat > "$FAKE_BIN/curl" <<'CURL'
#!/usr/bin/env bash
cat <<'INSTALLER'
#!/usr/bin/env bash
echo "junction installer: version not found" >&2
exit 1
INSTALLER
CURL
  chmod +x "$FAKE_BIN/curl"
  # The bad version won't match the gh mock's output, so version=999.9.9
  run eidolons harness install 999.9.9
  [ "$status" -ne 0 ]
  # Binary must not have been left behind.
  [ ! -d "$EIDOLONS_HOME/cache/junction@999.9.9" ]
}

@test "harness install: JUNCTION_VERSION env var pins the version" {
  setup_fake_curl_and_gh
  JUNCTION_VERSION="0.1.0" run eidolons harness install
  [ "$status" -eq 0 ]
  [ -d "$EIDOLONS_HOME/cache/junction@0.1.0" ]
}

# ─── F7-2b: harness up ────────────────────────────────────────────────────────

@test "harness up: prints version and binary path, exits 0 when installed" {
  seed_junction_cache
  run eidolons harness up
  [ "$status" -eq 0 ]
  # Binary path must appear on stdout.
  [[ "$output" =~ "junction" ]]
  [[ "$output" =~ "$FAKE_JUNCTION_VERSION" ]]
}

@test "harness up: exits non-zero and emits clear error when not installed" {
  # No seed_junction_cache — harness absent.
  run eidolons harness up
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not installed" ]]
}

# ─── F7-2c: harness verify ────────────────────────────────────────────────────

@test "harness verify: passes through to junction binary when installed" {
  seed_junction_cache
  run eidolons harness verify
  [ "$status" -eq 0 ]
  [[ "$output" =~ "junction verify" ]]
}

@test "harness verify: clear error and non-zero exit when not installed" {
  # No seed_junction_cache.
  run eidolons harness verify
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not installed" ]]
}

# ─── F7-2d: harness uninstall ─────────────────────────────────────────────────

@test "harness uninstall --yes: removes cache dir" {
  seed_junction_cache
  [ -d "$EIDOLONS_HOME/cache/junction@${FAKE_JUNCTION_VERSION}" ]
  run eidolons harness uninstall --yes
  [ "$status" -eq 0 ]
  [ ! -d "$EIDOLONS_HOME/cache/junction@${FAKE_JUNCTION_VERSION}" ]
}

@test "harness uninstall --yes: removes .eidolons/harness marker dir" {
  seed_junction_cache
  # Create a fake marker dir in the project.
  mkdir -p ".eidolons/harness"
  printf '{"name":"junction","version":"0.1.0","cache_path":"%s"}\n' \
    "$EIDOLONS_HOME/cache/junction@0.1.0" > ".eidolons/harness/manifest.json"
  run eidolons harness uninstall --yes
  [ "$status" -eq 0 ]
  [ ! -d ".eidolons/harness" ]
}

@test "harness uninstall --yes: idempotent (second run reports nothing to remove)" {
  seed_junction_cache
  run eidolons harness uninstall --yes
  [ "$status" -eq 0 ]
  # Second run — nothing present anymore.
  run eidolons harness uninstall --yes
  [ "$status" -eq 0 ]
  [[ "$output" =~ "not installed" || "$output" =~ "nothing to remove" || "$output" =~ "Nothing to remove" ]]
}

@test "harness uninstall --yes: removes all junction@* cache dirs" {
  # Seed two version dirs.
  seed_junction_cache "0.1.0"
  seed_junction_cache "0.2.0"
  run eidolons harness uninstall --yes
  [ "$status" -eq 0 ]
  [ ! -d "$EIDOLONS_HOME/cache/junction@0.1.0" ]
  [ ! -d "$EIDOLONS_HOME/cache/junction@0.2.0" ]
}

# ─── F7-3: sync harness marker ────────────────────────────────────────────────

@test "sync: writes .eidolons/harness/manifest.json when Junction is installed" {
  seed_manifest
  seed_junction_cache
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  # dry-run should report the would-write action.
  [[ "$output" =~ "harness" ]]
}

@test "sync: harness manifest.json present and contains version when Junction installed" {
  # Simulate a successful sync with a pre-populated cache.
  # We use setup_fake_git_for_upgrade to avoid real network calls for the
  # Eidolon side, and seed_junction_cache for the harness side.
  setup_fake_git_for_upgrade
  seed_manifest_with atlas=^1.0.0
  seed_junction_cache

  run eidolons sync --yes
  [ "$status" -eq 0 ]

  [ -f ".eidolons/harness/manifest.json" ]
  run cat ".eidolons/harness/manifest.json"
  [[ "$output" =~ '"name": "junction"' ]]
  [[ "$output" =~ "\"version\": \"${FAKE_JUNCTION_VERSION}\"" ]]
  [[ "$output" =~ '"cache_path"' ]]
}

@test "sync: harness manifest.json is idempotent (same content on second run)" {
  setup_fake_git_for_upgrade
  seed_manifest_with atlas=^1.0.0
  seed_junction_cache

  run eidolons sync --yes
  [ "$status" -eq 0 ]
  [ -f ".eidolons/harness/manifest.json" ]
  local content1
  content1="$(cat ".eidolons/harness/manifest.json")"

  run eidolons sync --yes
  [ "$status" -eq 0 ]
  local content2
  content2="$(cat ".eidolons/harness/manifest.json")"

  [ "$content1" = "$content2" ]
}

@test "sync: removes .eidolons/harness when Junction is not installed" {
  setup_fake_git_for_upgrade
  seed_manifest_with atlas=^1.0.0
  # Create a stale marker dir (no cache entry).
  mkdir -p ".eidolons/harness"
  printf '{"name":"junction","version":"stale"}\n' > ".eidolons/harness/manifest.json"

  # No seed_junction_cache — Junction absent from cache.
  run eidolons sync --yes
  [ "$status" -eq 0 ]
  # Marker dir must have been removed.
  [ ! -d ".eidolons/harness" ]
}
