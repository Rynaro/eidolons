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

# ─── S6/S7 — Auto-pull on upgrade / --no-pull forwarding ─────────────────

# Seed a crystalium lockfile at a given version.
seed_crystalium_lock_at_version() {
  local ver="$1"
  local digest="${2:-sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
  cat > eidolons.mcp.lock <<EOF
# eidolons.mcp.lock
generated_at: "2026-05-19T00:00:00Z"
eidolons_cli_version: "1.3.0"
catalogue_version: "1.2"
mcps:
  - name: crystalium
    kind: oci-image
    version: "${ver}"
    source:
      image: "ghcr.io/rynaro/crystalium"
    integrity:
      algo: oci-digest
      value: "${digest}"
    target: ".mcp.json"
    hosts_wired:
      - ".mcp.json"
    installed_at: "2026-05-01T00:00:00Z"
EOF
}

setup_fake_docker_for_upgrade() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
INFO_RESULT="${FAKE_DOCKER_INFO_RESULT:-ok}"
INSPECT_RESULT="${FAKE_DOCKER_INSPECT_RESULT:-fail}"
PULL_RESULT="${FAKE_DOCKER_PULL_RESULT:-ok}"
INSPECT_AFTER_PULL="${FAKE_DOCKER_INSPECT_AFTER_PULL:-ok}"

count_pulls() {
  if [ -f "$DOCKER_LOG" ]; then
    grep -c '^pull ' "$DOCKER_LOG" 2>/dev/null || true
  else
    printf '0'
  fi
}

subcmd="${1:-}"
case "$subcmd" in
  info) [ "$INFO_RESULT" = "ok" ] && exit 0 || exit 1 ;;
  image)
    action="${2:-}"
    case "$action" in
      inspect)
        _eff="$INSPECT_RESULT"
        if [ -n "$INSPECT_AFTER_PULL" ] && [ "$(count_pulls)" -ge 1 ]; then
          _eff="$INSPECT_AFTER_PULL"
        fi
        shift 2
        _iref=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --format) shift 2 ;;
            *) _iref="$1"; shift ;;
          esac
        done
        printf 'image inspect %s\n' "$_iref" >> "$DOCKER_LOG"
        [ "$_eff" = "ok" ] && exit 0 || exit 1
        ;;
      *) exit 0 ;;
    esac
    ;;
  pull)
    printf 'pull %s\n' "${2:-}" >> "$DOCKER_LOG"
    [ "$PULL_RESULT" = "ok" ] && exit 0 || exit 1
    ;;
  build) exit 0 ;;
  *) exit 0 ;;
esac
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
  export BATS_TEST_TMPDIR
}

@test "S6 mcp upgrade crystalium: auto-pull on upgrade when image absent" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_upgrade

  # Image absent before pull, present after.
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=ok
  export FAKE_DOCKER_INSPECT_AFTER_PULL=ok

  # Seed crystalium at an older version (0.1.0); catalogue stable is 1.2.0.
  seed_crystalium_lock_at_version "0.1.0"

  run bash "$EIDOLONS_ROOT/cli/src/mcp_upgrade.sh" crystalium

  [ "$status" -eq 0 ]

  # A pull line must appear in docker.log (auto-pull fired during upgrade).
  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
  run grep -c '^pull ' "$log"
  [ "$output" -ge 1 ]
}

@test "S7 mcp upgrade --no-pull: image absent → upgrade aborts with non-zero exit" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_upgrade

  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=ok

  # Seed crystalium at an older version.
  seed_crystalium_lock_at_version "0.1.0"

  run bash "$EIDOLONS_ROOT/cli/src/mcp_upgrade.sh" crystalium --no-pull

  # With --no-pull and image absent, should exit non-zero.
  [ "$status" -ne 0 ]

  # No pull line in docker.log.
  local log="$BATS_TEST_TMPDIR/docker.log"
  if [ -f "$log" ]; then
    run grep -q '^pull ' "$log"
    [ "$status" -ne 0 ]
  fi
}
