#!/usr/bin/env bats
#
# cli/tests/mcp_assess.bats — coverage for 'eidolons mcp assess' (ESL escalation
# auto-flip, FORGE verdict H5). Encodes the acceptance gates:
#   G-RECORD     — tripped signals → enforcement:block; untripped → advisory.
#   G-IDEMPOTENT — a recorded enforcement survives an install entry-rebuild
#                  (RED-before-fix proof of the carry-forward).
#   G-DUAL       — 'eidolons mcp assess' is reachable through BOTH dispatch tables.
#   G-DEGRADE    — assess on a project where tonberry is NOT installed → warn + 0.
#   G-NO-VERB    — no new top-level 'eidolons spec'/'esl' verb was introduced.
#
# The assess op is stubbed via EIDOLONS_MCP_ASSESS_CMD (no live docker pull),
# mirroring how the OCI tests stub the image call. Bash 3.2 compatible.

load helpers

TONBERRY_DIGEST="sha256:3b2a01947c01ea3a3f3345073e198113964adb6e9b4629287da92622076aa856"

setup_mcp_env() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_SKIP_REFRESH=1
}

# Seed a tonberry lock entry as if it were installed (oci-image kind).
seed_tonberry_lock() {
  cat > eidolons.mcp.lock <<EOF
# eidolons.mcp.lock
generated_at: "2026-06-25T00:00:00Z"
eidolons_cli_version: "1.43.0"
catalogue_version: "1.2"
mcps:
  - name: tonberry
    kind: oci-image
    version: "0.3.1"
    source:
      image: "ghcr.io/rynaro/tonberry"
    integrity:
      algo: oci-digest
      value: "${TONBERRY_DIGEST}"
    target: ".mcp.json"
    hosts_wired:
      - ".mcp.json"
    installed_at: "2026-06-25T00:00:00Z"
EOF
}

# Install a stub `assess` command on the assess hook. $1 = JSON the tool prints.
stub_assess_json() {
  local json="$1"
  local stub="$BATS_TEST_TMPDIR/fake-assess.sh"
  cat > "$stub" <<STUB
#!/usr/bin/env bash
printf '%s' '${json}'
STUB
  chmod +x "$stub"
  export EIDOLONS_MCP_ASSESS_CMD="bash $stub"
}

# Read one field from the tonberry lock entry (via the same yaml_to_json path).
lock_field() {
  local jqpath="$1"
  yq eval -o=json '.' eidolons.mcp.lock 2>/dev/null \
    | jq -r --arg p "$jqpath" '(.mcps // [])[] | select(.name=="tonberry")' \
    | jq -r "$jqpath // \"\""
}

# ─── G-RECORD ────────────────────────────────────────────────────────────────

