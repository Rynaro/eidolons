#!/usr/bin/env bats
#
# cli/tests/mcp_verify.bats — ESL change `mcp-verify-lock-vs-artifact` AC suite.
#
# AC-0 / AC-0b (spec): every check here was run against today's `main`
# (unfixed) and shown RED before the fix landed — see the maker's report for
# the exact transcripts (mcp_images.sh's DRIFT tautology genuinely printed
# "no" while wired to a stale digest; doctor's fast path was genuinely silent
# on the same fixture; `eidolons mcp install crystalium` on invalid JSON
# genuinely exited 0 and wrote a lock entry). Every check below is
# two-sided: it flips GREEN when the seeded defect is removed and RED when
# re-seeded, nothing else changed.
#
# FIXTURE-drift builds itself from the real catalogue (reads both atomos
# digests out of roster/mcps.yaml via the CLI's own lib_mcp.sh helpers) so a
# future digest bump cannot rot it: lock = atomos 0.2.0 + catalogue's 0.2.0
# digest; .mcp.json wires the catalogue's 0.1.0 digest.
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.
# See CLAUDE.md §"Bash 3.2 compatibility".

load helpers

# ─── Fixture helpers ──────────────────────────────────────────────────────────

# _atomos_digest VERSION — read atomos's published digest for VERSION straight
# from roster/mcps.yaml (so the fixture cannot rot on a future digest bump).
_atomos_digest() {
  local ver="$1"
  bash -c "
    set -euo pipefail
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    export EIDOLONS_HOME='$EIDOLONS_HOME'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh' >/dev/null 2>&1
    mcp_catalogue_get atomos | jq -r --arg v '$ver' '.versions.releases[\$v].digest'
  "
}

# _write_lock_atomos VERSION DIGEST — seed eidolons.mcp.lock with a single
# atomos oci-image entry.
_write_lock_atomos() {
  local version="$1" digest="$2"
  cat > eidolons.mcp.lock <<EOF
# eidolons.mcp.lock — test fixture
generated_at: "2026-07-13T00:00:00Z"
eidolons_cli_version: "test"
catalogue_version: "1.2"
mcps:
  - name: atomos
    kind: oci-image
    version: "${version}"
    source:
      image: "ghcr.io/rynaro/atomos"
    integrity:
      algo: oci-digest
      value: "${digest}"
    target: ".mcp.json"
    hosts_wired:
      - ".mcp.json"
    installed_at: "2026-07-13T00:00:00Z"
EOF
}

# _write_mcp_json_atomos DIGEST_OR_TAGREF — seed .mcp.json with atomos wired
# to either a "sha256:..." digest (rendered as @<digest>) or a literal
# "<tag>" ref (rendered as :<tag>, the unpinned-tag shape).
_write_mcp_json_atomos() {
  local ref="$1"
  local image_ref
  case "$ref" in
    sha256:*) image_ref="ghcr.io/rynaro/atomos@${ref}" ;;
    *)        image_ref="ghcr.io/rynaro/atomos:${ref}" ;;
  esac
  cat > .mcp.json <<EOF
{
  "mcpServers": {
    "atomos": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "--label", "eidolons.project=test",
        "${image_ref}",
        "serve"
      ]
    }
  }
}
EOF
}

# _add_hand_added_server — append a non-catalogue MCP server entry to the
# existing .mcp.json (AC-8: must never be mentioned by verify's output).
_add_hand_added_server() {
  local tmp
  tmp="$(mktemp)"
  jq '.mcpServers["my-own-thing"] = {"command":"some-random-tool","args":[]}' .mcp.json > "$tmp"
  mv "$tmp" .mcp.json
}

_setup_fixture_drift() {
  _write_lock_atomos "0.2.0" "$ATOMOS_D2"
  _write_mcp_json_atomos "$ATOMOS_D1"
}

_setup_fixture_clean() {
  _write_lock_atomos "0.2.0" "$ATOMOS_D2"
  _write_mcp_json_atomos "$ATOMOS_D2"
}

