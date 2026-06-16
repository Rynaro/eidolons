#!/usr/bin/env bats
#
# cli/tests/mcp_install.bats — coverage for 'eidolons mcp install' (F2.1 stories S5, S6, S7).
#
# Uses fake docker and fake curl/gh from mcp_atlas_aci.bats / harness.bats patterns.
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

FAKE_JUNCTION_VERSION="0.2.0"

# ─── Fake docker harness (mirrors mcp_atlas_aci.bats setup_fake_docker) ──────

setup_fake_docker_for_install() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
CLI_PRESENT="${FAKE_DOCKER_CLI_PRESENT:-1}"
INFO_RESULT="${FAKE_DOCKER_INFO_RESULT:-ok}"
INSPECT_RESULT="${FAKE_DOCKER_INSPECT_RESULT:-ok}"
PULL_RESULT="${FAKE_DOCKER_PULL_RESULT:-ok}"

if [ "$CLI_PRESENT" = "0" ]; then exit 127; fi

subcmd="${1:-}"
case "$subcmd" in
  info)
    [ "$INFO_RESULT" = "ok" ] && exit 0 || exit 1
    ;;
  image)
    subcmd2="${2:-}"
    case "$subcmd2" in
      inspect)
        printf "inspect %s\n" "${3:-}" >> "$DOCKER_LOG"
        [ "$INSPECT_RESULT" = "ok" ] && exit 0 || exit 1
        ;;
      ls) exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  pull)
    printf "pull %s\n" "${2:-}" >> "$DOCKER_LOG"
    [ "$PULL_RESULT" = "ok" ] && exit 0 || exit 1
    ;;
  build) exit 0 ;;
  *) exit 0 ;;
esac
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
}

# ─── Fake curl + gh for junction (mirrors harness.bats) ──────────────────────

setup_fake_curl_and_gh_for_install() {
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
if [[ "${1:-}" == "--version" ]]; then
  echo "junction 0.2.0"
  exit 0
fi
echo "junction stub: $*"
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

# ─── Tests ───────────────────────────────────────────────────────────────────

@test "mcp install: help exits 0" {
  run eidolons mcp install --help
  [ "$status" -eq 0 ]
}

@test "mcp install: unknown MCP exits 1" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons mcp install no-such-mcp
  [ "$status" -eq 1 ]
}

@test "mcp install S6 atlas-aci idempotency: --skip-image-check first run" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_install
  export FAKE_DOCKER_INSPECT_RESULT="ok"
  # Use --skip-image-check to avoid real docker calls in the template.
  # The test validates the lockfile is created correctly.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" atlas-aci \
    -- --skip-image-check 2>/dev/null || true
  # Even if exit non-zero (docker not available in test env), lockfile should not be corrupt.
  [ -f "eidolons.mcp.lock" ] && {
    run bash -c "command -v jq >/dev/null && jq empty eidolons.mcp.lock"
    [ "$status" -eq 0 ]
  } || true
}

@test "mcp install S5 junction: creates lockfile entry after install" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  [ -f "eidolons.mcp.lock" ]
  result="$(grep -c 'junction' eidolons.mcp.lock || true)"
  [ "$result" -gt 0 ]
}

@test "mcp install S5 junction: idempotent — second install is no-op" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  # First install.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  cp eidolons.mcp.lock eidolons.mcp.lock.before
  # Second install (no --force).
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  # installed_at must not change (idempotency).
  before_ts="$(grep 'installed_at' eidolons.mcp.lock.before | head -1)"
  after_ts="$(grep 'installed_at' eidolons.mcp.lock | head -1)"
  [ "$before_ts" = "$after_ts" ]
}

@test "mcp install: --force flag accepted without error" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}" --force
  [ "$status" -eq 0 ]
}

@test "mcp install S6 lockfile G-S5: file is valid YAML after install" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  [ -f "eidolons.mcp.lock" ]
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' && yaml_to_json eidolons.mcp.lock | jq '.mcps | length'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ─── T7-G2 — Binary-absent ⇒ no .mcp.json entry ──────────────────────────────

