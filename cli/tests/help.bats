#!/usr/bin/env bats

load helpers

@test "help: explicit subcommand" {
  run eidolons help
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons ]]
  [[ "$output" =~ init ]]
  [[ "$output" =~ add ]]
  [[ "$output" =~ doctor ]]
}

@test "help: --help flag" {
  run eidolons --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons ]]
}

@test "help: -h flag" {
  run eidolons -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons ]]
}

@test "help: no args dispatches to help" {
  run eidolons
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons ]]
}
