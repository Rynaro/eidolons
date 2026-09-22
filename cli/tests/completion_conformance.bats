#!/usr/bin/env bats
load helpers

@test "V4-05 T01: latest applicable mandatory observation wins" {
  run python3 "$EIDOLONS_ROOT/cli/tests/completion_conformance.py" latest
  [ "$status" -eq 0 ]
}
@test "V4-05 T02: candidate constituents and typed retry identity invalidate safely" {
  run python3 "$EIDOLONS_ROOT/cli/tests/completion_conformance.py" candidate
  [ "$status" -eq 0 ]
}
@test "V4-05 T03: labels and serialized claims cannot confer independent provenance" {
  run python3 "$EIDOLONS_ROOT/cli/tests/completion_conformance.py" provenance
  [ "$status" -eq 0 ]
}
@test "V4-05 T04: historical views regenerate from canonical captures" {
  run python3 "$EIDOLONS_ROOT/cli/tests/completion_conformance.py" views
  [ "$status" -eq 0 ]
}
@test "V4-05 T05: missing stale cancelled and invalid evidence withhold acceptance" {
  run python3 "$EIDOLONS_ROOT/cli/tests/completion_conformance.py" required
  [ "$status" -eq 0 ]
}
@test "V4-05 T06: integrity provenance and acceptance remain distinct typed grades" {
  run python3 "$EIDOLONS_ROOT/cli/tests/completion_conformance.py" grades
  [ "$status" -eq 0 ]
}
@test "V4-05 T07: native A2A and MCP termination does not imply acceptance" {
  run python3 "$EIDOLONS_ROOT/cli/tests/completion_conformance.py" termination
  [ "$status" -eq 0 ]
}

@test "V4-05 T02: ancestor modes and symlink resolution invalidate dependent evidence" {
  run python3 "$EIDOLONS_ROOT/cli/tests/completion_conformance.py" ancestors
  [ "$status" -eq 0 ]
}
@test "V4-05 T02: unchanged legacy completion retry preserves bytes and conflicts remain strict" {
  run python3 "$EIDOLONS_ROOT/cli/tests/completion_conformance.py" legacy_retry
  [ "$status" -eq 0 ]
}