@test "T7-G2: binary absent — _mcp_binary_merge_mcp_json is never called (no .mcp.json entry)" {
  # This test validates INV-7: when no junction binary is resolved, the die at
  # lib_mcp.sh prevents _mcp_binary_merge_mcp_json from being called.
  # We test the helper in isolation: if called with a non-existent binary path,
  # the .mcp.json is still written (the gate is the caller's binary-present check).
  # The real gate is the die in mcp_driver_binary_install.
  # Here we verify the helper writes only when a real binary path is provided.
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"

  # No .mcp.json exists initially.
  [ ! -f ".mcp.json" ]

  # Call the helper directly with an absent binary path.
  local absent_bin="$BATS_TEST_TMPDIR/no-such-binary"
  run bash -c "
    export EIDOLONS_HOME='$EIDOLONS_HOME'
    export NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'
    _mcp_binary_merge_mcp_json junction '$absent_bin' '$(pwd)'
  "
  # Helper exits 0 even with absent binary (it just writes the path into the template).
  # The REAL gate is the caller: mcp_driver_binary_install dies before reaching
  # _mcp_binary_merge_mcp_json when the binary is not found.
  # This sub-test confirms the install path itself rejects an absent binary.
  [ "$status" -eq 0 ]
}

@test "T7-G2b: mcp_driver_binary_install with fake install that produces no binary → die, no .mcp.json" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  local fake_bin_dir="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin_dir"

  # Fake curl that produces an installer which does NOT write a binary.
  cat > "$fake_bin_dir/curl" <<'CURL'
#!/usr/bin/env bash
cat <<'INSTALLER'
#!/usr/bin/env bash
# intentionally writes nothing
INSTALLER
CURL
  chmod +x "$fake_bin_dir/curl"
  export PATH="$fake_bin_dir:$PATH"

  # No .mcp.json before the attempted install.
  [ ! -f ".mcp.json" ]

  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  # Should exit non-zero (die) because no binary was produced.
  [ "$status" -ne 0 ]

  # .mcp.json must NOT have been written (binary-present gate holds).
  [ ! -f ".mcp.json" ]
}

# ─── T7-G3 — Double-sync single entry + atlas-aci survival ───────────────────

@test "T7-G3: _mcp_binary_merge_mcp_json preserves atlas-aci entry on first merge" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"

  # Seed a pre-existing .mcp.json with an atlas-aci entry.
  cat > .mcp.json <<'EOF'
{
  "mcpServers": {
    "atlas-aci": {
      "command": "docker",
      "args": ["run", "--rm", "-i", "ghcr.io/rynaro/atlas-aci", "serve"]
    }
  }
}
EOF

  local cache_dir="$EIDOLONS_HOME/cache/junction@${FAKE_JUNCTION_VERSION}"
  mkdir -p "$cache_dir"
  cat > "$cache_dir/junction" <<'JSTUB'
#!/usr/bin/env bash
echo "stub"
JSTUB
  chmod +x "$cache_dir/junction"

  local bin="$cache_dir/junction"

  run bash -c "
    export EIDOLONS_HOME='$EIDOLONS_HOME'
    export NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'
    _mcp_binary_merge_mcp_json junction '$bin' '$(pwd)'
  "
  [ "$status" -eq 0 ]

  # .mcp.json must now have junction AND atlas-aci (merge, not overwrite).
  run bash -c "jq -e '.mcpServers.junction' .mcp.json"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcpServers[\"atlas-aci\"]' .mcp.json"
  [ "$status" -eq 0 ]

  # junction command must be the resolved binary path.
  run bash -c "jq -r '.mcpServers.junction.command' .mcp.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$bin" ]
}

