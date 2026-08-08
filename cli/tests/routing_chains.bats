#!/usr/bin/env bats
# cli/tests/routing_chains.bats — chain-template selection (ESL change
# `chain-three-class`).
#
# Chain selection is `sort_by(-spec) | .[0]` over the templates whose
# requires_classes are a subset of the prompt's triggered classes. jq's sort is
# STABLE, so two templates of EQUAL specificity that both match are resolved by
# declaration order in roster/routing.yaml — an artifact, not a decision.
#
# These tests do two things:
#   1. pin the routes for the multi-class chains, so a dropped step is caught;
#   2. PIN THE AMBIGUITY SET. A template added later that creates a NEW
#      equal-specificity collision fails here instead of silently letting file
#      order pick a winner in production.

load helpers

# ─── Routes ────────────────────────────────────────────────────────────────────

@test "chains: debugger+planner+coder selects diagnose-then-plan-then-fix (not ship-fast)" {
  # Regression: this fell back to the 2-class ship-fast and SILENTLY DROPPED the
  # diagnosis step — a planner got handed a failure nobody had root-caused.
  run eidolons run "diagnose the flaky test, plan the fix and implement it" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.decision' <<< "$output")" = "chain" ]
  [ "$(jq -r '.selected | join(",")' <<< "$output")" = "vigil,ramza,vivi" ]
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "diagnose-then-plan-then-fix" ]
}

@test "chains: scout+debugger+planner+coder selects scout-diagnose-plan-fix (no order-dependent tie)" {
  run eidolons run "map the worker, diagnose the timeout, spec a fix and implement it" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.selected | join(",")' <<< "$output")" = "atlas,vigil,ramza,vivi" ]
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "scout-diagnose-plan-fix" ]
}

@test "chains: pre-existing 2-class and 3-class routes are unchanged" {
  run eidolons run "spec the caching layer and implement it" --json
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "ship-fast" ]

  run eidolons run "the build broke after the last merge" --json
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "forensic-then-fix" ]

  run eidolons run "explore the module, spec the change and implement it" --json
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "plan-before-build" ]

  run eidolons run "compare the two designs, spec the winner and build it" --json
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "decide-then-implement" ]
}

# ─── The ambiguity pin ─────────────────────────────────────────────────────────

# Every equal-specificity pair of templates whose union has NO covering
# template. Each of these is currently decided by declaration order alone.
# They all predate `chain-three-class` and are recorded, not endorsed.
#
# To add a template: run the suite. If it fails here, your template created a
# NEW ambiguity — add a more specific entry covering the union (that is what
# `scout-diagnose-plan-fix` does), rather than appending a line below.
_expected_ambiguous_pairs() {
  cat <<'EOF'
audit-without-touching|forensic-then-fix|coder+debugger+scout+scriber
audit-without-touching|scout-then-spec|planner+scout+scriber
audit-without-touching|ship-fast|coder+planner+scout+scriber
decide-then-implement|audit-without-touching|coder+reasoner+scout+scriber
decide-then-implement|forensic-then-fix|coder+debugger+reasoner
decide-then-implement|scout-then-spec|coder+planner+reasoner+scout
decide-then-implement|ship-fast|coder+planner+reasoner
EOF
}

_actual_ambiguous_pairs() {
  yq -o=json '.chains' "$EIDOLONS_ROOT/roster/routing.yaml" | jq -r '
    [ .[] | {name, req: (.requires_classes | sort)} ] as $t
    | [ $t[] | .req ] as $all
    | [ range(0; $t|length) as $i
        | range($i+1; $t|length) as $j
        | select(($t[$i].req|length) == ($t[$j].req|length))
        | (($t[$i].req + $t[$j].req) | unique) as $u
        | select([ $all[] | select(. == $u) ] | length == 0)
        | "\($t[$i].name)|\($t[$j].name)|\($u | join("+"))" ]
    | sort | .[]'
}

@test "chains: the set of order-dependent ties is exactly the pinned set (no new ambiguity)" {
  _actual="$(_actual_ambiguous_pairs)"
  _expected="$(_expected_ambiguous_pairs | sort)"
  [ "$_actual" = "$_expected" ]
}

@test "chains: adding diagnose-then-plan-then-fix did NOT introduce a tie with plan-before-build" {
  # The union of their classes must be covered by a strictly more specific
  # template, or specificity stops being decisive for that prompt shape.
  run bash -c "yq -o=json '.chains' \"\$EIDOLONS_ROOT/roster/routing.yaml\" | jq -e '
    [ .[] | (.requires_classes | sort) ] as \$all
    | ([\"coder\",\"debugger\",\"planner\",\"scout\"]) as \$u
    | [ \$all[] | select(. == \$u) ] | length == 1'"
  [ "$status" -eq 0 ]
}

@test "chains: every template's steps name real roster members" {
  run bash -c "yq -o=json '.chains' \"\$EIDOLONS_ROOT/roster/routing.yaml\" \
    | jq -r '.[].steps[]' | sort -u"
  [ "$status" -eq 0 ]
  while read -r _member; do
    [ -n "$_member" ] || continue
    run bash -c "yq -o=json '.eidolons' \"\$EIDOLONS_ROOT/roster/routing.yaml\" | jq -e 'has(\"$_member\")'"
    [ "$status" -eq 0 ]
  done <<< "$(yq -o=json '.chains' "$EIDOLONS_ROOT/roster/routing.yaml" | jq -r '.[].steps[]' | sort -u)"
}