_setup_fixture_incoherent() {
  # AC-3: lock claims 0.2.0 but carries 0.1.0's digest; .mcp.json wires that
  # SAME 0.1.0 digest, so the wired-vs-locked axis (A) passes on its own.
  _write_lock_atomos "0.2.0" "$ATOMOS_D1"
  _write_mcp_json_atomos "$ATOMOS_D1"
}

# _setup_fixture_junction VER_LOCK VER_WIRED — two junction@<ver> cache dirs,
# lock target pointing at VER_LOCK's binary, .mcp.json wired to VER_WIRED's.
_setup_fixture_junction() {
  local ver_lock="$1" ver_wired="$2"
  local dir_lock="$EIDOLONS_HOME/cache/junction@${ver_lock}"
  local dir_wired="$EIDOLONS_HOME/cache/junction@${ver_wired}"
  mkdir -p "$dir_lock" "$dir_wired"
  cat > "$dir_lock/junction" <<'JSTUB'
#!/usr/bin/env bash
echo "stub-lock"
JSTUB
  chmod +x "$dir_lock/junction"
  cat > "$dir_wired/junction" <<'JSTUB'
#!/usr/bin/env bash
echo "stub-wired"
JSTUB
  chmod +x "$dir_wired/junction"

  cat > eidolons.mcp.lock <<EOF
generated_at: "2026-07-13T00:00:00Z"
eidolons_cli_version: "test"
catalogue_version: "1.2"
mcps:
  - name: junction
    kind: binary
    version: "${ver_lock}"
    source:
      repo: "Rynaro/Junction"
    integrity:
      algo: none
      value: ""
    target: "${dir_lock}/junction"
    hosts_wired:
      - ".mcp.json"
    installed_at: "2026-07-13T00:00:00Z"
EOF

  cat > .mcp.json <<EOF
{
  "mcpServers": {
    "junction": {
      "command": "${dir_wired}/junction",
      "args": ["mcp", "serve"]
    }
  }
}
EOF
  JUNCTION_LOCK_TARGET="${dir_lock}/junction"
}

# ─── Setup / teardown ─────────────────────────────────────────────────────────

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  mkdir -p "$EIDOLONS_HOME"
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"

  ATOMOS_D1="$(_atomos_digest 0.1.0)"
  ATOMOS_D2="$(_atomos_digest 0.2.0)"
  [ -n "$ATOMOS_D1" ]
  [ -n "$ATOMOS_D2" ]
  [ "$ATOMOS_D1" != "$ATOMOS_D2" ]
}

teardown() {
  cd "$EIDOLONS_ROOT"
}

_verify() {
  bash "$EIDOLONS_ROOT/cli/src/mcp_verify.sh" "$@"
}

# ─── AC-1 ─────────────────────────────────────────────────────────────────────

@test "AC-1: FIXTURE-drift -> exit 1, names both digests + the remedy" {
  _setup_fixture_drift
  run _verify
  [ "$status" -eq 1 ]
  [[ "$output" =~ "V-OCI-WIRED-MISMATCH" ]]
  [[ "$output" =~ "$ATOMOS_D1" ]]
  [[ "$output" =~ "$ATOMOS_D2" ]]
  [[ "$output" =~ "eidolons mcp install atomos" ]]
  [[ "$output" =~ "--force" ]]
}

@test "AC-1 two-sided: wired == locked -> exit 0" {
  _setup_fixture_clean
  run _verify
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "V-OCI-WIRED-MISMATCH" ]]
}

@test "AC-1 two-sided: flip one hex char in the wired digest -> exit 1" {
  _setup_fixture_clean
  # Flip the last hex character of the wired digest to a DIFFERENT hex digit
  # (still a valid hex shape) — deterministic regardless of what that digit
  # happens to be.
  local last="${ATOMOS_D2: -1}"
  local stem="${ATOMOS_D2%?}"
  local mutated
  if [ "$last" = "a" ]; then mutated="${stem}b"; else mutated="${stem}a"; fi
  # Ensure we actually changed something.
  [ "$mutated" != "$ATOMOS_D2" ]
  _write_mcp_json_atomos "$mutated"
  run _verify
  [ "$status" -eq 1 ]
  [[ "$output" =~ "V-OCI-WIRED-MISMATCH" ]]
}