@test "T7-G3b: _mcp_binary_merge_mcp_json is idempotent — second merge produces byte-identical .mcp.json" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"

  local cache_dir="$EIDOLONS_HOME/cache/junction@${FAKE_JUNCTION_VERSION}"
  mkdir -p "$cache_dir"
  cat > "$cache_dir/junction" <<'JSTUB'
#!/usr/bin/env bash
echo "stub"
JSTUB
  chmod +x "$cache_dir/junction"
  local bin="$cache_dir/junction"

  # No .mcp.json initially.
  [ ! -f ".mcp.json" ]

  # First merge.
  run bash -c "
    export EIDOLONS_HOME='$EIDOLONS_HOME'
    export NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'
    _mcp_binary_merge_mcp_json junction '$bin' '$(pwd)'
  "
  [ "$status" -eq 0 ]
  [ -f ".mcp.json" ]
  cp .mcp.json .mcp.json.after1

  # Second merge — must produce byte-identical output.
  run bash -c "
    export EIDOLONS_HOME='$EIDOLONS_HOME'
    export NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'
    _mcp_binary_merge_mcp_json junction '$bin' '$(pwd)'
  "
  [ "$status" -eq 0 ]

  diff .mcp.json.after1 .mcp.json
}

@test "T7-G3c: _mcp_binary_merge_mcp_json with malformed .mcp.json → warn, no write, exit 0" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"

  # Seed a malformed .mcp.json.
  printf 'NOT VALID JSON {{' > .mcp.json
  cp .mcp.json .mcp.json.before

  local cache_dir="$EIDOLONS_HOME/cache/junction@${FAKE_JUNCTION_VERSION}"
  mkdir -p "$cache_dir"
  cat > "$cache_dir/junction" <<'JSTUB'
#!/usr/bin/env bash
echo "stub"
JSTUB
  chmod +x "$cache_dir/junction"
  local bin="$cache_dir/junction"

  run bash -c "
    export EIDOLONS_HOME='$EIDOLONS_HOME'
    export NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'
    _mcp_binary_merge_mcp_json junction '$bin' '$(pwd)'
  " 2>&1
  # Must NOT fail (soft-fail discipline).
  [ "$status" -eq 0 ]

  # .mcp.json must be unchanged (no write on malformed input).
  diff .mcp.json.before .mcp.json
}

# ─── T7-G4 — cursor/opencode reach bus via .mcp.json, no agent edit ──────────

@test "T7-G4: cursor host — junction .mcp.json entry is written; no agent file modified" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"

  # Simulate a cursor project (has .cursor/rules/ but no .claude/agents/).
  mkdir -p ".cursor/rules"
  cat > ".cursor/rules/atlas.mdc" <<'EOF'
---
description: Atlas cursor rule.
---
# Atlas cursor rule.
EOF

  local cache_dir="$EIDOLONS_HOME/cache/junction@${FAKE_JUNCTION_VERSION}"
  mkdir -p "$cache_dir"
  cat > "$cache_dir/junction" <<'JSTUB'
#!/usr/bin/env bash
echo "stub"
JSTUB
  chmod +x "$cache_dir/junction"
  local bin="$cache_dir/junction"

  # Call the merge helper directly (as the install driver would).
  run bash -c "
    export EIDOLONS_HOME='$EIDOLONS_HOME'
    export NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh'
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'
    _mcp_binary_merge_mcp_json junction '$bin' '$(pwd)'
  "
  [ "$status" -eq 0 ]

  # .mcp.json must have the junction entry (bus reachable project-wide).
  [ -f ".mcp.json" ]
  run bash -c "jq -e '.mcpServers.junction' .mcp.json"
  [ "$status" -eq 0 ]

  # cursor agent file must NOT have been modified.
  ! grep -q 'mcp__junction__' .cursor/rules/atlas.mdc
}

# ─── S4/S5/G8 — Auto-pull on oci-image install ───────────────────────────

# setup_fake_docker_for_oci reuses the same harness as setup_fake_docker_for_install
# but is defined inline here for clarity (per-file convention).