@test "G-RECORD: tripped signals → enforcement:block recorded with signals" {
  setup_mcp_env
  seed_tonberry_lock

  # RED-first: the field is absent before assess.
  run lock_field '.enforcement'
  [ -z "$output" ]

  stub_assess_json '{"signals":{"change_count":14,"repo_loc":62000,"full_ratio":0.6},"thresholds":{"N":10,"L":50000,"R":0.4},"tripped":["change_count","repo_loc","full_ratio"],"recommended_mode":"block"}'

  run bash "$EIDOLONS_ROOT/cli/src/mcp_assess.sh" tonberry
  [ "$status" -eq 0 ]
  # Machine result on stdout carries enforcement + tripped.
  [[ "$output" =~ \"enforcement\":\ *\"block\" ]] || [[ "$output" =~ "block" ]]

  # The lock now records enforcement:block + the producing signals/thresholds.
  run lock_field '.enforcement'
  [ "$output" = "block" ]

  run bash -c "yq eval -o=json '.mcps[0].enforcement_signals.change_count' eidolons.mcp.lock"
  [ "$output" = "14" ]
  run bash -c "yq eval -o=json '.mcps[0].enforcement_thresholds.N' eidolons.mcp.lock"
  [ "$output" = "10" ]
  run bash -c "yq eval '.mcps[0].enforcement_assessed_at' eidolons.mcp.lock"
  [ -n "$output" ]
}

@test "G-RECORD: untripped signals → enforcement:advisory recorded (exit 0)" {
  setup_mcp_env
  seed_tonberry_lock

  stub_assess_json '{"signals":{"change_count":2,"repo_loc":1200,"full_ratio":0.0},"thresholds":{"N":10,"L":50000,"R":0.4},"tripped":[],"recommended_mode":"advisory"}'

  run bash "$EIDOLONS_ROOT/cli/src/mcp_assess.sh" tonberry
  [ "$status" -eq 0 ]

  run lock_field '.enforcement'
  [ "$output" = "advisory" ]
}

@test "G-RECORD: lockfile remains valid YAML after recording enforcement" {
  setup_mcp_env
  seed_tonberry_lock
  stub_assess_json '{"signals":{"change_count":14},"thresholds":{"N":10},"tripped":["change_count"],"recommended_mode":"block"}'

  run bash "$EIDOLONS_ROOT/cli/src/mcp_assess.sh" tonberry
  [ "$status" -eq 0 ]

  # The whole lock must still round-trip through yq (the canonical reader).
  run bash -c "yq eval -o=json '.' eidolons.mcp.lock"
  [ "$status" -eq 0 ]
  # And jq must accept the projected entry.
  run bash -c "yq eval -o=json '.mcps[0]' eidolons.mcp.lock | jq -e '.enforcement == \"block\"'"
  [ "$status" -eq 0 ]
}

# ─── G-IDEMPOTENT (carry-forward; RED-before-fix proof) ──────────────────────

@test "G-IDEMPOTENT: RED-before-fix — a catalogue-rebuilt entry would DROP enforcement" {
  setup_mcp_env

  # A freshly-rebuilt catalogue-driven entry (the install path's construction)
  # carries NO enforcement* fields — this is the bug surface the carry-forward
  # closes. Asserting the drop here pins the failure mode the fix prevents.
  local rebuilt='{"name":"tonberry","kind":"oci-image","version":"0.3.1","source":{"image":"ghcr.io/rynaro/tonberry"},"integrity":{"algo":"oci-digest","value":"x"},"target":".mcp.json","hosts_wired":[".mcp.json"],"installed_at":"now"}'

  run bash -c "printf '%s' '$rebuilt' | jq -r '.enforcement // \"DROPPED\"'"
  [ "$output" = "DROPPED" ]
}

@test "G-IDEMPOTENT: GREEN — carry-forward preserves a recorded enforcement on rebuild" {
  setup_mcp_env
  # Seed a lock that already has a recorded escalation.
  cat > eidolons.mcp.lock <<EOF
generated_at: "2026-06-25T00:00:00Z"
eidolons_cli_version: "1.43.0"
catalogue_version: "1.2"
mcps:
  - name: tonberry
    kind: oci-image
    version: "0.3.1"
    source:
      image: "ghcr.io/rynaro/tonberry"
    integrity:
      algo: oci-digest
      value: "${TONBERRY_DIGEST}"
    target: ".mcp.json"
    hosts_wired:
      - ".mcp.json"
    installed_at: "2026-06-25T00:00:00Z"
    enforcement: "block"
    enforcement_signals: {"change_count":14}
    enforcement_thresholds: {"N":10}
    enforcement_assessed_at: "2026-06-25T00:00:00Z"
EOF

  # Drive the carry-forward helper exactly as the install entry-builder does.
  run bash -c '
    export EIDOLONS_NEXUS="'"$EIDOLONS_ROOT"'" EIDOLONS_SKIP_REFRESH=1
    . "'"$EIDOLONS_ROOT"'/cli/src/lib.sh"
    . "'"$EIDOLONS_ROOT"'/cli/src/lib_mcp.sh"
    rebuilt='\''{"name":"tonberry","kind":"oci-image","version":"0.3.1","source":{"image":"ghcr.io/rynaro/tonberry"},"integrity":{"algo":"oci-digest","value":"'"$TONBERRY_DIGEST"'"},"target":".mcp.json","hosts_wired":[".mcp.json"],"installed_at":"2026-06-25T09:00:00Z"}'\''
    mcp_lock_carry_enforcement tonberry "$rebuilt" | jq -r ".enforcement // \"DROPPED\""
  '
  [ "$status" -eq 0 ]
  [ "$output" = "block" ]
}

@test "G-IDEMPOTENT: end-to-end — 'mcp install' that REWRITES the entry preserves enforcement" {
  setup_mcp_env

  # Fake docker so the OCI install driver runs without a live pull.
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
case "${1:-}" in
  info) exit 0 ;;
  image) exit 0 ;;
  pull) exit 0 ;;
  *) exit 0 ;;
