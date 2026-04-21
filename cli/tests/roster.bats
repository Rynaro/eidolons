#!/usr/bin/env bats

load helpers

@test "roster: team view lists every Eidolon" {
  run eidolons roster
  [ "$status" -eq 0 ]
  [[ "$output" =~ ATLAS ]]
  [[ "$output" =~ SPECTRA ]]
  [[ "$output" =~ cycle: ]]
  [[ "$output" =~ methodology: ]]
}

@test "roster atlas: single-member summary" {
  run eidolons roster atlas
  [ "$status" -eq 0 ]
  [[ "$output" =~ ATLAS ]]
  [[ "$output" =~ Methodology: ]]
  [[ "$output" =~ Handoffs: ]]
  [[ "$output" =~ Security: ]]
}

@test "roster atlas --methodology: methodology view only" {
  run eidolons roster atlas --methodology
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.name == "ATLAS"' >/dev/null
  echo "$output" | jq -e '.cycle' >/dev/null
}

@test "roster atlas --handoffs: handoff view only" {
  run eidolons roster atlas --handoffs
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.downstream | length > 0' >/dev/null
}

@test "roster atlas --references: references list" {
  run eidolons roster atlas --references
  [ "$status" -eq 0 ]
  [[ "$output" =~ research/ ]]
}

@test "roster atlas --json: full entry as JSON" {
  run eidolons roster atlas --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.name == "atlas"' >/dev/null
  echo "$output" | jq -e '.source.repo' >/dev/null
}

@test "roster: unknown name exits 1 with actionable message" {
  run eidolons roster not-a-real-eidolon
  [ "$status" -eq 1 ]
  [[ "$output" =~ not\ found ]]
}

@test "roster -h: help prints" {
  run eidolons roster -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons\ roster ]]
}