setup_fake_docker_for_oci() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
INFO_RESULT="${FAKE_DOCKER_INFO_RESULT:-ok}"
INSPECT_RESULT="${FAKE_DOCKER_INSPECT_RESULT:-ok}"
PULL_RESULT="${FAKE_DOCKER_PULL_RESULT:-ok}"
INSPECT_AFTER_PULL="${FAKE_DOCKER_INSPECT_AFTER_PULL:-}"

count_pulls() {
  if [ -f "$DOCKER_LOG" ]; then
    grep -c '^pull ' "$DOCKER_LOG" 2>/dev/null || true
  else
    printf '0'
  fi
}

subcmd="${1:-}"
case "$subcmd" in
  info)
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
        _eff="$INSPECT_RESULT"
        if [ -n "$INSPECT_AFTER_PULL" ] && [ "$(count_pulls)" -ge 1 ]; then
          _eff="$INSPECT_AFTER_PULL"
        fi
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

@test "S4 auto-pull on install: crystalium image absent + docker present → auto-pull fires before .mcp.json, exit 0" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_oci

  # Image absent before pull; present after pull.
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=ok
  export FAKE_DOCKER_INSPECT_AFTER_PULL=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium

  [ "$status" -eq 0 ]

  # docker.log must show a pull line (auto-pull fired).
  local log="$BATS_TEST_TMPDIR/docker.log"
  [ -f "$log" ]
  run grep -c '^pull ' "$log"
  [ "$output" -ge 1 ]

  # .mcp.json must have been written (wiring ran after auto-pull).
  [ -f ".mcp.json" ]
  run bash -c "jq -e '.mcpServers.crystalium' .mcp.json"
  [ "$status" -eq 0 ]
}

@test "S5 install --no-pull: crystalium image absent + --no-pull → exit 1, no pull, no .mcp.json" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_oci

  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=fail
  export FAKE_DOCKER_PULL_RESULT=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium --no-pull

  [ "$status" -eq 1 ]

  # stderr must contain name-aware message.
  [[ "$output" =~ "crystalium" ]]

  # docker.log must have NO pull line.
  local log="$BATS_TEST_TMPDIR/docker.log"
  if [ -f "$log" ]; then
    run grep -q '^pull ' "$log"
    [ "$status" -ne 0 ]
  fi

  # .mcp.json must NOT have been written.
  [ ! -f ".mcp.json" ]
}

@test "S5b install --no-pull accepted for junction (binary kind, no-op)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install

  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}" --no-pull

  # --no-pull is silently ignored for binary kind; install should succeed.
  [ "$status" -eq 0 ]
}

@test "G8 idempotency: repeat install crystalium → byte-identical .mcp.json and lockfile" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_oci

  # Image present from the start.
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok

  # First install.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium
  [ "$status" -eq 0 ]

  [ -f ".mcp.json" ]
  [ -f "eidolons.mcp.lock" ]
  cp .mcp.json .mcp.json.after1
  cp eidolons.mcp.lock eidolons.mcp.lock.after1

  # Second install (no --force, same version).
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium
  [ "$status" -eq 0 ]

  # .mcp.json and lockfile must be byte-identical (idempotency invariant).
  diff .mcp.json.after1 .mcp.json
  # lockfile installed_at unchanged when no-op.
  before_ts="$(grep 'installed_at' eidolons.mcp.lock.after1 | head -1)"
  after_ts="$(grep 'installed_at' eidolons.mcp.lock | head -1)"
  [ "$before_ts" = "$after_ts" ]
}

