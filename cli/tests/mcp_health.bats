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

# ═══════════════════════════════════════════════════════════════════════════
# UID/GID and bind-path probe coverage (re-implementation in
# mcp_driver_oci_image_health via _mcp_driver_oci_uid_bind_probes).
#
# These tests verify that the new probes surface in the health output when
# .mcp.json is present with an atlas-aci key.
# ═══════════════════════════════════════════════════════════════════════════

# Helper: fake docker shim that always succeeds, enabling the image-local
# branch in mcp_driver_oci_image_health so the UID/bind probes are reached.
_setup_fake_docker_for_uid_probe() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin-docker-uid"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'DSHIM'
#!/usr/bin/env bash
subcmd="${1:-}"
case "$subcmd" in
  info)           exit 0 ;;
  image)          exit 0 ;;
  *)              exit 0 ;;
esac
DSHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
}

# Helper: seed a minimal atlas-aci MCP lock entry.
_seed_atlas_aci_lock() {
  local digest="sha256:386677f06b0ce23cb4883f6c0f91d8eac22328cd7d9451ae241e2f183207ad96"
  cat > eidolons.mcp.lock <<EOF
# eidolons.mcp.lock
generated_at: "2026-05-19T00:00:00Z"
eidolons_cli_version: "1.3.0"
catalogue_version: "1.0"
mcps:
  - name: atlas-aci
    kind: oci-image
    version: "0.2.2"
    source:
      image: "ghcr.io/rynaro/atlas-aci"
    integrity:
      algo: sha256
      value: "${digest}"
    hosts_wired:
      - ".mcp.json"
    installed_at: "2026-05-19T00:00:00Z"
EOF
}

# Helper: write .mcp.json for atlas-aci with given uid_gid (or omit if empty)
# and optional bind specs (each as "host:container").
_seed_mcp_json_uid() {
  local uid_gid="$1"
  shift
  local digest="sha256:386677f06b0ce23cb4883f6c0f91d8eac22328cd7d9451ae241e2f183207ad96"
  local args_json
  args_json='["run","--rm","-i"'
  if [ -n "$uid_gid" ]; then
    args_json="${args_json},\"-u\",\"${uid_gid}\""
  fi
  for bind_spec in "$@"; do
    args_json="${args_json},\"-v\",\"${bind_spec}\""
  done
  args_json="${args_json},\"ghcr.io/rynaro/atlas-aci@${digest}\",\"serve\"]"
  cat > .mcp.json <<EOF
{
  "mcpServers": {
    "atlas-aci": {
      "command": "docker",
      "args": ${args_json}
    }
  }
}
EOF
}

# ═══════════════════════════════════════════════════════════════════════════
# Regression coverage: _mcp_driver_oci_uid_bind_probes must honor $name and
# NOT hardcode "atlas-aci" — the exact defect that let tonberry/atomos report
# fully green under 'eidolons mcp health'/'eidolons doctor' while their
# .mcp.json entries carried no --user pin at all (every container write
# failing with EACCES/EPERM against the UID-1000 workspace bind mount).
# ═══════════════════════════════════════════════════════════════════════════

# Helper: seed a minimal tonberry MCP lock entry (kind: oci-image, same shape
# as atlas-aci's, just a different name/image — tonberry is one of the three
# workspace-binding OCI servers named in the fix).
_seed_tonberry_lock() {
  local digest="sha256:55dd2fed08070461e1f3b92c303128a0ae1f3c1b62165fd07d0c327e7b1f94f9"
  cat > eidolons.mcp.lock <<EOF
# eidolons.mcp.lock
generated_at: "2026-05-19T00:00:00Z"
eidolons_cli_version: "1.3.0"
catalogue_version: "1.0"
mcps:
  - name: tonberry
    kind: oci-image
    version: "0.5.2"
    source:
      image: "ghcr.io/rynaro/tonberry"
    integrity:
      algo: sha256
      value: "${digest}"
    hosts_wired:
      - ".mcp.json"
    installed_at: "2026-05-19T00:00:00Z"
EOF
}

# Helper: write .mcp.json for tonberry with given uid_gid (or omit if empty)
# and optional bind specs (each as "host:container"). Mirrors _seed_mcp_json_uid
# but keys the mcpServers entry as "tonberry" instead of "atlas-aci" — this is
# the shape that exposed the hardcoded-name regression.
_seed_mcp_json_uid_tonberry() {
  local uid_gid="$1"
  shift
  local digest="sha256:55dd2fed08070461e1f3b92c303128a0ae1f3c1b62165fd07d0c327e7b1f94f9"
  local args_json
  args_json='["run","--rm","-i"'
  if [ -n "$uid_gid" ]; then
    args_json="${args_json},\"-u\",\"${uid_gid}\""
  fi
  for bind_spec in "$@"; do
    args_json="${args_json},\"-v\",\"${bind_spec}\""
  done
  args_json="${args_json},\"ghcr.io/rynaro/tonberry@${digest}\",\"serve\"]"
  cat > .mcp.json <<EOF
{
  "mcpServers": {
    "tonberry": {
      "command": "docker",
      "args": ${args_json}
    }
  }
}
EOF
}

