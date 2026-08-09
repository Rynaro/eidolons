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
  [ "$(jq -r '.selected | join(",")' <<< "$output")" = "atlas,vigil,ramza,vivi,idg" ]
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "scout-diagnose-plan-fix" ]
}

@test "chains: scout+debugger+coder selects scout-diagnose-fix (scout step no longer dropped)" {
  # Was the last residual of `chain-three-class`: this fell back to the 2-class
  # forensic-then-fix and dropped the SCOUT step.
  run eidolons run "map the auth flow, diagnose why login fails, and fix it" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "scout-diagnose-fix" ]
  [ "$(jq -r '.selected | join(",")' <<< "$output")" = "atlas,vigil,vivi,idg" ]
}

@test "chains: scout+debugger+coder+scriber no longer returns a read-only pair" {
  # Adding a scriber used to make this one of the order-dependent ties, and
  # audit-without-touching won by declaration order — so a prompt asking for a
  # FIX came back as [atlas, idg], dropping both the diagnosis and the repair.
  run eidolons run "audit the module, diagnose the failure, fix it and document it" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "scout-diagnose-fix" ]
  _sel="$(jq -r '.selected | join(",")' <<< "$output")"
  [[ "$_sel" == *"vigil"* ]]   # diagnosis present
  [[ "$_sel" == *"vivi"* ]]    # the fix they actually asked for
  [[ "$_sel" == *"idg"* ]]     # docs step still there
}

@test "chains: scout+debugger+reasoner+coder keeps the FORGE step, in order" {
  # Checker finding H1: scout-diagnose-fix took this combination over from
  # decide-then-implement and DROPPED forge — which scored 0.8, while the
  # hardcoded idg scored 0.0. Until this test existed, the fix was verified
  # only structurally from the YAML and never once through the kernel.
  #
  # Asserts the FULL ordered list, not membership: that pins vigil-before-forge
  # (root-cause before deliberating on the options the diagnosis produces), an
  # argument the record makes at length and nothing previously enforced.
  run eidolons run "audit the module, root cause the failure, decide between rollback or patch, then implement it" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "scout-diagnose-decide-fix" ]
  [ "$(jq -r '.selected | join(",")' <<< "$output")" = "atlas,vigil,forge,vivi,idg" ]
}

@test "chains: the five-class pipeline keeps FORGE and RAMZA, in order" {
  run eidolons run "explore the worker, diagnose the timeout, weigh the options, spec the fix and implement it" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "scout-diagnose-decide-plan-fix" ]
  [ "$(jq -r '.selected | join(",")' <<< "$output")" = "atlas,vigil,forge,ramza,vivi,idg" ]
}

@test "chains: the widest pipeline does not drop the scriber step" {
  # scout-diagnose-plan-fix supersedes plan-before-build, which ended in idg.
  # Without a trailing idg of its own, a prompt that explicitly asked for
  # documentation lost the docs step — the same silent step-drop this change
  # exists to remove, transplanted onto the scriber class.
  run eidolons run "explore the module, diagnose the timeout, spec the fix, implement it and document the change" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.chain[0].template' <<< "$output")" = "scout-diagnose-plan-fix" ]
  [[ "$(jq -r '.selected | join(",")' <<< "$output")" == *"idg"* ]]
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
audit-without-touching|scout-then-spec|planner+scout+scriber
decide-then-implement|audit-without-touching|coder+reasoner+scout+scriber
decide-then-implement|forensic-then-fix|coder+debugger+reasoner
decide-then-implement|ship-fast|coder+planner+reasoner
EOF
}

# A pair (A,B) at equal specificity is RESOLVED iff some template C satisfies
#   C.req ⊆ (A.req ∪ B.req)   AND   |C.req| > |A.req|
# SUBSET — matching cli/src/run.sh, which selects
#   select(requires_classes ⊆ classes) | sort_by(-spec) | .[0]
#
# The first revision of this helper tested set-EQUALITY (`. == $u`). That
# over-reported ties (it claimed 7 where 5 exist) and, worse, was blind to a
# template that merely DUPLICATES an existing class set — such a pair always
# ties, since no C can be a strict superset inside their own union. Because the
# expected list above had been generated with the same wrong expression, both
# sides of the comparison were wrong identically and this test passed while
# proving nothing about the property it names. The subset form below closes
# both holes: duplicate class sets now surface as unresolved automatically.
_actual_ambiguous_pairs() {
  yq -o=json '.chains' "$EIDOLONS_ROOT/roster/routing.yaml" | jq -r '
    [ .[] | {name, req: (.requires_classes | sort)} ] as $t
    | [ range(0; $t|length) as $i
        | range($i+1; $t|length) as $j
        | select(($t[$i].req|length) == ($t[$j].req|length))
        | (($t[$i].req + $t[$j].req) | unique) as $u
        | select([ $t[]
                   | select(((.req - $u) == [])
                            and ((.req|length) > ($t[$i].req|length))) ]
                 | length == 0)
        | "\($t[$i].name)|\($t[$j].name)|\($u | join("+"))" ]
    | sort | .[]'
}