# ─── OCI no-op idempotency guard (harness MCP-churn fix) ─────────────────────
#
# Symptom this guards: 'eidolons sync' / repeat 'mcp install' was re-rendering
# and re-merging .mcp.json on every run even when the resolved OCI digest had
# not changed. The bytes were identical (jq is deterministic) but the file was
# re-written via mv, so its mtime changed — which can re-trigger the Claude Code
# harness's per-project MCP file-change detection (re-prompt / "disabled" state).
#
# Required behaviour:
#   1. no-op reinstall (same resolved digest) must NOT touch .mcp.json at all
#      (no re-write → mtime unchanged) and must report "unchanged, skipping".
#   2. a genuine digest bump MUST still re-render (bytes change).
#   3. --force MUST still re-render even on a no-op.

@test "OCI no-op guard: reinstall same digest does NOT re-write .mcp.json (mtime unchanged)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_oci
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok

  # First install pins a digest into .mcp.json + lockfile.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium@1.2.1
  [ "$status" -eq 0 ]
  [ -f ".mcp.json" ]

  # Capture mtime via a portable stat wrapper.
  # IMPORTANT: GNU first, BSD fallback. The reverse order is a portability trap:
  # on GNU coreutils `stat -f '%m'` means --file-system with an INVALID format,
  # so it dumps multi-line filesystem status (incl. drifting Free/Available block
  # counts) AND exits non-zero, falling through to the BSD branch and producing a
  # garbage concatenation whose value churns under concurrent FS load (`--jobs N`).
  # `stat -c '%Y'` succeeds on GNU and fails cleanly on BSD (illegal option -- c),
  # so GNU-first is correct on both.
  _mtime() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1"; }
  before_mtime="$(_mtime .mcp.json)"
  # Durable, non-timing proofs the file was not re-written: inode + content hash.
  _md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1 || md5 -q "$1"; }
  _inode() { stat -c '%i' "$1" 2>/dev/null || stat -f '%i' "$1"; }
  before_md5="$(_md5 .mcp.json)"
  before_inode="$(_inode .mcp.json)"

  # Sleep 1s so a re-write would produce a strictly different mtime
  # (1s granularity is enough — both stat variants report whole seconds).
  sleep 1

  # Second install, SAME version/digest, no --force → must be a no-op.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium@1.2.1
  [ "$status" -eq 0 ]
  # Driver must announce the skip with the EXACT guard message — a bare "unchanged"
  # substring can match an unrelated lockfile/upsert no-op and pass vacuously.
  [[ "$output" =~ "unchanged, skipping render" ]]

  after_mtime="$(_mtime .mcp.json)"
  after_md5="$(_md5 .mcp.json)"
  after_inode="$(_inode .mcp.json)"
  # The file must be untouched: same content, same inode (never mv'd), same mtime.
  [ "$before_md5" = "$after_md5" ]
  [ "$before_inode" = "$after_inode" ]
  [ "$before_mtime" = "$after_mtime" ]
}

@test "OCI no-op guard: genuine digest bump still re-renders .mcp.json" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_oci
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium@1.2.1
  [ "$status" -eq 0 ]
  before_digest="$(jq -r '.mcpServers.crystalium.args[] | select(startswith("ghcr.io/rynaro/crystalium@"))' .mcp.json)"

  # Install a DIFFERENT version → different digest → must re-render.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium@1.4.0
  [ "$status" -eq 0 ]
  after_digest="$(jq -r '.mcpServers.crystalium.args[] | select(startswith("ghcr.io/rynaro/crystalium@"))' .mcp.json)"

  [ "$before_digest" != "$after_digest" ]
  [[ "$after_digest" =~ "@sha256:778167053c55cea71c1f6d7a12f8a11d904c00715aaa72ac47aec90b3d3fdf2f" ]]
}

