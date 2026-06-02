#!/usr/bin/env bats
#
# cli/tests/mcp_back_compat.bats — alias DEPRECATED warnings + exit codes (F5.1-F5.3).
#
# Verifies that:
#   - eidolons mcp atlas-aci [pull] emits exactly one DEPRECATED line on stderr
#   - eidolons harness install/up/verify/uninstall emits exactly one DEPRECATED line
#   - EIDOLONS_SUPPRESS_DEPRECATED=1 suppresses the line
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

FAKE_JUNCTION_VERSION="0.2.0"

setup_fake_docker_for_compat() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
subcmd="${1:-}"
case "$subcmd" in
  info)        exit 0 ;;
  image)
    case "${2:-}" in
      inspect) exit 0 ;;
      *) exit 0 ;;
    esac ;;
  pull)        exit 0 ;;
  *) exit 0 ;;
esac
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
}

setup_fake_curl_and_gh_for_compat() {
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
if [[ "${1:-}" == "verify" ]]; then echo "pass"; exit 0; fi
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

seed_junction_for_compat() {
  local ver="${1:-$FAKE_JUNCTION_VERSION}"
  local cache_dir="$EIDOLONS_HOME/cache/junction@${ver}"
  mkdir -p "$cache_dir"
  cat > "$cache_dir/junction" <<'JSTUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then echo "junction 0.2.0"; exit 0; fi
if [[ "${1:-}" == "verify" ]]; then echo "pass"; exit 0; fi
echo "stub: $*"
JSTUB
  chmod +x "$cache_dir/junction"
}

# ─── atlas-aci alias tests ────────────────────────────────────────────────────

@test "F5 S22: eidolons mcp atlas-aci emits DEPRECATED line on stderr" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_compat
  # --skip-image-check so we don't need a real docker image.
  run eidolons mcp atlas-aci --skip-image-check 2>&1 || true
  # The combined output should contain DEPRECATED.
  echo "$output" | grep -q "DEPRECATED"
}

@test "F5 S22: EIDOLONS_SUPPRESS_DEPRECATED=1 suppresses DEPRECATED line" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_SUPPRESS_DEPRECATED=1
  setup_fake_docker_for_compat
  run bash -c 'EIDOLONS_SUPPRESS_DEPRECATED=1 eidolons mcp atlas-aci --skip-image-check 2>&1 || true'
  echo "$output" | grep -v "DEPRECATED" > /dev/null || true
  # Should not have DEPRECATED in output.
  count="$(echo "$output" | grep -c "DEPRECATED" || true)"
  [ "$count" -eq 0 ]
  unset EIDOLONS_SUPPRESS_DEPRECATED
}

@test "F5 S23: eidolons mcp atlas-aci pull emits DEPRECATED line" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_compat
  run eidolons mcp atlas-aci pull 2>&1 || true
  echo "$output" | grep -q "DEPRECATED"
}

# ─── S13: atlas-aci pull alias back-compat + suppress env ────────────────

@test "S13a: mcp atlas-aci pull routes to mcp pull atlas-aci (generic verb), one DEPRECATED line" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_compat
  # Image present so pull exits 0 (fake docker inspect returns 0).
  run eidolons mcp atlas-aci pull 2>&1 || true
  local dep_count
  dep_count="$(echo "$output" | grep -c "DEPRECATED" || true)"
  [ "$dep_count" -eq 1 ]
}

@test "S13b: EIDOLONS_SUPPRESS_DEPRECATED=1 suppresses atlas-aci pull DEPRECATED line" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_compat
  count="$(EIDOLONS_SUPPRESS_DEPRECATED=1 eidolons mcp atlas-aci pull 2>&1 | grep -c "DEPRECATED" || true)"
  [ "$count" -eq 0 ]
}

@test "S13c: mcp atlas-aci pull re-pointed to pull semantics (not refresh)" {
  # Verify the dispatcher maps atlas-aci pull to mcp_pull.sh, not mcp_refresh.sh.
  # We do this by checking the eidolons dispatcher source for the new routing.
  run grep -A5 "atlas-aci" "$EIDOLONS_ROOT/cli/eidolons"
  [ "$status" -eq 0 ]
  # The pull case must reference mcp_pull.sh (not mcp_refresh.sh).
  run grep "mcp_pull.sh" "$EIDOLONS_ROOT/cli/eidolons"
  [ "$status" -eq 0 ]
}

# ─── harness alias tests ─────────────────────────────────────────────────────

@test "F5 S24: eidolons harness install emits DEPRECATED line" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_compat
  run eidolons harness install "$FAKE_JUNCTION_VERSION" 2>&1
  echo "$output" | grep -q "DEPRECATED"
}

@test "F5 S24: harness install DEPRECATED mentions mcp verb" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_compat
  run eidolons harness install "$FAKE_JUNCTION_VERSION" 2>&1
  echo "$output" | grep -q "eidolons mcp"
}

@test "F5 S25: eidolons harness up emits DEPRECATED line" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_for_compat
  run eidolons harness up 2>&1 || true
  echo "$output" | grep -q "DEPRECATED"
}

@test "F5: eidolons harness uninstall emits DEPRECATED line" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_for_compat
  # Seed lockfile so uninstall has something.
  cat > eidolons.mcp.lock <<'EOF'
generated_at: "2026-05-19T00:00:00Z"
eidolons_cli_version: "1.3.0"
catalogue_version: "1.0"
mcps:
  - name: junction
    kind: binary
    version: "0.2.0"
    source:
      repo: "Rynaro/Junction"
    integrity:
      algo: none
      value: ""
    target: ""
    hosts_wired:
      - ".eidolons/harness/manifest.json"
    installed_at: "2026-05-19T00:00:00Z"
EOF
  run eidolons harness uninstall 2>&1 || true
  echo "$output" | grep -q "DEPRECATED"
}

@test "F5: EIDOLONS_SUPPRESS_DEPRECATED=1 suppresses harness DEPRECATED" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_compat
  count="$(EIDOLONS_SUPPRESS_DEPRECATED=1 eidolons harness install "$FAKE_JUNCTION_VERSION" 2>&1 | grep -c "DEPRECATED" || true)"
  [ "$count" -eq 0 ]
}

@test "F5 S26: eidolons mcp run junction verify works via alias" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_junction_for_compat
  cat > eidolons.mcp.lock <<EOF
generated_at: "2026-05-19T00:00:00Z"
eidolons_cli_version: "1.3.0"
catalogue_version: "1.0"
mcps:
  - name: junction
    kind: binary
    version: "${FAKE_JUNCTION_VERSION}"
    source:
      repo: "Rynaro/Junction"
    integrity:
      algo: none
      value: ""
    target: "${EIDOLONS_HOME}/cache/junction@${FAKE_JUNCTION_VERSION}/junction"
    hosts_wired:
      - ".eidolons/harness/manifest.json"
    installed_at: "2026-05-19T00:00:00Z"
EOF
  run eidolons mcp run junction verify
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "pass"
}