# ─── AC-2 / AC-2b ─────────────────────────────────────────────────────────────

@test "AC-2: mcp images on FIXTURE-drift prints DRIFT: yes; --json .drift == \"yes\"" {
  _setup_fixture_drift
  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh" --json
  [ "$status" -eq 0 ]
  run jq -r '.[] | select(.name == "atomos") | .drift' <<< "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "yes" ]
}

@test "AC-2 two-sided: clean fixture -> DRIFT: no (proves not a constant in either direction)" {
  _setup_fixture_clean
  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh" --json
  [ "$status" -eq 0 ]
  run jq -r '.[] | select(.name == "atomos") | .drift' <<< "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "no" ]
}

@test "AC-2b: FIXTURE-drift with docker ENTIRELY absent from PATH -> DRIFT still \"yes\" (the tautology killer)" {
  _setup_fixture_drift

  # Build a PATH mirroring every executable EXCEPT docker (mcp_images.sh
  # resolves the catalogue via yq/jq before ever touching docker, so the full
  # toolset must be mirrored — same technique as mcp_images.bats S11).
  local nodoc="$BATS_TEST_TMPDIR/nodoc-bin"
  mkdir -p "$nodoc"
  local d f b
  IFS=':' read -ra _dirs <<< "$PATH"
  for d in "${_dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -e "$f" ] || continue
      b="$(basename "$f")"
      [ "$b" = "docker" ] && continue
      [ -e "$nodoc/$b" ] || ln -s "$f" "$nodoc/$b" 2>/dev/null || true
    done
  done

  local _saved_path="$PATH"
  PATH="$nodoc"
  run bash "$EIDOLONS_ROOT/cli/src/mcp_images.sh" --json
  PATH="$_saved_path"
  [ "$status" -eq 0 ]
  # Capture the full JSON once — each `run jq ...` below reassigns $output to
  # ITS OWN (narrower) result, so chained queries must all read from this
  # fixed snapshot rather than cascading off one another's $output.
  local img_json="$output"

  run jq -r '.[] | select(.name == "atomos") | .docker_available' <<< "$img_json"
  [ "$output" = "false" ]

  run jq -r '.[] | select(.name == "atomos") | .drift' <<< "$img_json"
  [ "$status" -eq 0 ]
  [ "$output" = "yes" ]

  run jq -r '.[] | select(.name == "atomos") | .drift_axis' <<< "$img_json"
  [ "$output" = "wired_vs_locked" ]
}

# ─── AC-3 ─────────────────────────────────────────────────────────────────────

@test "AC-3: lock claims 0.2.0 but carries 0.1.0's digest (A passes) -> exit 1, V-LOCK-INCOHERENT" {
  _setup_fixture_incoherent
  run _verify
  [ "$status" -eq 1 ]
  [[ "$output" =~ "V-LOCK-INCOHERENT" ]]
  [[ ! "$output" =~ "V-OCI-WIRED-MISMATCH" ]]
}

@test "AC-3 two-sided: coherent lock (clean fixture) -> no V-LOCK-INCOHERENT" {
  _setup_fixture_clean
  run _verify
  [[ ! "$output" =~ "V-LOCK-INCOHERENT" ]]
}

# ─── AC-4 ─────────────────────────────────────────────────────────────────────

@test "AC-4: junction lock 0.4.0 / .mcp.json wired to 0.2.0's binary -> exit 1, V-BIN-WIRED-MISMATCH" {
  _setup_fixture_junction "0.4.0" "0.2.0"
  run _verify
  [ "$status" -eq 1 ]
  [[ "$output" =~ "V-BIN-WIRED-MISMATCH" ]]
}

@test "AC-4 two-sided: re-point .mcp.json to the locked target -> green" {
  _setup_fixture_junction "0.4.0" "0.4.0"
  run _verify
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "V-BIN-WIRED-MISMATCH" ]]
  [[ ! "$output" =~ "V-BIN-TARGET-MISSING" ]]
}

