#!/usr/bin/env bats
load helpers

@test "checkpoint: complete payload round-trips and rejects incomplete payload" {
  good="$BATS_TEST_TMPDIR/good.json"; bad="$BATS_TEST_TMPDIR/bad.json"
  jq -n '{constraints:[],anchors:[],decisions:[],failed_approaches:[],open_variables:[],pending_checks:[],lineage:[]}' > "$good"
  jq -n '{constraints:[]}' > "$bad"
  run eidolons context checkpoint create --payload "$good" --id complete --json
  [ "$status" -eq 0 ]
  run eidolons context checkpoint recover --id complete --json
  [ "$status" -eq 0 ]
  [ "$(jq -r 'has("lineage")' <<< "$output")" = true ]
  run eidolons context checkpoint create --payload "$bad" --id incomplete
  [ "$status" -ne 0 ]
}

@test "augment: capsule rejects traversal and recall is untrusted and bounded" {
  run eidolons augment capsule export --file ../escape.json --task-id t
  [ "$status" -ne 0 ]
  run eidolons augment recall add --origin tool --text "instructions"
  [ "$status" -eq 0 ]
  run eidolons augment recall list
  [ "$(jq -r '.records[0].authority' <<< "$output")" = none ]
  [ "$(jq -r '.records | length <= 5' <<< "$output")" = true ]
}

@test "run: opt-in ledger records planned but not completed work" {
  run env EIDOLONS_LEDGER=1 eidolons run "audit the loader" --json
  [ "$status" -eq 0 ]
  id="$(jq -r '.semantic_decision_digest' <<< "$output")"
  run eidolons ledger status --run-id "$id" --json
  [ "$(jq -r '.completion' <<< "$output")" = not-complete ]
}