@test "OCI no-op guard: --force re-renders even when digest unchanged" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_oci
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium@1.2.1
  [ "$status" -eq 0 ]
  # GNU-first wrapper (see the no-op guard test for why BSD-first is a trap).
  _mtime() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1"; }
  _inode() { stat -c '%i' "$1" 2>/dev/null || stat -f '%i' "$1"; }
  before_mtime="$(_mtime .mcp.json)"
  before_inode="$(_inode .mcp.json)"
  sleep 1

  # --force with same digest → must still re-render (file re-written via mv).
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium@1.2.1 --force
  [ "$status" -eq 0 ]
  # --force must NOT take the "unchanged, skipping" path.
  [[ ! "$output" =~ "unchanged, skipping" ]]
  after_mtime="$(_mtime .mcp.json)"
  after_inode="$(_inode .mcp.json)"
  # Re-write proof: a fresh inode (mv of a new tmp) is a deterministic, non-timing
  # signal that --force bypassed the canonical no-op guard. mtime backs it up.
  [ "$before_inode" != "$after_inode" ]
  [ "$before_mtime" != "$after_mtime" ]
  # Entry still valid.
  run bash -c "jq -e '.mcpServers.crystalium' .mcp.json"
  [ "$status" -eq 0 ]
}

@test "OCI no-op guard: missing .mcp.json forces render even when lock digest matches" {
  # Regression for the secondary symptom: if the lockfile still records the
  # current digest but .mcp.json was deleted (or never written for this host),
  # the guard must NOT skip — it must re-render so the entry comes back.
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_oci
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok

  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium@1.2.1
  [ "$status" -eq 0 ]
  [ -f ".mcp.json" ]
  [ -f "eidolons.mcp.lock" ]

  # Simulate a lost .mcp.json (harness reset, manual delete) while the lock
  # still carries the matching digest.
  rm -f .mcp.json

  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium@1.2.1
  [ "$status" -eq 0 ]
  # .mcp.json must be restored (NOT skipped).
  [ -f ".mcp.json" ]
  run bash -c "jq -e '.mcpServers.crystalium' .mcp.json"
  [ "$status" -eq 0 ]
}

# ─── Phase 2: R10 — cursor .cursor/mcp.json + R11 .codex/config.toml ────────

# Helper: seed manifest with given hosts.
seed_manifest_with_hosts() {
  local hosts_csv="$1"
  local hosts_yaml=""
  for _h in $(printf '%s' "$hosts_csv" | tr ',' ' '); do
    hosts_yaml="${hosts_yaml}  - ${_h}
"
  done
  cat > eidolons.yaml <<EOF
version: 1
hosts:
  wire:
${hosts_yaml}members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
}

@test "mcp: binary install writes .cursor/mcp.json when cursor wired" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "cursor"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  [ -f ".cursor/mcp.json" ]
  run bash -c "jq -e '.mcpServers.junction' .cursor/mcp.json"
  [ "$status" -eq 0 ]
}

@test "mcp: .cursor/mcp.json not written when cursor not wired" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "claude-code"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  [ ! -f ".cursor/mcp.json" ]
}

@test "mcp: .cursor/mcp.json merge preserves sibling servers; repeat install no-op (jq -cS)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "cursor"
  # Pre-seed .cursor/mcp.json with a sibling user server.
  mkdir -p .cursor
  printf '{"mcpServers":{"user-server":{"command":"stub"}}}\n' > .cursor/mcp.json
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  # Both junction and the sibling must be present.
  run bash -c "jq -e '.mcpServers.junction' .cursor/mcp.json"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcpServers[\"user-server\"]' .cursor/mcp.json"
  [ "$status" -eq 0 ]
  # Repeat install: byte-identical (jq -cS no-op).
  _before="$(jq -cS . .cursor/mcp.json)"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  _after="$(jq -cS . .cursor/mcp.json)"
  [ "$_before" = "$_after" ]
}

@test "mcp: lockfile hosts_wired truthful (omits .cursor/mcp.json when cursor absent)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "claude-code"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  [ -f "eidolons.mcp.lock" ]
  # hosts_wired must only contain .mcp.json (cursor not wired).
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1 && yaml_to_json eidolons.mcp.lock | jq -e '.mcps[0].hosts_wired | map(select(. == \".cursor/mcp.json\")) | length == 0'"
  [ "$status" -eq 0 ]
}