@test "AC-4: delete the (now-matching) target binary -> red with a DIFFERENT code (V-BIN-TARGET-MISSING)" {
  _setup_fixture_junction "0.4.0" "0.4.0"
  rm -f "$JUNCTION_LOCK_TARGET"
  run _verify
  [ "$status" -eq 1 ]
  [[ "$output" =~ "V-BIN-TARGET-MISSING" ]]
  [[ ! "$output" =~ "V-BIN-WIRED-MISMATCH" ]]
}

# ─── AC-5 ─────────────────────────────────────────────────────────────────────

_seed_clean_project_manifest() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: []
members: []
EOF
  cat > eidolons.lock <<EOF
generated_at: "2026-07-13T00:00:00Z"
eidolons_cli_version: "$(tr -d '[:space:]' < "$EIDOLONS_ROOT/VERSION" 2>/dev/null || echo test)"
nexus_commit: "test"
members: []
EOF
}

# AC-5 asserts the WIRING SECTION's own contribution, NOT doctor's global exit.
#
# The first draft asserted `[ "$status" -eq 0 ]` on the clean fixture and
# `-ne 0` on the drift fixture. Both are environment-dependent, and macos-latest
# proved it: doctor there exits non-zero for reasons that have nothing to do with
# this change (no docker on the runner, absent agent files), so
#   * the clean-fixture half FAILED — for a reason we did not cause; and, worse,
#   * the drift half would have PASSED VACUOUSLY — doctor was already non-zero
#     whether or not the wiring section did anything at all.
# A gate whose verdict is decided by the runner is not a gate. Same lesson as
# AC-SL-6 in v2.10.0, wearing different clothes.
#
# So we assert the SECTION's own markers, which no unrelated check can forge:
#   block          -> `err "<mcp>: <msg>"`, and err ALWAYS feeds doctor's exit code
#                     (that is a code-level invariant, not an environmental one)
#   indeterminate  -> "could not fully verify MCP wiring"
#   clean          -> "All locked MCPs verified against .mcp.json"
# These discriminate on every host, including one where doctor is red anyway.

@test "AC-5: doctor (fast, no --deep) on FIXTURE-drift -> the wiring section ERRORS" {
  _setup_fixture_drift
  _seed_clean_project_manifest
  run bash "$EIDOLONS_ROOT/cli/src/doctor.sh"

  # The real signal: the finding was emitted by err(), which prints "✗" AND
  # increments ERRORS (doctor.sh:71) — so an "✗ … wired digest …" line IS the
  # redness, by construction, and no unrelated docker failure can forge it.
  #
  # Assert the MARKER, not just the message. An advisory downgrade (err -> a "·"
  # printf) still prints the same text, so a message-only assertion would pass on
  # any host where doctor is already red for other reasons — i.e. exactly on
  # macos-latest, which is where this class of test fails us. Requiring "✗" on the
  # same line kills that: it goes red on EVERY host when the section stops erroring.
  echo "$output" | grep -q '✗.*wired digest'
  echo "$output" | grep -q '✗.*atomos'
  [ "$status" -ne 0 ]

  # Different axis, still true — a test that passes by making Check 8 red is
  # testing the wrong thing (that is lock-vs-pins.stable; this is
  # lock-vs-artifact). Neither subsumes the other.
  [[ "$output" =~ "All installed MCPs at catalogue stable" ]]
}

@test "AC-5 two-sided: doctor (fast) on the clean fixture -> the wiring section PASSES" {
  _setup_fixture_clean
  _seed_clean_project_manifest
  run bash "$EIDOLONS_ROOT/cli/src/doctor.sh"

  # Section-level, not global-exit: doctor's overall status is the environment's
  # business (macOS CI has no docker), but the wiring section must be clean.
  [[ "$output" =~ "All locked MCPs verified against .mcp.json" ]]
  [[ ! "$output" =~ "wired digest" ]]
}

