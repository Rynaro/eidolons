#!/usr/bin/env bats
load helpers

@test "readiness: writes a versioned receipt without claiming startup readiness" {
  seed_manifest
  run eidolons readiness --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.receipt_version')" = "1.0" ]
  [ "$(echo "$output" | jq -r '.hosts[0].startup_test.state')" = "unknown" ]
  [ "$(echo "$output" | jq -r '.members[0].discoverable')" = "missing" ]
  [ -f .eidolons/.readiness/receipt.json ]
}

@test "readiness: cache is invalidated when manifest configuration changes" {
  seed_manifest
  run eidolons readiness --json
  first="$(echo "$output" | jq -r '.configuration_digest')"
  printf '\n# changed\n' >> eidolons.yaml
  run eidolons readiness --json
  second="$(echo "$output" | jq -r '.configuration_digest')"
  [ "$first" != "$second" ]
}