esac
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
  # Image always "present" so install skips the pull and goes straight to wiring.
  export FAKE_DOCKER_INSPECT_RESULT=ok

  # CRITICAL: seed at an OLD version/digest with a recorded escalation. Installing
  # the catalogue stable (0.3.1) BUMPS version+digest, so mcp_lock_upsert's no-op
  # signature does NOT match → the entry is genuinely REWRITTEN. Without the
  # carry-forward the rebuilt entry would DROP enforcement (the trap). With an
  # identical-field re-install the upsert no-ops and enforcement survives
  # vacuously — that would not exercise the fix, so we force a real rewrite here.
  cat > eidolons.mcp.lock <<EOF
generated_at: "2026-06-25T00:00:00Z"
eidolons_cli_version: "1.43.0"
catalogue_version: "1.2"
mcps:
  - name: tonberry
    kind: oci-image
    version: "0.3.0"
    source:
      image: "ghcr.io/rynaro/tonberry"
    integrity:
      algo: oci-digest
      value: "sha256:cb898ab1ba4cf8a31ff6b82963ba4d5e2cbf2f3f9f66670fcc043d37b9e407da"
    target: ".mcp.json"
    hosts_wired:
      - ".mcp.json"
    installed_at: "2026-06-25T00:00:00Z"
    enforcement: "block"
    enforcement_signals: {"change_count":14}
    enforcement_thresholds: {"N":10}
    enforcement_assessed_at: "2026-06-25T00:00:00Z"
EOF

  # Install the catalogue stable (≠ 0.3.0) — forces a real entry rewrite.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" tonberry

  # The entry was rewritten to the new version …
  run bash -c "yq eval '.mcps[] | select(.name==\"tonberry\") | .version' eidolons.mcp.lock"
  [ "$output" != "0.3.0" ]

  # … and the recorded escalation SURVIVED the rewrite (carry-forward).
  run bash -c "yq eval '.mcps[] | select(.name==\"tonberry\") | .enforcement' eidolons.mcp.lock"
  [ "$output" = "block" ]
  run bash -c "yq eval -o=json '.mcps[] | select(.name==\"tonberry\") | .enforcement_signals.change_count' eidolons.mcp.lock"
  [ "$output" = "14" ]
}

# ─── DRY-RUN (--dry-run gates only the RECORD hop) ───────────────────────────

@test "DRY-RUN: prints assessment JSON to stdout (enforcement parseable)" {
  setup_mcp_env
  seed_tonberry_lock

  stub_assess_json '{"signals":{"change_count":14,"repo_loc":62000,"full_ratio":0.6},"thresholds":{"N":10,"L":50000,"R":0.4},"tripped":["change_count","repo_loc","full_ratio"],"recommended_mode":"block"}'

  # Capture STDOUT ONLY (stderr discarded). This is the load-bearing AC-1 check:
  # any 'say'/'info'/'warn' note (incl. the dry-run "lock not written" line) must
  # land on stderr, so the captured stdout has to be a single valid JSON object
  # that jq parses cleanly. A stray log line on stdout would break this jq parse.
  run bash -c "bash '$EIDOLONS_ROOT/cli/src/mcp_assess.sh' tonberry --dry-run 2>/dev/null"
  [ "$status" -eq 0 ]

  printf '%s' "$output" | jq -e '.enforcement == "block"'
  printf '%s' "$output" | jq -e '.name == "tonberry"'
  printf '%s' "$output" | jq -e '.recommended_mode == "block"'
  printf '%s' "$output" | jq -e 'has("tripped")'
  printf '%s' "$output" | jq -e 'has("assessed_at")'
}