# ─── AC-6 ─────────────────────────────────────────────────────────────────────

@test "AC-6: valid lock, no .mcp.json -> mcp verify exits exactly 3, prints INDETERMINATE" {
  _write_lock_atomos "0.2.0" "$ATOMOS_D2"
  [ ! -f .mcp.json ]
  run _verify
  [ "$status" -eq 3 ]
  [[ "$output" =~ "INDETERMINATE" ]]
  [[ ! "$output" =~ "OK" ]]
}

@test "AC-6: doctor does NOT redden on INDETERMINATE (valid lock, no .mcp.json)" {
  _write_lock_atomos "0.2.0" "$ATOMOS_D2"
  _seed_clean_project_manifest
  run bash "$EIDOLONS_ROOT/cli/src/doctor.sh"

  # R9: INDETERMINATE must never make the wiring section go red — the fresh-clone
  # state is not a defect. Asserted at the SECTION, not on doctor's global exit:
  # macos-latest exits non-zero here for unrelated reasons (no docker), and an
  # `-eq 0` assertion would fail for something we did not cause while telling us
  # nothing about the check under test.
  [[ "$output" =~ "could not fully verify MCP wiring" ]]
  [[ ! "$output" =~ "wired digest" ]]
}

# ─── AC-7 ─────────────────────────────────────────────────────────────────────

@test "AC-7: locked/no-.mcp.json fixture --strict -> exactly 1" {
  _write_lock_atomos "0.2.0" "$ATOMOS_D2"
  run _verify --strict
  [ "$status" -eq 1 ]
}

@test "AC-7: FIXTURE-drift --strict -> 1" {
  _setup_fixture_drift
  run _verify --strict
  [ "$status" -eq 1 ]
}

@test "AC-7: clean fixture --strict -> 0" {
  _setup_fixture_clean
  run _verify --strict
  [ "$status" -eq 0 ]
}

# ─── AC-8 ─────────────────────────────────────────────────────────────────────

@test "AC-8: clean lock+wiring plus a hand-added mcpServers.my-own-thing -> exit 0, output omits it" {
  _setup_fixture_clean
  _add_hand_added_server
  run _verify
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "my-own-thing" ]]

  run _verify --json
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "my-own-thing" ]]
}

# ─── AC-9 ─────────────────────────────────────────────────────────────────────

@test "AC-9: .mcp.json wires atomos:latest -> default exit 0 + WARN" {
  _write_lock_atomos "0.2.0" "$ATOMOS_D2"
  _write_mcp_json_atomos "latest"
  run _verify
  [ "$status" -eq 0 ]
  [[ "$output" =~ "V-UNPINNED-TAG" ]]
  [[ "$output" =~ "WARN" ]]
}

@test "AC-9 two-sided: same fixture --strict -> 1 (a constant-exit impl fails this)" {
  _write_lock_atomos "0.2.0" "$ATOMOS_D2"
  _write_mcp_json_atomos "latest"
  run _verify --strict
  [ "$status" -eq 1 ]
  [[ "$output" =~ "V-UNPINNED-TAG" ]]
}

# ─── AC-10 ────────────────────────────────────────────────────────────────────

@test "AC-10: mcp verify --json is valid JSON on stdout (stderr discarded); block finding + exit_code shape" {
  _setup_fixture_drift
  run bash -c "bash '$EIDOLONS_ROOT/cli/src/mcp_verify.sh' --json 2>/dev/null | jq empty"
  [ "$status" -eq 0 ]

  run bash -c "bash '$EIDOLONS_ROOT/cli/src/mcp_verify.sh' --json 2>/dev/null"
  [ "$status" -eq 1 ]
  # Snapshot the JSON before the chained `run jq` queries below overwrite
  # $output with their own (narrower) results.
  local verify_json="$output"
  run jq -r '.findings[] | select(.id == "V-OCI-WIRED-MISMATCH") | .severity' <<< "$verify_json"
  [ "$output" = "block" ]
  run jq -r '.summary.exit_code' <<< "$verify_json"
  [ "$output" = "1" ]
}

