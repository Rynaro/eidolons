#!/usr/bin/env bats

load helpers

@test "upgrade: prints stub message and exits non-zero" {
  run eidolons upgrade
  [ "$status" -ne 0 ]
  [[ "$output" =~ stub ]]
  [[ "$output" =~ eidolons\ sync ]]
}