@test "mcp health uid-probe: NON-atlas-aci server (tonberry) — no -u flag → mcp_uid_pin warn (regression guard)" {
  setup_mcp_env
  _setup_fake_docker_for_uid_probe
  _seed_tonberry_lock
  _seed_mcp_json_uid_tonberry ""  # omit -u pair

  run eidolons mcp health tonberry
  [ "$status" -eq 0 ]  # health always exits 0
  # Must actually surface a tonberry-scoped probe line — NOT silently skip it
  # the way the hardcoded-"atlas-aci" defect did for every non-atlas-aci name.
  echo "$output" | grep -q "^tonberry  mcp_uid_pin.*warn"
  [[ "$output" =~ "no -u UID:GID pin" ]]
  [[ "$output" =~ "eidolons mcp install tonberry --force" ]]
}

@test "mcp health uid-probe: NON-atlas-aci server (tonberry) — matching UID:GID → mcp_uid_pin ok (regression guard)" {
  setup_mcp_env
  _setup_fake_docker_for_uid_probe
  _seed_tonberry_lock
  cur_uid="$(id -u)"
  cur_gid="$(id -g)"
  _seed_mcp_json_uid_tonberry "${cur_uid}:${cur_gid}"

  run eidolons mcp health tonberry
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^tonberry  mcp_uid_pin.*ok"
  [[ ! "$output" =~ "no -u UID:GID pin" ]]
}

@test "mcp health uid-probe: matching UID:GID → mcp_uid_pin ok" {
  setup_mcp_env
  _setup_fake_docker_for_uid_probe
  _seed_atlas_aci_lock
  cur_uid="$(id -u)"
  cur_gid="$(id -g)"
  _seed_mcp_json_uid "${cur_uid}:${cur_gid}"

  run eidolons mcp health atlas-aci
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "mcp_uid_pin"
  echo "$output" | grep -q "mcp_uid_pin.*ok"
  [[ ! "$output" =~ "no -u UID:GID pin" ]]
  [[ ! "$output" =~ "pins --user" ]]
}

@test "mcp health uid-probe: mismatched UID:GID → mcp_uid_pin err with both UIDs" {
  setup_mcp_env
  _setup_fake_docker_for_uid_probe
  _seed_atlas_aci_lock
  cur_uid="$(id -u)"
  cur_gid="$(id -g)"
  _seed_mcp_json_uid "99999:99999"

  run eidolons mcp health atlas-aci
  [ "$status" -eq 0 ]  # health always exits 0
  echo "$output" | grep -q "mcp_uid_pin.*err"
  [[ "$output" =~ "pins --user 99999:99999" ]]
  [[ "$output" =~ "${cur_uid}:${cur_gid}" ]]
}

@test "mcp health uid-probe: no -u flag → mcp_uid_pin warn with re-install hint" {
  setup_mcp_env
  _setup_fake_docker_for_uid_probe
  _seed_atlas_aci_lock
  _seed_mcp_json_uid ""  # omit -u pair

  run eidolons mcp health atlas-aci
  [ "$status" -eq 0 ]  # health always exits 0
  echo "$output" | grep -q "mcp_uid_pin.*warn"
  [[ "$output" =~ "no -u UID:GID pin" ]]
  [[ "$output" =~ "eidolons mcp install atlas-aci --force" ]]
}

@test "mcp health uid-probe: bind path missing → mcp_bind_path_exists err" {
  setup_mcp_env
  _setup_fake_docker_for_uid_probe
  _seed_atlas_aci_lock
  cur_uid="$(id -u)"
  cur_gid="$(id -g)"
  local nonexistent="/tmp/eidolons-mh-uid-nonexistent-$$"
  rm -rf "$nonexistent"
  _seed_mcp_json_uid "${cur_uid}:${cur_gid}" "${nonexistent}:/repo"

  run eidolons mcp health atlas-aci
  [ "$status" -eq 0 ]  # health always exits 0
  echo "$output" | grep -q "mcp_bind_path_exists.*err"
  [[ "$output" =~ "does not exist" ]]
  [[ "$output" =~ "$nonexistent" ]]
}

@test "mcp health uid-probe: no .mcp.json → uid probes silently absent" {
  setup_mcp_env
  _setup_fake_docker_for_uid_probe
  _seed_atlas_aci_lock
  # No .mcp.json written.

  run eidolons mcp health atlas-aci
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "mcp_uid_pin" ]]
  [[ ! "$output" =~ "mcp_bind_path" ]]
}