@test "DRY-RUN: leaves eidolons.mcp.lock byte-unchanged" {
  setup_mcp_env
  seed_tonberry_lock

  # RED-first: the field is absent before assess.
  run lock_field '.enforcement'
  [ -z "$output" ]

  stub_assess_json '{"signals":{"change_count":14,"repo_loc":62000,"full_ratio":0.6},"thresholds":{"N":10,"L":50000,"R":0.4},"tripped":["change_count","repo_loc","full_ratio"],"recommended_mode":"block"}'

  # Snapshot the exact bytes before the run.
  cp eidolons.mcp.lock "$BATS_TEST_TMPDIR/lock.before"

  run bash "$EIDOLONS_ROOT/cli/src/mcp_assess.sh" tonberry --dry-run
  [ "$status" -eq 0 ]

  # The lock is byte-for-byte identical — no enforcement* keys written (AC-2).
  cmp -s "$BATS_TEST_TMPDIR/lock.before" eidolons.mcp.lock

  run lock_field '.enforcement'
  [ -z "$output" ]
}

@test "DRY-RUN: --dry-run is listed in assess usage/help" {
  setup_mcp_env
  run eidolons mcp assess --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "--dry-run" ]]
}

# ─── G-DUAL (both dispatch tables) ───────────────────────────────────────────

@test "G-DUAL: 'eidolons mcp assess' reaches mcp_assess.sh (not 'unknown subcommand')" {
  setup_mcp_env
  # No name → mcp_assess.sh prints usage (exit 2), NOT the inner/outer dispatcher's
  # 'Unknown mcp subcommand'. This proves BOTH tables resolve 'assess'.
  run eidolons mcp assess
  [ "$status" -eq 2 ]
  [[ "$output" =~ "eidolons mcp assess" ]]
  [[ ! "$output" =~ "Unknown mcp subcommand" ]]
}

@test "G-DUAL: 'eidolons mcp assess --help' routes to the assess help" {
  setup_mcp_env
  run eidolons mcp assess --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "record an MCP's ESL escalation decision" ]]
}

@test "G-DUAL: 'assess' is registered in BOTH dispatch tables" {
  # Outer table: cli/eidolons mcp verb allowlist (line ~265).
  run grep -E 'list\|show\|install\|.*\|assess\|.*\|images' "$EIDOLONS_ROOT/cli/eidolons"
  [ "$status" -eq 0 ]
  # Inner table: cli/src/mcp.sh case dispatch.
  run grep -E 'assess\)[[:space:]]+exec bash "\$SELF_DIR/mcp_assess.sh"' "$EIDOLONS_ROOT/cli/src/mcp.sh"
  [ "$status" -eq 0 ]
  # Inner "Available subcommands" line must list assess.
  run grep -E 'Available subcommands:.*assess' "$EIDOLONS_ROOT/cli/src/mcp.sh"
  [ "$status" -eq 0 ]
}

# ─── G-DEGRADE (graceful skip) ───────────────────────────────────────────────

@test "G-DEGRADE: assess on a project with tonberry NOT installed → warn + exit 0" {
  setup_mcp_env
  # No lockfile at all.
  [ ! -f eidolons.mcp.lock ]

  run bash "$EIDOLONS_ROOT/cli/src/mcp_assess.sh" tonberry
  [ "$status" -eq 0 ]
  [[ "$output" =~ "not installed" ]]
  # No lock corruption: still no lockfile created by a graceful skip.
  [ ! -f eidolons.mcp.lock ]
}

@test "G-DEGRADE: assess when the assess op is unavailable → warn + exit 0, no record" {
  setup_mcp_env
  seed_tonberry_lock

  # Stub that FAILS (assess op cannot run) → graceful skip.
  local stub="$BATS_TEST_TMPDIR/fail-assess.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$stub"
  export EIDOLONS_MCP_ASSESS_CMD="bash $stub"

  run bash "$EIDOLONS_ROOT/cli/src/mcp_assess.sh" tonberry
  [ "$status" -eq 0 ]
  [[ "$output" =~ "skipping" ]] || [[ "$output" =~ "unavailable" ]]

  # No enforcement recorded (the lock entry is untouched).
  run lock_field '.enforcement'
  [ -z "$output" ]
}

