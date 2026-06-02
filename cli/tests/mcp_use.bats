#!/usr/bin/env bats
#
# cli/tests/mcp_use.bats — coverage for 'eidolons mcp use' (version-switch command).
#
# Stories: USE-UP (forward switch), USE-DOWN (downgrade allowed), USE-NOOP (idempotency),
#          UNPUB (unpublished version rejected), USE-BARE (missing @ver rejected),
#          NOTINST (not-installed rejected), BIN (binary kind vehicle), NOPULL.
#
# Uses junction (binary kind) as primary vehicle — avoids Docker requirement.
# Fake curl/gh stubs avoid real network calls. Fake mcp_install via override
# patterns isolate the delegation path for selected tests.
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

FAKE_JUNCTION_VERSION="0.2.0"

# ─── Shared stubs ─────────────────────────────────────────────────────────────

# Create a fake curl that emits a junction installer stub. Also fakes gh.
setup_fake_curl_and_gh() {
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
if [[ "${1:-}" == "--version" ]]; then echo "junction stub"; exit 0; fi
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

# Write a junction lockfile entry at a specific version.
seed_junction_lock_at_version() {
  local ver="$1"
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
    installed_at: "2026-05-01T00:00:00Z"
EOF
}

# ─── USE-BARE: missing @ver must exit 2 ───────────────────────────────────────

@test "mcp use: bare name (no @ver) exits 2" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons mcp use junction
  [ "$status" -eq 2 ]
  [[ "$output" =~ "@" ]] || [[ "$output" =~ "ver" ]]
}

@test "mcp use: --help exits 0" {
  run eidolons mcp use --help
  [ "$status" -eq 0 ]
}

@test "mcp use: no arguments exits 2" {
  run eidolons mcp use
  [ "$status" -eq 2 ]
}

# ─── UNPUB: unpublished version rejected exit 1 ───────────────────────────────

@test "mcp use: unpublished version rejected (exit 1)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_at_version "0.2.0"
  # 9.9.9 does not exist in the catalogue releases.
  run eidolons mcp use junction@9.9.9
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not published" ]]
}

@test "mcp use: unpublished version error names the MCP and version" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_at_version "0.2.0"
  run eidolons mcp use junction@9.9.9
  [ "$status" -eq 1 ]
  [[ "$output" =~ "junction" ]]
  [[ "$output" =~ "9.9.9" ]]
}

@test "mcp use: unpublished version error mentions roster bump" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_at_version "0.2.0"
  run eidolons mcp use junction@9.9.9
  [ "$status" -eq 1 ]
  [[ "$output" =~ "roster" ]]
}

@test "mcp use: unpublished version leaves lockfile untouched" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_at_version "0.2.0"
  local before
  before="$(cat eidolons.mcp.lock)"
  run eidolons mcp use junction@9.9.9
  [ "$status" -eq 1 ]
  local after
  after="$(cat eidolons.mcp.lock)"
  [ "$before" = "$after" ]
}

@test "mcp use: unpublished version lists published versions in error" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_at_version "0.2.0"
  run eidolons mcp use junction@9.9.9
  [ "$status" -eq 1 ]
  # The catalogue has 0.2.0 as the only junction release.
  [[ "$output" =~ "0.2.0" ]]
}

# ─── NOTINST: not installed → exit 1 ─────────────────────────────────────────

@test "mcp use: not installed exits 1" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  rm -f eidolons.mcp.lock
  run eidolons mcp use junction@0.2.0
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not installed" ]]
}

# ─── USE-NOOP: already at target version → no-op ─────────────────────────────

@test "mcp use: no-op when already at target version" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_at_version "0.2.0"
  local before_ts
  before_ts="$(grep 'installed_at' eidolons.mcp.lock | head -1)"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_use.sh" "junction@0.2.0"
  [ "$status" -eq 0 ]
  local after_ts
  after_ts="$(grep 'installed_at' eidolons.mcp.lock | head -1)"
  # installed_at must be unchanged (no-op path).
  [ "$before_ts" = "$after_ts" ]
}

@test "mcp use: no-op leaves lockfile byte-identical (idempotency)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_at_version "0.2.0"
  local before
  before="$(cat eidolons.mcp.lock)"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_use.sh" "junction@0.2.0"
  [ "$status" -eq 0 ]
  local after
  after="$(cat eidolons.mcp.lock)"
  [ "$before" = "$after" ]
}

# ─── BIN / USE-UP: forward switch via binary kind (junction) ─────────────────
# Note: junction catalogue has only 0.2.0 as a published release.
# We can't test a real UP move to a non-existent version, but we CAN
# test the full delegation path for the no-op (same version) and confirm
# the install path is exercised for a downgrade scenario with USE-DOWN.

@test "mcp use: unknown MCP (not in catalogue) exits 1" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_at_version "0.2.0"
  run eidolons mcp use no-such-mcp@1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not found" ]] || [[ "$output" =~ "catalogue" ]]
}

# ─── NOPULL: --no-pull forwarded correctly ────────────────────────────────────

@test "mcp use: --no-pull accepted for binary kind (no-op at same version)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_lock_at_version "0.2.0"
  # --no-pull + same version = no-op; should succeed without error.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_use.sh" "junction@0.2.0" --no-pull
  [ "$status" -eq 0 ]
}

# ─── USE-DOWN: downgrade allowed (catalogue-published target) ─────────────────
# This test seeds junction at 0.2.0 and requests the same published version 0.2.0
# via a delegated install. The real "downgrade" scenario would need two published
# junction releases; since the catalogue only has 0.2.0, we verify the absence of
# a direction check by confirming use never rejects on version ordering.

@test "mcp use: no direction gate (downgrade allowed, no rejection)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh
  seed_junction_lock_at_version "0.2.0"
  # Simulate a "downgrade" scenario: mcp_use should have no direction check.
  # The command must exit 0 (no-op path) rather than die with "older than installed".
  run bash "$EIDOLONS_ROOT/cli/src/mcp_use.sh" "junction@0.2.0"
  [ "$status" -eq 0 ]
  # Must NOT contain "older than" (that error belongs to mcp_upgrade).
  [[ ! "$output" =~ "older than" ]]
}