@test "AC-10: nothing is echoed to stdout besides the JSON report (P0 stdout/stderr discipline)" {
  _setup_fixture_drift
  # If any say/ok/info/warn line leaked to stdout, this jq parse would fail.
  run bash -c "bash '$EIDOLONS_ROOT/cli/src/mcp_verify.sh' --json 2>/dev/null | jq -e 'type == \"object\"'"
  [ "$status" -eq 0 ]
}

# ─── AC-11 — THE INVARIANT ────────────────────────────────────────────────────

setup_fake_docker_for_ac11() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
subcmd="${1:-}"
case "$subcmd" in
  info) exit 0 ;;
  image)
    case "${2:-}" in
      inspect) exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  pull) exit 0 ;;
  *) exit 0 ;;
esac
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
}

@test "AC-11: .mcp.json invalid JSON -> eidolons mcp install crystalium exits non-zero AND the lock gains NO entry" {
  setup_fake_docker_for_ac11
  printf '{ "mcpServers": ' > .mcp.json
  cp .mcp.json .mcp.json.before

  run bash "$EIDOLONS_ROOT/cli/eidolons" mcp install crystalium
  [ "$status" -ne 0 ]

  # .mcp.json is untouched — no data loss, but no lie either.
  diff .mcp.json.before .mcp.json

  # The lock must NOT gain a crystalium entry (the P1 bug, reproduced live
  # against unfixed main: exit 0, .mcp.json untouched, lock entry written
  # anyway).
  if [ -f eidolons.mcp.lock ]; then
    run grep -c 'name: crystalium' eidolons.mcp.lock
    [ "${output:-0}" -eq 0 ]
  fi
}

@test "AC-11 two-sided: repair the JSON -> install exits 0 AND the lock gains the entry" {
  setup_fake_docker_for_ac11
  printf '{}' > .mcp.json

  run bash "$EIDOLONS_ROOT/cli/eidolons" mcp install crystalium
  [ "$status" -eq 0 ]

  run bash -c "jq -e '.mcpServers.crystalium' .mcp.json"
  [ "$status" -eq 0 ]

  [ -f eidolons.mcp.lock ]
  run grep -c 'name: crystalium' eidolons.mcp.lock
  [ "$output" -gt 0 ]
}

@test "AC-11: the same invariant holds for the binary driver (junction) — malformed .mcp.json blocks the lock write" {
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
echo "junction stub: $*"
JBIN
chmod +x "$DEST/junction"
INSTALLER
CURL
  chmod +x "$fake_bin/curl"
  export PATH="$fake_bin:$PATH"

  printf 'NOT VALID JSON {{' > .mcp.json
  cp .mcp.json .mcp.json.before

  run bash "$EIDOLONS_ROOT/cli/eidolons" mcp install junction@0.2.0
  [ "$status" -ne 0 ]
  diff .mcp.json.before .mcp.json
  [ ! -f eidolons.mcp.lock ]
}

# ─── AC-12 ────────────────────────────────────────────────────────────────────

@test "AC-12: mcp verify --help exits 0" {
  run _verify --help
  [ "$status" -eq 0 ]
}

@test "AC-12: mcp_verify.sh has no bash4-only constructs (comments excluded)" {
  local code
  code="$(grep -vE '^[[:space:]]*#' "$EIDOLONS_ROOT/cli/src/mcp_verify.sh")"
  ! printf '%s\n' "$code" | grep -qE 'declare -A|readarray|mapfile|&>>'
  ! printf '%s\n' "$code" | grep -qE '\$\{[a-zA-Z_][a-zA-Z0-9_]*,,\}|\$\{[a-zA-Z_][a-zA-Z0-9_]*\^\^\}'
}

@test "AC-12: unknown mcp verify option -> exit 2 (usage error)" {
  run _verify --nope
  [ "$status" -eq 2 ]
}

@test "AC-12: unknown MCP name -> exit 2 (usage error)" {
  run _verify no-such-mcp-name
  [ "$status" -eq 2 ]
}

