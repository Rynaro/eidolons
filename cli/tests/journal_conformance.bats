#!/usr/bin/env bats
load helpers

@test "V4-04 T01: 120 events preserve numeric order and canonical digest links" {
  run python3 "$EIDOLONS_ROOT/cli/tests/journal_conformance.py" ordering
  [ "$status" -eq 0 ]
}

@test "V4-04 T02: synchronized identities and retries retain exact content once" {
  run python3 "$EIDOLONS_ROOT/cli/tests/journal_conformance.py" concurrent
  [ "$status" -eq 0 ]
}

@test "V4-04 T03: interrupted ownership preserves publication and requires bounded recovery" {
  run python3 "$EIDOLONS_ROOT/cli/tests/journal_conformance.py" interruption
  [ "$status" -eq 0 ]
}

@test "V4-04 T04: unknown inspection leaves project and home unchanged" {
  run python3 "$EIDOLONS_ROOT/cli/tests/journal_conformance.py" unknown
  [ "$status" -eq 0 ]
}

@test "V4-04 T05: invalid histories fail closed while legacy bytes remain readable" {
  run python3 "$EIDOLONS_ROOT/cli/tests/journal_conformance.py" corruption
  [ "$status" -eq 0 ]
}
