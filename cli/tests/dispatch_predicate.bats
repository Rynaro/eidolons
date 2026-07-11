#!/usr/bin/env bats
# cli/tests/dispatch_predicate.bats — Step-2(a)/(b) mechanical predicate
# (ESL change generalist-eidolon, Track C).
#
# Covers AC-C01, AC-C02, AC-C04, AC-C05, AC-C06, AC-C07, AC-C08, AC-C09,
# AC-C10, AC-C11, AC-C12 against the seventeen frozen normative fixtures
# (`.spectra/changes/generalist-eidolon/acceptance-criteria.md`).

load helpers

EXTRACTOR="$EIDOLONS_ROOT/scripts/dispatch-predicate-extractor.sh"
SELFCHECK="$EIDOLONS_ROOT/scripts/dispatch-predicate-selfcheck.sh"
FIXTURES="$EIDOLONS_ROOT/cli/tests/fixtures/dispatch-predicate/fixtures.tsv"

# fixture_field <id> <column_name> — reads one TSV column for one fixture row.
fixture_field() {
  local id="$1" col="$2"
  awk -F'\t' -v id="$id" -v col="$col" '
    NR == 1 { for (i = 1; i <= NF; i++) if ($i == col) target = i; next }
    $1 == id { print $target; exit }
  ' "$FIXTURES"
}

# fixture_vector <id> — runs the extractor on the fixture prompt, returns "S1 S2 S3 S4 S5".
fixture_vector() {
  local id="$1" prompt
  prompt="$(fixture_field "$id" prompt)"
  "$EXTRACTOR" "$prompt"
}

@test "dispatch-predicate: extractor script exists and is executable" {
  [ -x "$EXTRACTOR" ]
  [ -x "$SELFCHECK" ]
}

@test "dispatch-predicate: usage error on missing prompt argument exits 2" {
  run bash "$EXTRACTOR"
  [ "$status" -eq 2 ]
}

# ─── AC-C05 — deterministic (no-LLM), two runs give the same vector (I-C6) ──

@test "dispatch-predicate: AC-C05 — extractor is deterministic across two runs" {
  prompt="$(fixture_field C1 prompt)"
  run1="$("$EXTRACTOR" "$prompt")"
  run2="$("$EXTRACTOR" "$prompt")"
  [ "$run1" = "$run2" ]
}

# ─── AC-C06 / AC-C11 — the derivability self-check (all 17 fixtures) ───────

@test "dispatch-predicate: AC-C06/AC-C11 — self-check re-derives all 17 fixtures exactly (exit 0)" {
  run bash "$SELFCHECK"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "PASS" ]]
  [[ "$output" =~ "17 fixtures checked, 0 mismatch" ]]
}

@test "dispatch-predicate: fixtures.tsv declares exactly 17 normative rows" {
  # 18 lines total = 1 header + 17 fixtures.
  count="$(wc -l < "$FIXTURES" | tr -d '[:space:]')"
  [ "$count" -eq 18 ]
}

# ─── AC-C01 — actionable fixtures dispatch generalist ──────────────────────

@test "dispatch-predicate: AC-C01 — C1,C3,C5,C6 route to generalist" {
  for id in C1 C3 C5 C6; do
    route="$(fixture_field "$id" route)"
    [ "$route" = "generalist" ]
  done
}

# ─── AC-C02 / AC-C07 — underspecified fixtures route to clarification_request ─

@test "dispatch-predicate: AC-C02 — P1,P2,P3,P4,P5,P7,P8,P9,P10,P11,C2,C4 route to clarification_request" {
  for id in P1 P2 P3 P4 P5 P7 P8 P9 P10 P11 C2 C4; do
    route="$(fixture_field "$id" route)"
    [ "$route" = "clarification_request" ]
  done
}

@test "dispatch-predicate: AC-C07 — fixture P1 'Make the project better.' routes to clarification_request" {
  route="$(fixture_field P1 route)"
  [ "$route" = "clarification_request" ]
  vector="$(fixture_vector P1)"
  [ "$vector" = "0 0 0 0 0" ]
}

# ─── AC-C08 — S5 blast-radius guard (GENERIC_SCOPE + LIMITER rescue) ───────

