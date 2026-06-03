#!/usr/bin/env bats
# cli/tests/aci.bats — D7 ACI boundary conformance gate (roadmap #3).
# Codifies the SWE-agent ACI rubric (R8-02): the roster security block (the
# read/write/network boundary) must match its capability class's contract in
# roster/aci.yaml. Verifies the gate logic, that the SHIPPED roster is clean,
# and that `eidolons doctor --deep` surfaces D7.

load helpers

# Build a one-member roster fixture + a copy of the real ACI contract.
# $1=dir  $2=capability_class  $3=indented security block (or "")
_mkroster() {
  local dir="$1" class="$2" sec="$3"
  mkdir -p "$dir"
  {
    echo 'registry_version: "1.1"'
    echo 'eidolons:'
    echo "  - name: tester"
    echo "    capability_class: $class"
    if [ -n "$sec" ]; then
      echo "    security:"
      printf '%s\n' "$sec"
    fi
  } > "$dir/index.yaml"
  cp "$EIDOLONS_ROOT/roster/aci.yaml" "$dir/aci.yaml"
}

# Run deep_check_aci_conformance against a fixture roster with stub err/pass.
# Echoes the function output; $status is the violation count.
_aci() {
  local roster="$1" name="$2"
  # lib.sh sets `set -euo pipefail` on source; doctor.sh always calls deep gates
  # as `deep_check_X || rc=$?` (which disables set -e inside the function). `set
  # +e` here replicates that call context so a standalone call behaves the same.
  bash -c '
    . "'"$EIDOLONS_ROOT"'/cli/src/lib.sh" >/dev/null 2>&1
    set +eu
    ROSTER_FILE="'"$roster"'"
    err() { printf "ERR: %s\n" "$*"; }
    pass() { printf "PASS: %s\n" "$*"; }
    warn() { printf "WARN: %s\n" "$*" >&2; }
    deep_check_aci_conformance "'"$name"'"
  '
}

@test "D7 logic: conformant scout (read-only) passes" {
  _mkroster "$BATS_TEST_TMPDIR/r" scout "$(printf '      reads_repo: true\n      writes_repo: false\n      reads_network: false')"
  run _aci "$BATS_TEST_TMPDIR/r/index.yaml" tester
  [ "$status" -eq 0 ]
  [[ "$output" =~ "conforms" ]]
}

@test "D7 logic: scout declaring writes_repo=true is a violation" {
  _mkroster "$BATS_TEST_TMPDIR/r" scout "$(printf '      reads_repo: true\n      writes_repo: true\n      reads_network: false')"
  run _aci "$BATS_TEST_TMPDIR/r/index.yaml" tester
  [ "$status" -ne 0 ]
  [[ "$output" =~ "read-only-by-construction but writes_repo=true" ]]
}

@test "D7 logic: reasoner is tool-less — any read/write/network is a violation" {
  _mkroster "$BATS_TEST_TMPDIR/r" reasoner "$(printf '      reads_repo: true\n      writes_repo: false\n      reads_network: false')"
  run _aci "$BATS_TEST_TMPDIR/r/index.yaml" tester
  [ "$status" -ne 0 ]
  [[ "$output" =~ "tool-less" || "$output" =~ "reads_repo" ]]
}

@test "D7 logic: any class declaring reads_network=true violates the universal contract" {
  _mkroster "$BATS_TEST_TMPDIR/r" debugger "$(printf '      reads_repo: true\n      writes_repo: false\n      reads_network: true')"
  run _aci "$BATS_TEST_TMPDIR/r/index.yaml" tester
  [ "$status" -ne 0 ]
  [[ "$output" =~ "reads_network" ]]
}

@test "D7 logic: memory class is exempt (MCP-mediated)" {
  _mkroster "$BATS_TEST_TMPDIR/r" memory ""
  run _aci "$BATS_TEST_TMPDIR/r/index.yaml" tester
  [ "$status" -eq 0 ]
}

@test "D7: the SHIPPED roster is ACI-clean (all members conform)" {
  for n in atlas spectra apivr idg forge vigil crystalium; do
    run _aci "$EIDOLONS_ROOT/roster/index.yaml" "$n"
    [ "$status" -eq 0 ]
  done
}

@test "doctor --deep surfaces the D7 ACI gate" {
  run eidolons doctor --deep --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "D7" ]]
  [[ "$output" =~ "ACI boundary conformance" ]]
}
