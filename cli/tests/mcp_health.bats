#!/usr/bin/env bats
#
# cli/tests/mcp_health.bats — coverage for 'eidolons mcp health' (F4.1 stories S18-S20).
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

FAKE_JUNCTION_VERSION="0.2.0"

setup_mcp_env() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
}

setup_fake_curl_and_gh_for_health() {
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

# Seed a minimal lockfile entry for junction.
seed_junction_lock() {
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
    hosts_wired:
      - ".eidolons/harness/manifest.json"
    installed_at: "2026-05-19T00:00:00Z"
EOF
}

@test "mcp health: help exits 0" {
  run eidolons mcp health --help
  [ "$status" -eq 0 ]
}

@test "mcp health: exits 0 always (probe verb)" {
  setup_mcp_env
  seed_junction_lock
  run eidolons mcp health junction
  [ "$status" -eq 0 ]
}

@test "mcp health S18: outputs OVERALL line" {
  setup_mcp_env
  seed_junction_lock
  run eidolons mcp health junction
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OVERALL"
}

@test "mcp health S20 --all: exits 0 with no MCPs installed" {
  setup_mcp_env
  rm -f eidolons.mcp.lock
  run eidolons mcp health --all
  [ "$status" -eq 0 ]
}

@test "mcp health S20 --all: iterates lockfile entries" {
  setup_mcp_env
  seed_junction_lock
  run eidolons mcp health --all
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "junction"
}

@test "mcp health: not-installed MCP shows not-installed line" {
  setup_mcp_env
  rm -f eidolons.mcp.lock
  # health for a catalogue entry that's not installed.
  run eidolons mcp health junction
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not-installed\|not installed"
}

@test "mcp health: unknown name exits 1" {
  setup_mcp_env
  run eidolons mcp health no-such-mcp
  [ "$status" -eq 1 ]
}