@test "dispatch-predicate: AC-C08 — P3, P9, C4 yield S5=0" {
  for id in P3 P9 C4; do
    s5="$(fixture_vector "$id" | awk '{print $5}')"
    [ "$s5" -eq 0 ]
  done
}

@test "dispatch-predicate: AC-C08 — C6 (LIMITER + path) yields S5=1" {
  s5="$(fixture_vector C6 | awk '{print $5}')"
  [ "$s5" -eq 1 ]
}

# ─── AC-C09 — S1 noun-position guard (DET_BLOCKLIST) ───────────────────────

@test "dispatch-predicate: AC-C09 — fixture P7 (the recent patch / the update) yields S1=0" {
  s1="$(fixture_vector P7 | awk '{print $1}')"
  [ "$s1" -eq 0 ]
}

# ─── AC-C10 — PATH_OR_ID excludes versions/decimals ────────────────────────

@test "dispatch-predicate: AC-C10 — fixtures P8 (30.5s), P11 (2.5.0) yield S3=0" {
  for id in P8 P11; do
    s3="$(fixture_vector "$id" | awk '{print $3}')"
    [ "$s3" -eq 0 ]
  done
}

# ─── AC-C12 — English-only scope (CRIT-019) ────────────────────────────────

@test "dispatch-predicate: AC-C12 — fixture P10 (Spanish) yields S1=0 and routes to clarification_request" {
  s1="$(fixture_vector P10 | awk '{print $1}')"
  [ "$s1" -eq 0 ]
  route="$(fixture_field P10 route)"
  [ "$route" = "clarification_request" ]
}

# ─── AC-C04 — Gilgamesh never appears in the Step-1 candidate scoring set ──

@test "dispatch-predicate: AC-C04 — roster/routing.yaml declares gilgamesh with an empty trigger_verbs array" {
  count="$(yq -o=json eval '.eidolons.gilgamesh.trigger_verbs' "$EIDOLONS_ROOT/roster/routing.yaml" | jq 'length')"
  [ "$count" -eq 0 ]
}

@test "dispatch-predicate: AC-C04 — router unit: an explicit prompt cannot dispatch gilgamesh through Step-1 (name bonus alone stays below tau_standard)" {
  run bash "$EIDOLONS_ROOT/cli/eidolons" run "Gilgamesh, refactor the auth layer" --json
  [ "$status" -eq 0 ]
  selected="$(echo "$output" | jq -r '.selected[0] // empty')"
  [ "$selected" != "gilgamesh" ]
}

@test "dispatch-predicate: AC-C04 — router unit: a generic actionable prompt (no specialist match) never selects gilgamesh via the Step-1 kernel" {
  run bash "$EIDOLONS_ROOT/cli/eidolons" run "Append a retry field to config/http.yaml so requests retry 3 times." --json
  [ "$status" -eq 0 ]
  decision="$(echo "$output" | jq -r '.decision')"
  selected="$(echo "$output" | jq -r '.selected[0] // empty')"
  # The Step-1 kernel (roster/routing.yaml) has no gilgamesh trigger_verbs,
  # so it can never be $top; it either clarifies or a specialist dispatches —
  # never gilgamesh, consistent with R-019/AC-C04 (the actual Step-2(a)
  # branch dispatch is a separate, on-demand predicate layer, not this
  # kernel — see methodology/cortex/dispatch-predicate.md).
  [ "$selected" != "gilgamesh" ]
}

# ─── Full fixture sweep — every S1..S5 vector matches the frozen table ─────

@test "dispatch-predicate: full sweep — every one of the 17 fixtures' computed vector matches its frozen row" {
  for id in P1 P2 P3 P4 P5 P6 P7 P8 P9 P10 P11 C1 C2 C3 C4 C5 C6; do
    frozen="$(fixture_field "$id" S1)/$(fixture_field "$id" S2)/$(fixture_field "$id" S3)/$(fixture_field "$id" S4)/$(fixture_field "$id" S5)"
    computed="$(fixture_vector "$id" | awk '{print $1"/"$2"/"$3"/"$4"/"$5}')"
    [ "$frozen" = "$computed" ]
  done
}