# ─── Dispatch wiring sanity ───────────────────────────────────────────────────

@test "eidolons mcp verify is reachable via the CLI dispatcher and mcp.sh usage lists it" {
  run bash "$EIDOLONS_ROOT/cli/src/mcp.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "verify" ]]

  _setup_fixture_clean
  run bash "$EIDOLONS_ROOT/cli/eidolons" mcp verify
  [ "$status" -eq 0 ]
}

# ─── --project-root resolution ────────────────────────────────────────────────

@test "mcp verify --project-root resolves .mcp.json from PATH, not cwd" {
  # The lockfile (like every other 'mcp' subcommand — mcp_lockfile() is
  # cwd-relative by existing, shared convention) is read from cwd: atomos
  # locked at 0.2.0's digest. cwd's OWN .mcp.json is clean (matches).
  _write_lock_atomos "0.2.0" "$ATOMOS_D2"
  _write_mcp_json_atomos "$ATOMOS_D2"

  # A second directory whose .mcp.json wires the STALE 0.1.0 digest instead.
  local other="$BATS_TEST_TMPDIR/other-project"
  mkdir -p "$other"
  cat > "$other/.mcp.json" <<EOF
{"mcpServers":{"atomos":{"command":"docker","args":["run","--rm","-i","ghcr.io/rynaro/atomos@${ATOMOS_D1}","serve"]}}}
EOF

  # Default (cwd's .mcp.json): clean.
  run _verify
  [ "$status" -eq 0 ]

  # --project-root other: must pick up the OTHER .mcp.json (drift), proving
  # the flag actually redirects where the artifact half of the comparison is
  # read from (resolved with the same `cd ... && pwd` idiom as the rest of
  # the CLI) rather than being silently ignored.
  run _verify --project-root "$other"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "V-OCI-WIRED-MISMATCH" ]]
}

# ─── AC-13: --probe must NEVER be mistaken for a pass ──────────────────────
#
# V-PROBE-SURFACE is not implemented in this release. The first draft ACCEPTED
# the flag and merely info'd "(no-op)" — reasoning that it kept `--probe`
# forward-compatible for scripts written against the eventual implementation.
#
# That is the precise defect this whole change exists to kill. The note goes to
# STDERR, which CI routinely discards, so `mcp verify --probe` would exit 0 on a
# clean project and read as "the served tool surface was verified" when nothing
# was probed at all. A check that cannot run must never be scored as a pass —
# least of all by the verb whose entire job is enforcing that rule.
#
# These pin BOTH halves: it fails, and it fails even when nobody is reading
# stderr. A future implementer who wires the probe up flips these to assert the
# real behaviour; nobody gets a silent green in the meantime.

@test "AC-13: mcp verify --probe exits 2 (never 0) on a CLEAN project" {
  _setup_fixture_clean
  _seed_clean_project_manifest
  run bash "$EIDOLONS_ROOT/cli/src/mcp_verify.sh" --probe
  # The clean fixture is exactly the case that would otherwise exit 0 and look
  # like a verified tool surface. Assert the literal code, not just non-zero.
  [ "$status" -eq 2 ]
  [[ "$output" =~ "not implemented" ]]
}

@test "AC-13b: --probe still exits 2 with stderr discarded (the CI case)" {
  _setup_fixture_clean
  _seed_clean_project_manifest
  run bash -c "bash '$EIDOLONS_ROOT/cli/src/mcp_verify.sh' --probe 2>/dev/null"
  [ "$status" -eq 2 ]
}

@test "AC-13c: --probe fails BEFORE emitting any verdict" {
  # It must not print a report and then exit 2 — a caller scraping stdout would
  # read a verdict that silently omitted the probe they asked for.
  _setup_fixture_drift
  _seed_clean_project_manifest
  run bash -c "bash '$EIDOLONS_ROOT/cli/src/mcp_verify.sh' --probe 2>/dev/null"
  [ "$status" -eq 2 ]
  [[ ! "$output" =~ "V-OCI-WIRED-MISMATCH" ]]
  [[ ! "$output" =~ "Summary:" ]]
}

