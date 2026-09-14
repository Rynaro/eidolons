#!/usr/bin/env bats
# PL-02: routing exposes authority separately from selection.  Consumers must
# be able to refuse a write even when a host adapter cannot enforce it yet.

load helpers

@test "routing: negative write intent is an explicit authorization boundary" {
  run eidolons run "audit the loader and do not implement any changes" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.route_contract.version' <<< "$output")" = "1.0" ]
  [ "$(jq -r '.route_contract.forbidden_operations | join(",")' <<< "$output")" = "write" ]
  [ "$(jq -r '.route_contract.authorized_operations | join(",")' <<< "$output")" = "read" ]
  [ "$(jq -r '.route_contract.enforcement' <<< "$output")" = "advisory-until-host-enforced" ]
}

@test "routing: a semantic decision digest is stable for identical input" {
  run eidolons run "fix the retry bug" --json
  [ "$status" -eq 0 ]
  first="$(jq -r '.semantic_decision_digest' <<< "$output")"
  [[ "$first" =~ ^[a-f0-9]{64}$ ]]

  run eidolons run "fix the retry bug" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.semantic_decision_digest' <<< "$output")" = "$first" ]
}

@test "routing: capability receipt evidence does not grant authority" {
  run eidolons run "audit the loader" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.route_contract.capability_evidence.receipt' <<< "$output")" = ".eidolons/.readiness/receipt.json" ]
  [ "$(jq -r '.route_contract.authorized_operations | join(",")' <<< "$output")" = "read" ]
}
