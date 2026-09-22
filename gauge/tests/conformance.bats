#!/usr/bin/env bats

setup() {
  export GAUGE_REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export GOTOOLCHAIN=local
  cd "$GAUGE_REPO/gauge"
}

anchor() {
  run go test -mod=readonly -race -count=1 ./... -run "^TestV406T${1}($|_)" -v
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}

@test "V4-06 T01 separate profile method worker context and execution identities" { anchor 01; }
@test "V4-06 T02 opt-out compatibility and explicit binary selection" { anchor 02; }
@test "V4-06 T03 unsupported corrupt and incomplete state stays unchanged" { anchor 03; }
@test "V4-06 T04 frozen legacy import and exclusive recoverable promotion" {
  run python3 "$GAUGE_REPO/gauge/tests/authority.py"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
  anchor 04
}
@test "V4-06 T05 atomic dependent state rollback contention and process interruption" { anchor 05; }
@test "V4-06 T06 fixture execution bookkeeping invokes zero models" { anchor 06; }
@test "V4-06 T07 history context knowledge and policy stay distinct" { anchor 07; }
@test "V4-06 T08 durable identity survives independent process and environment replacement" { anchor 08; }
@test "V4-06 T09 execution configuration constituents and observed unknown model" { anchor 09; }