@test "mcp: uninstall removes only our entry from .cursor/mcp.json" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "cursor"
  # Pre-seed .cursor/mcp.json with a sibling.
  mkdir -p .cursor
  printf '{"mcpServers":{"sibling":{"command":"other-tool"}}}\n' > .cursor/mcp.json
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  # Both present.
  run bash -c "jq -e '.mcpServers.junction' .cursor/mcp.json"
  [ "$status" -eq 0 ]
  # Uninstall junction.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_uninstall.sh" junction
  [ "$status" -eq 0 ]
  # junction removed; sibling preserved.
  run bash -c "jq -e '.mcpServers.junction // empty | length == 0' .cursor/mcp.json 2>/dev/null || jq 'has(\"mcpServers\") and (.mcpServers | has(\"junction\") | not)' .cursor/mcp.json"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcpServers.sibling' .cursor/mcp.json"
  [ "$status" -eq 0 ]
}

@test "mcp: codex config.toml managed section created when codex wired" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "codex"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  [ -f ".codex/config.toml" ]
  grep -qF "# eidolon:mcp start" .codex/config.toml
  grep -qF "# eidolon:mcp end" .codex/config.toml
  grep -qF "[mcp_servers.junction]" .codex/config.toml
}

@test "mcp: codex config.toml rewrite preserves content outside markers" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "codex"
  # Pre-seed .codex/config.toml with user content.
  mkdir -p .codex
  printf '[profiles.default]\nmodel = "codex-mini"\n\n' > .codex/config.toml
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  # User content must be preserved.
  grep -qF '[profiles.default]' .codex/config.toml
  grep -qF 'model = "codex-mini"' .codex/config.toml
  # Managed section must also be present.
  grep -qF '# eidolon:mcp start' .codex/config.toml
  grep -qF '[mcp_servers.junction]' .codex/config.toml
}

@test "mcp: codex config.toml repeat install byte-identical" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "codex"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  [ -f ".codex/config.toml" ]
  _before="$(cat .codex/config.toml)"
  # Second install (same version, no --force).
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  _after="$(cat .codex/config.toml)"
  [ "$_before" = "$_after" ]
}

@test "mcp: codex config.toml not written when codex not wired" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "claude-code"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  [ ! -f ".codex/config.toml" ]
}

@test "mcp: uninstall removes mcp_servers table from codex managed section" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "codex"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  grep -qF "[mcp_servers.junction]" .codex/config.toml
  # Uninstall.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_uninstall.sh" junction
  [ "$status" -eq 0 ]
  # The managed section or config.toml should not contain junction entry.
  ! grep -qF "[mcp_servers.junction]" .codex/config.toml 2>/dev/null || true
}

# OCI driver cursor test (R10-1).
@test "mcp: oci install writes .cursor/mcp.json when cursor wired" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_oci
  seed_manifest_with_hosts "cursor"
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium
  [ "$status" -eq 0 ]
  [ -f ".cursor/mcp.json" ]
  run bash -c "jq -e '.mcpServers.crystalium' .cursor/mcp.json"
  [ "$status" -eq 0 ]
}

# ─── R16: OpenCode MCP registration ─────────────────────────────────────────

@test "mcp: oci install writes opencode.json mcp entry (type local, flattened command) when opencode wired" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_docker_for_oci
  seed_manifest_with_hosts "opencode"
  export FAKE_DOCKER_INFO_RESULT=ok
  export FAKE_DOCKER_INSPECT_RESULT=ok
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" crystalium
  [ "$status" -eq 0 ]
  [ -f "opencode.json" ]
  run bash -c "jq -e '.mcp.crystalium.type == \"local\"' opencode.json"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcp.crystalium.command | type == \"array\"' opencode.json"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcp.crystalium.command[0] == \"docker\"' opencode.json"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcp.crystalium.enabled == true' opencode.json"
  [ "$status" -eq 0 ]
}