@test "chains: the set of order-dependent ties is exactly the pinned set (no new ambiguity)" {
  _actual="$(_actual_ambiguous_pairs)"
  _expected="$(_expected_ambiguous_pairs | sort)"
  [ "$_actual" = "$_expected" ]
}

@test "chains: a DUPLICATE class set is reported as an unresolved tie (pin blind-spot regression)" {
  # The equality-based helper could not see this: a template duplicating an
  # existing requires_classes always ties (no C can be a strict superset inside
  # their own union), yet all assertions stayed green while the live route
  # flipped to idg>kupo.
  #
  # This test calls _actual_ambiguous_pairs() against a DOCTORED ROSTER rather
  # than re-implementing the predicate inline. The first version inlined a copy,
  # which meant it asserted a property of its own frozen expression and gave the
  # real helper zero protection — a checker confirmed it stayed green when the
  # helper was reverted to the equality form. Pointing EIDOLONS_ROOT at a temp
  # tree keeps exactly one copy of the predicate under test.
  local _root="$BATS_TEST_TMPDIR/duproot"
  mkdir -p "$_root/roster"
  yq -o=json '.' "$EIDOLONS_ROOT/roster/routing.yaml" \
    | jq '.chains += [{name:"rival-plan-before-build", steps:["idg","kupo"],
                       requires_classes:["scout","planner","coder"]}]' \
    | yq -P '.' > "$_root/roster/routing.yaml"

  local _saved="$EIDOLONS_ROOT"
  EIDOLONS_ROOT="$_root"
  local _out
  _out="$(_actual_ambiguous_pairs)"
  EIDOLONS_ROOT="$_saved"

  [[ "$_out" == *"plan-before-build|rival-plan-before-build"* ]]
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