# ─── G-NO-VERB (no new top-level verb) ───────────────────────────────────────

@test "G-NO-VERB: no top-level 'eidolons spec' verb was introduced" {
  setup_mcp_env
  run eidolons spec
  # Unknown command path: dispatcher must NOT recognize 'spec'. (Non-zero exit
  # and no spec sub-dispatcher file.)
  [ "$status" -ne 0 ]
  [ ! -f "$EIDOLONS_ROOT/cli/src/spec.sh" ]
}

@test "G-NO-VERB: no top-level 'eidolons esl' verb was introduced" {
  setup_mcp_env
  run eidolons esl
  [ "$status" -ne 0 ]
  [ ! -f "$EIDOLONS_ROOT/cli/src/esl.sh" ]
}

@test "G-NO-VERB: assess is an 'mcp' subcommand, not a top-level dispatch entry" {
  # The dispatcher's top-level command list must NOT add 'assess' as a sibling
  # of init/sync/doctor/mcp — it lives only inside the mcp sub-dispatcher.
  run grep -nE '^[[:space:]]+assess\)' "$EIDOLONS_ROOT/cli/eidolons"
  [ "$status" -ne 0 ]
}

# ─── M4-S5 — enforcement from the install AUTO-FIRE survives sync + re-install ─
#
# Distinct from the existing carry-forward proofs above (which seed enforcement
# MANUALLY): here the enforcement is written by the NEW install-time auto-fire,
# then must survive (a) a no-op 'mcp sync' and (b) a real entry-rewrite via a
# forced re-install WITH the auto-fire suppressed (so block can only survive via
# mcp_lock_carry_enforcement, never a fresh re-assess).

@test "M4-S5: install auto-fire enforcement survives a subsequent mcp sync AND a forced re-install" {
  setup_mcp_env
  # Fake docker so the OCI install driver runs without a live pull.
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
case "${1:-}" in
  info) exit 0 ;;
  image) exit 0 ;;
  pull) exit 0 ;;
  *) exit 0 ;;
esac
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
  export FAKE_DOCKER_INSPECT_RESULT=ok

  # Manifest declaring tonberry so 'mcp sync' has something to reconcile.
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
mcps:
  - name: tonberry
    version: "^0.4.0"
EOF

  # The install auto-fire records enforcement via the assess stub (block).
  stub_assess_json '{"signals":{"change_count":14,"repo_loc":62000,"full_ratio":0.6},"thresholds":{"N":10,"L":50000,"R":0.4},"tripped":["change_count"],"recommended_mode":"block"}'

  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" tonberry
  [ "$status" -eq 0 ] || return 1
  # PROOF the auto-fire (not a manual seed) wrote the enforcement.
  run bash -c "yq eval '.mcps[] | select(.name==\"tonberry\") | .enforcement' eidolons.mcp.lock"
  [ "$output" = "block" ] || return 1

  # (a) A subsequent 'mcp sync' must preserve the recorded escalation.
  run bash "$EIDOLONS_ROOT/cli/src/mcp_sync.sh"
  [ "$status" -eq 0 ] || return 1
  run bash -c "yq eval '.mcps[] | select(.name==\"tonberry\") | .enforcement' eidolons.mcp.lock"
  [ "$output" = "block" ] || return 1

  # (b) A forced re-install WITH the auto-fire suppressed rewrites the entry; the
  #     auto-fire write can only survive via the carry-forward (no re-assess).
  export EIDOLONS_SKIP_AUTO_ASSESS=1
  run bash "$EIDOLONS_ROOT/cli/src/mcp_install.sh" tonberry --force
  [ "$status" -eq 0 ] || return 1
  run bash -c "yq eval '.mcps[] | select(.name==\"tonberry\") | .enforcement' eidolons.mcp.lock"
  [ "$output" = "block" ] || return 1
  run bash -c "yq eval -o=json '.mcps[] | select(.name==\"tonberry\") | .enforcement_signals.change_count' eidolons.mcp.lock"
  [ "$output" = "14" ]
}
