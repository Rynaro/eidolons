#!/usr/bin/env bats
# cli/tests/ecl_conformance.bats — D8 ECL receiver verify-incoming gate (frontier N3).
# Every installed RECEIVER Eidolon must ship a BLOCKING verify-incoming skill
# (ECL v1.0 section 6.2.2). Verifies the gate logic, that the marker discipline
# does NOT false-positive on the canonical skill's historical-contrast prose, that
# the shipped roster classifies every class, and that `doctor --deep` surfaces D8.

load helpers

# Build a fixture: a one-member roster + a copy of the real ECL contract + an
# installed skill tree under <projdir>/.eidolons/tester/skills/.
# $1=basedir  $2=capability_class  $3=skill content (empty => no skill file)
_mkproj() {
  local base="$1" class="$2" content="$3"
  mkdir -p "$base/proj"
  {
    echo 'registry_version: "1.1"'
    echo 'eidolons:'
    echo "  - name: tester"
    echo "    capability_class: $class"
  } > "$base/index.yaml"
  cp "$EIDOLONS_ROOT/roster/ecl.yaml" "$base/ecl.yaml"
  if [ -n "$content" ]; then
    mkdir -p "$base/proj/.eidolons/tester/skills"
    printf '%s\n' "$content" > "$base/proj/.eidolons/tester/skills/verify-incoming.md"
  fi
}

# Run deep_check_verify_incoming_conformance with stub err/pass/warn, ROSTER_FILE
# set, and CWD = the project fixture (so the .eidolons/ skill path resolves).
# Echoes function output; $status is the violation count.
_ecl() {
  local base="$1" name="$2"
  bash -c '
    cd "'"$base"'/proj"
    . "'"$EIDOLONS_ROOT"'/cli/src/lib.sh" >/dev/null 2>&1
    set +eu
    ROSTER_FILE="'"$base"'/index.yaml"
    err() { printf "ERR: %s\n" "$*"; }
    pass() { printf "PASS: %s\n" "$*"; }
    warn() { printf "WARN: %s\n" "$*" >&2; }
    deep_check_verify_incoming_conformance "'"$name"'"
  '
}

@test "D8 logic: a blocking verify-incoming skill conforms" {
  _mkproj "$BATS_TEST_TMPDIR/a" coder "$(printf '# Verify-Incoming\nOn mismatch, REFUSE to process and hand back. Do not process the payload.')"
  run _ecl "$BATS_TEST_TMPDIR/a" tester
  [ "$status" -eq 0 ]
  [[ "$output" =~ "blocking verify-incoming gate present" ]]
}

@test "D8 logic: a receiver missing the skill fails" {
  _mkproj "$BATS_TEST_TMPDIR/b" scout ""
  run _ecl "$BATS_TEST_TMPDIR/b" tester
  [ "$status" -ne 0 ]
  [[ "$output" =~ "missing blocking verify-incoming skill" ]]
}

@test "D8 logic: a skill with no blocking marker fails" {
  _mkproj "$BATS_TEST_TMPDIR/c" planner "$(printf '# Verify-Incoming\nThis skill validates the envelope schema and logs the outcome.')"
  run _ecl "$BATS_TEST_TMPDIR/c" tester
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no blocking posture" ]]
}

@test "D8 logic: a warn-only (prescriptive) skill fails" {
  _mkproj "$BATS_TEST_TMPDIR/d" coder "$(printf '# Verify-Incoming\nWARN-ONLY on failure: the payload is always processed.')"
  run _ecl "$BATS_TEST_TMPDIR/d" tester
  [ "$status" -ne 0 ]
  [[ "$output" =~ "warn-only posture" ]]
}

@test "D8 logic: memory class is exempt (not a receiver)" {
  _mkproj "$BATS_TEST_TMPDIR/e" memory ""
  run _ecl "$BATS_TEST_TMPDIR/e" tester
  [ "$status" -eq 0 ]
  [[ "$output" =~ "not an ECL hand-off receiver" ]]
}

@test "D8 logic: blocking skill that REFERENCES the old warn-only posture in contrast prose still conforms" {
  # The canonical skill names "warn-only" historically — the gate must NOT
  # false-positive on it (this is the exact subtlety the distribution agents hit).
  _mkproj "$BATS_TEST_TMPDIR/f" coder "$(printf '# Verify-Incoming\n> Previous versions logged a warning and processed the payload anyway. That is now superseded.\nOn mismatch, REFUSE to process.\n- **Blocking, not warn-only.**')"
  run _ecl "$BATS_TEST_TMPDIR/f" tester
  [ "$status" -eq 0 ]
  [[ "$output" =~ "blocking verify-incoming gate present" ]]
}

@test "D8: the shipped roster/ecl.yaml classifies every capability_class in the roster" {
  # No class may be silently unconstrained — every roster member's class must be
  # declared receiver true|false in ecl.yaml.
  run bash -c '
    . "'"$EIDOLONS_ROOT"'/cli/src/lib.sh" >/dev/null 2>&1
    ecl=$(yaml_to_json "'"$EIDOLONS_ROOT"'/roster/ecl.yaml")
    for c in $(yq eval ".eidolons[].capability_class" "'"$EIDOLONS_ROOT"'/roster/index.yaml" | sort -u); do
      printf "%s" "$ecl" | jq -e --arg c "$c" ".classes[\$c].receiver | type == \"boolean\"" >/dev/null \
        || { echo "UNCLASSIFIED: $c"; exit 1; }
    done
    echo OK
  '
  [ "$status" -eq 0 ]
  [[ "$output" =~ "OK" ]]
}

@test "D8: roster/ecl.yaml is valid against its schema shape (required keys present)" {
  run bash -c '
    . "'"$EIDOLONS_ROOT"'/cli/src/lib.sh" >/dev/null 2>&1
    yaml_to_json "'"$EIDOLONS_ROOT"'/roster/ecl.yaml" \
      | jq -e ".ecl_version and .verify_incoming.skill_path and (.verify_incoming.blocking_markers|length>0) and (.classes|length>0)" >/dev/null
  '
  [ "$status" -eq 0 ]
}

@test "doctor --deep surfaces the D8 ECL receiver gate" {
  run eidolons doctor --deep --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "D8" ]]
  [[ "$output" =~ "verify-incoming" ]]
}
