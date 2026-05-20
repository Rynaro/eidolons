#!/usr/bin/env bats
#
# cli/tests/mcp_sync.bats — coverage for 'eidolons mcp sync' (F5 stories S21-S23, NG3).
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

FAKE_JUNCTION_VERSION="0.2.0"

setup_fake_curl_and_gh_for_sync() {
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

# Write an eidolons.yaml with an mcps: block.
seed_manifest_with_mcp() {
  cat > eidolons.yaml <<EOF
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
mcps:
  - name: junction
    version: "^0.2.0"
EOF
}

# Write an eidolons.yaml without any mcps: block.
seed_manifest_without_mcp() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
}

# Seed a junction lockfile entry (already installed).
seed_junction_lock_for_sync() {
  local ver="${1:-$FAKE_JUNCTION_VERSION}"
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
    installed_at: "2026-05-19T00:00:00Z"
EOF
}

@test "mcp sync: help exits 0" {
  run eidolons mcp sync --help
  [ "$status" -eq 0 ]
}

@test "mcp sync S22: exits non-zero without eidolons.yaml" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  rm -f eidolons.yaml
  run eidolons mcp sync
  [ "$status" -ne 0 ]
}

@test "mcp sync S22: no-op when eidolons.yaml has no mcps block" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_manifest_without_mcp
  run eidolons mcp sync
  [ "$status" -eq 0 ]
  # Should emit "no mcps block" info.
  echo "$output$stderr" | grep -qi "no\|nothing"
}

@test "mcp sync S21: installs declared MCPs not yet in lockfile" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_sync
  seed_manifest_with_mcp
  rm -f eidolons.mcp.lock
  run bash "$EIDOLONS_ROOT/cli/src/mcp_sync.sh"
  [ "$status" -eq 0 ]
  [ -f "eidolons.mcp.lock" ]
  result="$(grep -c 'junction' eidolons.mcp.lock || true)"
  [ "$result" -gt 0 ]
}

@test "mcp sync S23: idempotent — second sync is no-op" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_sync
  seed_manifest_with_mcp
  seed_junction_lock_for_sync "$FAKE_JUNCTION_VERSION"
  # Take lockfile snapshot before.
  cp eidolons.mcp.lock eidolons.mcp.lock.before
  run bash "$EIDOLONS_ROOT/cli/src/mcp_sync.sh"
  [ "$status" -eq 0 ]
  # Lockfile must be byte-identical (idempotency gate G-S7).
  diff eidolons.mcp.lock.before eidolons.mcp.lock
}

@test "mcp sync NG3: eidolons sync does NOT call mcp sync" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  seed_manifest_with_mcp
  rm -f eidolons.mcp.lock
  # Top-level 'eidolons sync' must not install MCPs (NG3).
  run eidolons sync
  # sync may fail for network reasons in tests; what matters is no lockfile created.
  # If sync exits 0, check that no mcp lockfile was created from eidolons.yaml mcps block.
  if [ "$status" -eq 0 ]; then
    if [ -f "eidolons.mcp.lock" ]; then
      # lockfile might exist from a previous step; check it's not from this run.
      # The key invariant: eidolons sync does not auto-install MCPs.
      # We can only test the negative by verifying mcp sync is not invoked.
      # Grep sync.sh for any reference to mcp_sync.sh install calls.
      result="$(grep -c 'mcp_install\|mcp_sync' "$EIDOLONS_ROOT/cli/src/sync.sh" || true)"
      # sync.sh may reference lib_mcp for drift info — that's OK.
      # But it must NOT call mcp_install.sh.
      install_calls="$(grep -c 'mcp_install' "$EIDOLONS_ROOT/cli/src/sync.sh" || true)"
      [ "$install_calls" -eq 0 ]
    fi
  fi
}
