#!/usr/bin/env bats
# Negative intent is an authority boundary: implementation words inside a
# read-only request must not select a coder or start a write-capable chain.
load helpers

@test "routing: explicit do-not-implement excludes coder selection" {
  run eidolons run "audit the loader and do not implement any changes" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.selected | index("vivi") // false')" = "false" ]
  [ "$(echo "$output" | jq -r '.selected | index("apivr") // false')" = "false" ]
}

@test "routing: a named coder binds the coder chain step" {
  run eidolons run "Vivi, design and implement the --json flag for doctor" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "chain" ]
  [ "$(echo "$output" | jq -r '.selected[-1]')" = "vivi" ]
}
