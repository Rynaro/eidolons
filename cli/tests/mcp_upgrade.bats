#!/usr/bin/env bats
#
# cli/tests/mcp_upgrade.bats — coverage for 'eidolons mcp upgrade' (F2.5 stories S15-S17).
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

FAKE_JUNCTION_VERSION="0.2.0"

setup_fake_curl_and_gh_for_upgrade() {
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

# Seed junction lockfile at a specific installed version.
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

@test "mcp upgrade: help exits 0" {
  run eidolons mcp upgrade --help
  [ "$status" -eq 0 ]
}

@test "mcp upgrade: unknown MCP exits 1" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons mcp upgrade no-such-mcp
  [ "$status" -eq 1 ]
}

@test "mcp upgrade S17 --all: no-op when nothing installed" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  rm -f eidolons.mcp.lock
  run eidolons mcp upgrade --all
  [ "$status" -eq 0 ]
}

@test "mcp upgrade S17 --all: exits 0 with no args (defaults to --all)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  rm -f eidolons.mcp.lock
  run eidolons mcp upgrade
  [ "$status" -eq 0 ]
}

@test "mcp upgrade S16 no-op: installed_at unchanged when already at stable" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_upgrade
  # Seed at the catalogue stable version (0.2.0).
  seed_junction_lock_at_version "$FAKE_JUNCTION_VERSION"
  before_ts="$(grep 'installed_at' eidolons.mcp.lock | head -1)"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_upgrade.sh" "junction"
  [ "$status" -eq 0 ]
  after_ts="$(grep 'installed_at' eidolons.mcp.lock | head -1)"
  # installed_at must be unchanged (no-op path).
  [ "$before_ts" = "$after_ts" ]
}

@test "mcp upgrade S15: upgrades when behind catalogue stable" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_upgrade
  # Seed at an older version (0.1.0); catalogue stable is 0.2.0.
  seed_junction_lock_at_version "0.1.0"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_upgrade.sh" "junction"
  [ "$status" -eq 0 ]
  # After upgrade, lockfile should reference stable version.
  result="$(grep -c '0.2.0' eidolons.mcp.lock || true)"
  [ "$result" -gt 0 ]
}