# ─── The route-level coverage set pin ─────────────────────────────────────────
# The ambiguity pin above counts PAIRS. A checker showed that a route can flip
# while the pair count is untouched — `scout-diagnose-fix` took over
# {scout,debugger,reasoner,coder} and dropped FORGE with the pin still green,
# because the pair survived at its smaller witness. Pair-counting structurally
# cannot see a route change.
#
# This is the property those bugs actually violate: for every subset of
# triggered classes, the selected chain should contain at least one member of
# EVERY triggered class. Anything else is a silent step-drop.
#
# It is NOT satisfiable today — chain selection matches a template per class
# combination, and there are 57 subsets against 11 templates, so most subsets
# fall back to a lower-specificity entry that omits a class. Measured: 30
# violations at v2.19.1 (db82fb2), 24 here.
#
# It pins the SET, not a count. The first version was a count with a ceiling,
# and a checker PAID IT OFF: adding a plausible gap-fill template (−1) while
# dropping the trailing `idg` from `plan-before-build` (+1) held the total at 24,
# kept every test and eval green, and shipped a live step-drop —
# `"explore the module, spec the change, implement it and document it"` lost its
# docs step with the whole repo green. Widening the metric to (subset,class)
# pairs does not help; it went 33 → 31 under the same attack. Any aggregate
# scalar with a ceiling can be settled by trading one violation for another.
# A set cannot be traded against: a NEW violating subset fails no matter how
# many others were fixed.
#
# Stating this as "no step-drops" would be the absolute-invariant-over-a-
# partial-mechanism mistake that got three earlier records rejected. It is a
# known, enumerated, bounded defect surface — 30 subsets at v2.19.1, 24 here.
_class_coverage_violations() {
  yq -o=json '.' "$EIDOLONS_ROOT/roster/routing.yaml" | jq -r '
    .chains as $chains
    | (.eidolons | with_entries(.value |= .capability_class)) as $cls
    | ["scout","debugger","reasoner","planner","coder","scriber"] as $U
    | [ range(1; pow(2; ($U|length)) | floor) ]
    | map(. as $m | [ range(0; ($U|length)) | select((($m / pow(2;.)) | floor) % 2 == 1) | $U[.] ])
    | map(select(length >= 2))
    | map({ classes: (.|sort),
            pick: ( . as $c
                    | [ $chains[] | select([ .requires_classes[] | . as $x | ($c|index($x)) ] | all)
                        | . + {spec: (.requires_classes|length)} ]
                    | sort_by(-.spec) | if length>0 then .[0] else null end ) })
    | map(select(.pick != null))
    | map(. + { covered: ((.pick.steps // []) | map($cls[.]) | unique) })
    | map(. + { missing: [ .classes[] as $k | select(([.covered[]] | index($k)) == null) | $k ] })
    | map(select((.missing|length) > 0))
    | map("\(.classes|join("+"))\t\(.missing|join(","))")
    | sort | .[]'
}

# The exact subsets whose selected chain omits a class the prompt triggered,
# with the omitted classes. Recorded, NOT endorsed — this is the enumerated
# defect surface of template-per-combination selection.
#
# To change it: if you FIX one, delete its line in the same commit. If a line
# you did not intend appears, you introduced a step-drop — fix the template,
# do not paste the line in.
_expected_coverage_violations() {
  cat <<'EOF'
coder+debugger+planner+reasoner	reasoner
coder+debugger+planner+reasoner+scriber	reasoner,scriber
coder+debugger+planner+scriber	scriber
coder+debugger+reasoner	debugger
coder+debugger+reasoner+scriber	debugger,scriber
coder+debugger+scriber	scriber
coder+planner+reasoner+scout	reasoner
coder+planner+reasoner+scout+scriber	reasoner
coder+planner+reasoner+scriber	scriber
coder+planner+scriber	scriber
coder+reasoner+scout	scout
coder+reasoner+scout+scriber	scout,scriber
coder+reasoner+scriber	scriber
coder+scout+scriber	coder
debugger+planner+reasoner+scout	debugger,reasoner
debugger+planner+reasoner+scout+scriber	debugger,planner,reasoner
debugger+planner+scout	debugger
debugger+planner+scout+scriber	debugger,planner
debugger+reasoner+scout+scriber	debugger,reasoner
debugger+scout+scriber	debugger
planner+reasoner+scout	reasoner
planner+reasoner+scout+scriber	planner,reasoner
planner+scout+scriber	planner
reasoner+scout+scriber	reasoner
EOF
}

@test "chains: the set of class-coverage step-drops is exactly the pinned set" {
  _actual="$(_class_coverage_violations)"
  _expected="$(_expected_coverage_violations)"
  [ "$_actual" = "$_expected" ]
}

@test "chains: the combinations this change targets are step-drop free" {
  # The set pin above bounds the whole surface; these are the four subsets this
  # change set out to fix, asserted individually so a regression names itself.
  _out="$(yq -o=json '.' "$EIDOLONS_ROOT/roster/routing.yaml" | jq -r '
    .chains as $chains
    | (.eidolons | with_entries(.value |= .capability_class)) as $cls
    | [["coder","debugger","scout"],["coder","debugger","scout","scriber"],
       ["coder","debugger","reasoner","scout"],["coder","debugger","reasoner","scout","scriber"]]
    | map({ classes: .,
            pick: ( . as $c
                    | [ $chains[] | select([ .requires_classes[] | . as $x | ($c|index($x)) ] | all)
                        | . + {spec: (.requires_classes|length)} ]
                    | sort_by(-.spec) | .[0] ) })
    | map(. + { covered: (.pick.steps | map($cls[.]) | unique) })
    | map(select([ .classes[] as $k | select(([.covered[]] | index($k)) == null) ] | length > 0))
    | map(.classes | join("+")) | join(" ")')"
  [ -z "$_out" ]
}

# ─── The cortex deep table must document every routing template ──────────────
# methodology/cortex/chain-templates.md is what a host LLM loads on demand to
# compose a chain by hand. Two templates added by this change —
# scout-diagnose-decide-fix and scout-diagnose-decide-plan-fix, the two that
# exist SPECIFICALLY to stop the FORGE step being dropped — reached
# roster/routing.yaml, evals/routing-suite.yaml, this file and CHANGELOG.md,
# and never reached that table. A host reading it to route
# scout+debugger+reasoner+coder would have found no entry carrying FORGE after
# a scout, and reproduced the original defect by hand.
#
# Four checker rounds passed over it because the row count and the template
# count both read 11: the table also documents three DISPATCH PATTERNS that are
# not kernel chain templates (direct-implementation-bypass,
# failed-attempt-recovery, decision-only), which exactly masked the three
# routing templates missing from it. Counting agreed while membership did not.
#
# So this asserts CONTAINMENT, not equality — a doc-only pattern in the table
# is legitimate; a routing template absent from it is not.
#
# SCOPE, recorded rather than claimed away:
#   * It checks NAME PRESENCE, not steps. A row naming a template alongside the
#     WRONG steps passes. All 11 rows were checked by hand against
#     roster/routing.yaml and are correct, so there is no live defect — but this
#     gate would not catch one.
#   * It passes VACUOUSLY on an empty enumeration (the .chains key renamed, the
#     roster truncated), because an empty loop leaves _missing empty. Same
#     empty-match-set hole disclosed in check_change_specs.sh's header.
#   * A bold mention of the name anywhere in the file satisfies it, not only a
#     table row.
@test "chains: every routing template is documented in the cortex deep table" {
  _table="$EIDOLONS_ROOT/methodology/cortex/chain-templates.md"
  [ -f "$_table" ]
  _missing=""
  while read -r _name; do
    [ -n "$_name" ] || continue
    # Bold markers on both ends anchor the match, so scout-diagnose-plan-fix
    # cannot be satisfied by scout-diagnose-decide-plan-fix's row.
    grep -q "\*\*${_name}\*\*" "$_table" || _missing="$_missing $_name"
  done <<< "$(yq -o=json '.chains' "$EIDOLONS_ROOT/roster/routing.yaml" | jq -r '.[].name')"
  [ -z "$_missing" ]
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
