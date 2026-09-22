#!/usr/bin/env bats
load helpers

make_route() {
  seed_manifest
  route="$BATS_TEST_TMPDIR/route.json"
  eidolons run "audit the loader" --json > "$route"
}

@test "ledger: planned work is not completion when dispatch is unobserved" {
  make_route
  run eidolons ledger open --run-id no-dispatch --route "$route"
  [ "$status" -eq 0 ]
  run eidolons ledger status --run-id no-dispatch --json
  [ "$(jq -r '.dispatch' <<< "$output")" = "unobserved" ]
  [ "$(jq -r '.completion' <<< "$output")" = "not-complete" ]
}

@test "ledger: manual completion labels remain self-attested despite a matching artifact digest" {
  make_route
  run eidolons ledger open --run-id checked --route "$route"
  [ "$status" -eq 0 ]
  run eidolons ledger complete --run-id checked --artifact "$route" --checker checker-a --scope route --verdict pass
  [ "$status" -eq 0 ]
  run eidolons ledger status --run-id checked --json
  [ "$(jq -r '.completion' <<< "$output")" = "not-complete" ]
  [ "$(jq -r '.execution_provenance.status' <<< "$output")" = "self-attested" ]
  [ "$(jq -r '.events' <<< "$output")" = "2" ]
}

@test "ledger: unknown side effects require reconciliation" {
  make_route
  run eidolons ledger open --run-id unknown-effect --route "$route"
  [ "$status" -eq 0 ]
  run eidolons ledger record --run-id unknown-effect --type side-effect --observed '{"side_effect":"unknown"}'
  [ "$status" -eq 0 ]
  run eidolons ledger status --run-id unknown-effect --json
  [ "$(jq -r '.reconciliation_required' <<< "$output")" = "true" ]
}
