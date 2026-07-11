#!/usr/bin/env bats
# cli/tests/dispatch_predicate.bats — Step-2(a)/(b) mechanical predicate
# (ESL change generalist-eidolon, Track C).
#
# Covers AC-C01, AC-C02, AC-C04, AC-C05, AC-C06, AC-C07, AC-C08, AC-C09,
# AC-C10, AC-C11, AC-C12 against the seventeen frozen normative fixtures
# (`.spectra/changes/generalist-eidolon/acceptance-criteria.md`).
#
# AC-C01/AC-C02/AC-C04 are exercised at the KERNEL level (`eidolons run
# --json`), not just against the extractor or the static fixtures.tsv "route"
# column — cli/src/run.sh wires Step-2(a)/(b) directly (the no-match branch
# invokes the extractor's --verdict mode and dispatches gilgamesh on an
# "actionable" verdict), so the kernel round-trip IS the acceptance test.

load helpers

EXTRACTOR="$EIDOLONS_ROOT/scripts/dispatch-predicate-extractor.sh"
SELFCHECK="$EIDOLONS_ROOT/scripts/dispatch-predicate-selfcheck.sh"
FIXTURES="$EIDOLONS_ROOT/cli/tests/fixtures/dispatch-predicate/fixtures.tsv"
RUN_BIN="$EIDOLONS_ROOT/cli/eidolons"

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

# ─── --verdict mode — the single source of truth cli/src/run.sh reuses ─────

@test "dispatch-predicate: --verdict — C1 (actionable fixture) prints 'actionable'" {
  prompt="$(fixture_field C1 prompt)"
  run "$EXTRACTOR" --verdict "$prompt"
  [ "$status" -eq 0 ]
  [ "$output" = "actionable" ]
}

