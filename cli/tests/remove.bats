#!/usr/bin/env bats

load helpers

@test "remove: prints stub message and exits non-zero" {
  run eidolons remove atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ not\ yet\ implemented ]]
  [[ "$output" =~ Workaround ]]
}

@test "remove: rm alias dispatches to same stub" {
  run eidolons rm atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ not\ yet\ implemented ]]
}