# ─── AC-14: R2 (the read-back) must be pinned ON ITS OWN ───────────────────
#
# AC-11 does NOT pin R2. Its fixture is invalid `.mcp.json`, which trips R1
# (_mcp_merge_into_json_file returns non-zero) and short-circuits BEFORE the
# read-back is ever reached. Proof: neuter `_mcp_oci_confirm_wired` to `return 0`
# — deleting the F5 invariant's core gate — and the ENTIRE suite stays green.
# The two gates are layered defence, and only the OUTER one was tested.
#
# R2 is the GENERAL gate and the one F5 actually names: R1 only catches "the
# merge failed"; R2 catches "the merge SUCCEEDED but the artifact does not say
# what we intended". That second class is real — a template regression baking a
# stale or mutable ref writes perfectly valid JSON and R1 waves it through.
#
# So: a temp nexus whose atomos template hardcodes 0.1.0's digest instead of the
# __IMAGE_DIGEST__ placeholder. Installing atomos@0.2.0 through it produces a
# VALID .mcp.json (R1 is happy) that wires the WRONG image. Only the read-back
# can convict it — and it must, by refusing to write the lock.

_build_doctored_nexus() {   # $1 = digest to hardcode into the atomos template
  local bad_digest="$1"
  local nx="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$nx"
  cp -R "$EIDOLONS_ROOT/cli" "$nx/cli"
  cp -R "$EIDOLONS_ROOT/roster" "$nx/roster"
  # The regression: bake a fixed digest where the placeholder belongs.
  sed "s|__IMAGE_DIGEST__|${bad_digest}|g" \
    "$EIDOLONS_ROOT/cli/templates/mcp/atomos.mcp.json.tmpl" \
    > "$nx/cli/templates/mcp/atomos.mcp.json.tmpl"
  printf '%s' "$nx"
}

@test "AC-14: template wires the WRONG digest (merge SUCCEEDS) -> install fails, lock gains NO entry" {
  setup_fake_docker_for_ac11
  local nx; nx="$(_build_doctored_nexus "$ATOMOS_D1")"   # template bakes 0.1.0 ...
  export EIDOLONS_NEXUS="$nx"
  printf '{"mcpServers":{}}\n' > .mcp.json

  # ... while we ask for 0.2.0.
  run bash "$nx/cli/eidolons" mcp install atomos@0.2.0
  [ "$status" -ne 0 ]

  # R1 CANNOT have fired: the merge succeeded and produced valid JSON.
  # This is what makes the test a gate on R2 specifically.
  jq empty .mcp.json
  run jq -r '.mcpServers.atomos.args[] | select(startswith("ghcr.io/rynaro/atomos@"))' .mcp.json
  [[ "$output" == *"$ATOMOS_D1"* ]]   # the artifact really does carry the WRONG digest

  # The invariant: the installer is not permitted to witness its own success.
  # It wrote something other than what it intended, so it must NOT record it.
  if [ -f eidolons.mcp.lock ]; then
    run grep -c 'name: atomos' eidolons.mcp.lock
    [ "${output:-0}" -eq 0 ]
  fi
}

@test "AC-14 two-sided: an HONEST template (placeholder intact) -> install succeeds AND the lock records it" {
  setup_fake_docker_for_ac11
  local nx="$BATS_TEST_TMPDIR/nexus-ok"
  mkdir -p "$nx"
  cp -R "$EIDOLONS_ROOT/cli" "$nx/cli"
  cp -R "$EIDOLONS_ROOT/roster" "$nx/roster"
  export EIDOLONS_NEXUS="$nx"
  printf '{"mcpServers":{}}\n' > .mcp.json

  run bash "$nx/cli/eidolons" mcp install atomos@0.2.0
  [ "$status" -eq 0 ]

  run jq -r '.mcpServers.atomos.args[] | select(startswith("ghcr.io/rynaro/atomos@"))' .mcp.json
  [[ "$output" == *"$ATOMOS_D2"* ]]
  grep -q 'name: atomos' eidolons.mcp.lock
}