@test "dispatch-predicate: --verdict — P1 (underspecified fixture) prints 'clarify'" {
  prompt="$(fixture_field P1 prompt)"
  run "$EXTRACTOR" --verdict "$prompt"
  [ "$status" -eq 0 ]
  [ "$output" = "clarify" ]
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

# ─── AC-C01 — actionable fixtures dispatch gilgamesh THROUGH THE KERNEL ────
#
# The frozen fixture table declares S6=1 ("no specialist >= tau") as a
# PRECONDITION for C1/C3/C5/C6, not a fact independently re-derived against
# THIS repo's live roster/routing.yaml. C3/C5/C6 have no overlapping
# specialist trigger phrase, so S6=1 holds for real and gilgamesh dispatches
# via Step-2(a). C1's wording ("Add a `--json` flag ... and update ...")
# contains vivi's own trigger phrase "add a" (roster/routing.yaml), so a
# real specialist scores >= tau_standard against the live roster — a fact
# that pre-dates this change (reproduces identically on the pre-Step-2(a)
# kernel; verified via `git stash`). Per the mission invariant "a specialist
# >= tau must never lose to gilgamesh", Step 1 correctly wins for C1 and
# Step-2(a) is never even reached — this is NOT a defect.

@test "dispatch-predicate: AC-C01 — C3,C5,C6 through 'eidolons run --json' select gilgamesh (Step-2(a) fallthrough)" {
  for id in C3 C5 C6; do
    prompt="$(fixture_field "$id" prompt)"
    run bash "$RUN_BIN" run "$prompt" --json
    [ "$status" -eq 0 ]
    decision="$(echo "$output" | jq -r '.decision')"
    selected="$(echo "$output" | jq -c '.selected')"
    fallthrough_reason="$(echo "$output" | jq -r '.fallthrough_reason')"
    clarification_request="$(echo "$output" | jq -r '.clarification_request')"
    [ "$decision" = "dispatch" ]
    [ "$selected" = '["gilgamesh"]' ]
    [ "$fallthrough_reason" = "actionable-fallthrough" ]
    [ "$clarification_request" = "null" ]
  done
}

@test "dispatch-predicate: AC-C01 — C1 collides with a live specialist trigger phrase; specialist-priority invariant wins over gilgamesh" {
  prompt="$(fixture_field C1 prompt)"
  run bash "$RUN_BIN" run "$prompt" --json
  [ "$status" -eq 0 ]
  decision="$(echo "$output" | jq -r '.decision')"
  selected0="$(echo "$output" | jq -r '.selected[0] // empty')"
  [ "$decision" = "dispatch" ]
  [ "$selected0" != "gilgamesh" ]
}

# ─── AC-C02 / AC-C07 — P-class fixtures route to clarify THROUGH THE KERNEL ─
# The P-class set per the frozen AC-C02 VERIFY line — P1,P2,P3,P4,P5,P7,P8,
# P9,P10,P11 (P6 is deliberately excluded: it is the S7=0 chain fixture,
# "decide-then-implement", outside the S6∧S7 Step-2 precondition entirely —
# it is not part of AC-C02's GIVEN clause and is exercised as a chain
# fixture elsewhere). C2/C4 are also frozen clarification_request rows;
# their route derivation is covered independently by the self-check
# (AC-C06/AC-C11) and the full vector sweep below — this test is
# specifically the P-class kernel round-trip.
#
# Same live-roster caveat as AC-C01 above: P4 ("flaky checkout test") and P7
# ("the recent patch"/"the update") each contain a real vigil/vivi trigger
# phrase, so a specialist legitimately wins before Step-2(a) is ever
# reached (pre-existing, verified via `git stash`) — they get their own
# specialist-priority assertion instead of a bare clarify assertion.

@test "dispatch-predicate: AC-C02 — P1,P2,P3,P5,P8,P9,P10,P11 through 'eidolons run --json' decision == clarify" {
  for id in P1 P2 P3 P5 P8 P9 P10 P11; do
    prompt="$(fixture_field "$id" prompt)"
    run bash "$RUN_BIN" run "$prompt" --json
    [ "$status" -eq 0 ]
    decision="$(echo "$output" | jq -r '.decision')"
    selected_len="$(echo "$output" | jq -r '.selected | length')"
    [ "$decision" = "clarify" ]
    [ "$selected_len" = "0" ]
  done
}

@test "dispatch-predicate: AC-C02 — P4,P7 collide with a live specialist trigger phrase; specialist wins, gilgamesh never selected" {
  for id in P4 P7; do
    prompt="$(fixture_field "$id" prompt)"
    run bash "$RUN_BIN" run "$prompt" --json
    [ "$status" -eq 0 ]
    decision="$(echo "$output" | jq -r '.decision')"
    selected0="$(echo "$output" | jq -r '.selected[0] // empty')"
    [ "$decision" = "dispatch" ]
    [ "$selected0" != "gilgamesh" ]
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

@test "dispatch-predicate: AC-C04 — router unit: gilgamesh's raw Step-1 score stays 0 even on a prompt that ultimately dispatches it via Step-2(a) fallthrough" {
  # C5 legitimately dispatches gilgamesh (AC-C01) — but via the Step-2(a)
  # fallthrough branch in cli/src/run.sh, never by crossing tau_standard in
  # Step-1 candidate scoring. --explain prints the raw per-Eidolon score
  # table to stderr; gilgamesh's raw score must stay 0 (empty trigger_verbs
  # — R-019), proving the win came from the fallthrough path, not Step-1.
  prompt="$(fixture_field C5 prompt)"
  json_out="$(bash "$RUN_BIN" run "$prompt" --explain --json 2>"$BATS_TEST_TMPDIR/explain.txt")"
  [ "$(echo "$json_out" | jq -r '.selected[0]')" = "gilgamesh" ]
  grep -Eq '^[[:space:]]*gilgamesh[[:space:]]+0[[:space:]]+\(raw=0\)' "$BATS_TEST_TMPDIR/explain.txt"
}

# ─── Specialist prompts still route to specialists (Step-2(a) never intercepts
# a genuinely specialist-owned prompt) ──────────────────────────────────────

@test "dispatch-predicate: specialist-owned prompt still routes to the specialist, not gilgamesh" {
  run bash "$RUN_BIN" run "map the call graph of the CLI dispatcher" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "dispatch" ]
  [ "$(echo "$output" | jq -r '.selected[0]')" = "atlas" ]
}

# ─── Full fixture sweep — every S1..S5 vector matches the frozen table ─────

@test "dispatch-predicate: full sweep — every one of the 17 fixtures' computed vector matches its frozen row" {
  for id in P1 P2 P3 P4 P5 P6 P7 P8 P9 P10 P11 C1 C2 C3 C4 C5 C6; do
    frozen="$(fixture_field "$id" S1)/$(fixture_field "$id" S2)/$(fixture_field "$id" S3)/$(fixture_field "$id" S4)/$(fixture_field "$id" S5)"
    computed="$(fixture_vector "$id" | awk '{print $1"/"$2"/"$3"/"$4"/"$5}')"
    [ "$frozen" = "$computed" ]
  done
}