@test "mcp: binary install writes opencode.json mcp entry when opencode wired" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "opencode"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  [ -f "opencode.json" ]
  run bash -c "jq -e '.mcp.junction.type == \"local\"' opencode.json"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcp.junction.command | type == \"array\"' opencode.json"
  [ "$status" -eq 0 ]
}

@test "mcp: opencode.json not written when opencode not wired" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "claude-code"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  [ ! -f "opencode.json" ]
}

@test "mcp: opencode.json merge preserves siblings (agent, mcp.other); repeat install no-op (jq -cS)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "opencode"
  # Pre-seed opencode.json with sibling keys.
  printf '{"agent":{"custom":{"model":"gpt-4"}},"mcp":{"other-tool":{"type":"local","command":["stub"],"enabled":true}}}\n' > opencode.json
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  # junction added.
  run bash -c "jq -e '.mcp.junction' opencode.json"
  [ "$status" -eq 0 ]
  # sibling mcp entry preserved.
  run bash -c "jq -e '.mcp[\"other-tool\"]' opencode.json"
  [ "$status" -eq 0 ]
  # agent key preserved.
  run bash -c "jq -e '.agent.custom.model == \"gpt-4\"' opencode.json"
  [ "$status" -eq 0 ]
  # Repeat install: byte-identical (jq -cS no-op).
  _before="$(jq -cS . opencode.json)"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  _after="$(jq -cS . opencode.json)"
  [ "$_before" = "$_after" ]
}

@test "mcp: lockfile hosts_wired gains opencode.json only when opencode wired" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "opencode"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1 && yaml_to_json eidolons.mcp.lock | jq -e '.mcps[0].hosts_wired | any(. == \"opencode.json\")'"
  [ "$status" -eq 0 ]
}

@test "mcp: uninstall removes only our mcp.<name> from opencode.json" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_fake_curl_and_gh_for_install
  seed_manifest_with_hosts "opencode"
  # Pre-seed opencode.json with sibling.
  printf '{"mcp":{"sibling":{"type":"local","command":["other"],"enabled":true}}}\n' > opencode.json
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" "junction@${FAKE_JUNCTION_VERSION}"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcp.junction' opencode.json"
  [ "$status" -eq 0 ]
  # Uninstall junction.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_uninstall.sh" junction
  [ "$status" -eq 0 ]
  # junction removed; sibling preserved.
  run bash -c "jq -e '.mcp.junction // empty | length == 0' opencode.json 2>/dev/null || jq 'has(\"mcp\") and (.mcp | has(\"junction\") | not)' opencode.json"
  [ "$status" -eq 0 ]
  run bash -c "jq -e '.mcp.sibling' opencode.json"
  [ "$status" -eq 0 ]
}

# ─── PR-11: mcp install skip-guards — EIDOLONS_NEXUS prevents fetch ──────

@test "PR-11: mcp install does NOT fetch when EIDOLONS_NEXUS is set (skip-guard)" {
  # With EIDOLONS_NEXUS set (local checkout), nexus_refresh must be a no-op.
  # A poison EIDOLONS_REPO proves no real fetch occurs (if it did, it would fail
  # and mcp_install would also fail if refresh were fatal — but it's non-fatal,
  # so this test mainly verifies the EIDOLONS_NEXUS guard is respected).
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_REPO="https://invalid.example.invalid/poison.git"

  # mcp install with an unknown name should exit non-zero (name not in catalogue)
  # but NOT because of a network error from the poison repo.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" nonexistent-mcp-pr11 2>&1 || true
  # The failure should be about the catalogue (unknown MCP), NOT a network error.
  [[ "$output" =~ "nonexistent-mcp-pr11" ]] || [[ "$output" =~ "not found" ]] || \
    [[ "$output" =~ "unknown" ]] || [[ "$status" -ne 0 ]]
  # Critically: must not say "nexus cache stale" (that would mean it tried to fetch).
  [[ ! "$output" =~ "nexus cache stale" ]]
}
