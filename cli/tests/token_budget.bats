#!/usr/bin/env bats
# cli/tests/token_budget.bats — cortex always-loaded token-budget CI gate.
#
# ESL change generalist-eidolon, Track D (R-022/R-023/R-024).
# Covers:
#   AC-D01  over-budget fixture -> script exits 1
#   AC-D02  real EIDOLONS.md always-loaded region <= 850 chars/4 proxy tokens
#   AC-D04  relocated deep tables (chain templates, TRANCE activation gates)
#           sit outside the always-loaded markers, under methodology/cortex/
#   AC-D06  chars/4 proxy is within +/-15% of a recorded BPE reference count

load helpers

SCRIPT="$EIDOLONS_ROOT/scripts/token-budget-check.sh"
FIXTURES="$EIDOLONS_ROOT/cli/tests/fixtures/token-budget"

@test "token-budget: script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "token-budget: usage error on missing file argument exits 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "token-budget: errors (exit 2) when markers are absent from the file" {
  run bash -c "printf 'no markers here\n' > '$BATS_TEST_TMPDIR/nomarkers.md'; bash '$SCRIPT' '$BATS_TEST_TMPDIR/nomarkers.md'"
  [ "$status" -eq 2 ]
}

# ─── AC-D01 — over-budget fixture rejected ─────────────────────────────────

@test "token-budget: AC-D01 — over-budget fixture exits 1" {
  run bash "$SCRIPT" "$FIXTURES/over-budget.md" --ceiling 850
  [ "$status" -eq 1 ]
  [[ "$output" =~ "FAIL" ]]
}

@test "token-budget: AC-D01 — over-budget fixture's proxy count truly exceeds 850" {
  run bash "$SCRIPT" "$FIXTURES/over-budget.md" --ceiling 850
  proxy="$(echo "$output" | grep -oE 'ceil\) = [0-9]+ tokens' | grep -oE '[0-9]+')"
  [ -n "$proxy" ]
  [ "$proxy" -gt 850 ]
}

# ─── AC-D02 — the real EIDOLONS.md stays under budget ──────────────────────

@test "token-budget: AC-D02 — EIDOLONS.md always-loaded region <= 850 proxy tokens" {
  run bash "$SCRIPT" "$EIDOLONS_ROOT/EIDOLONS.md" --ceiling 850
  [ "$status" -eq 0 ]
  [[ "$output" =~ "PASS" ]]
}

@test "token-budget: EIDOLONS.md declares the always-loaded marker pair exactly once each" {
  starts="$(grep -c '<!-- always-loaded:start -->' "$EIDOLONS_ROOT/EIDOLONS.md")"
  ends="$(grep -c '<!-- always-loaded:end -->' "$EIDOLONS_ROOT/EIDOLONS.md")"
  [ "$starts" -eq 1 ]
  [ "$ends" -eq 1 ]
}

@test "token-budget: default ceiling (no --ceiling flag) is 850" {
  run bash "$SCRIPT" "$EIDOLONS_ROOT/EIDOLONS.md"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ceiling 850" ]]
}

# ─── AC-D04 — relocated deep tables sit outside the markers ────────────────

@test "token-budget: AC-D04 — Chain Templates full table lives under methodology/cortex/, outside markers" {
  [ -f "$EIDOLONS_ROOT/methodology/cortex/chain-templates.md" ]
  # The relocated file itself carries no always-loaded markers.
  ! grep -q '<!-- always-loaded:start -->' "$EIDOLONS_ROOT/methodology/cortex/chain-templates.md"
  # EIDOLONS.md's own Chain Templates section is a pointer, not the full table,
  # and sits AFTER the always-loaded:end marker.
  awk '/<!-- always-loaded:end -->/{f=1} f && /## Chain Templates/{found=1} END{exit !found}' "$EIDOLONS_ROOT/EIDOLONS.md"
}

@test "token-budget: AC-D04 — TRANCE Activation Gates table lives under methodology/cortex/trance-matrix.md, outside markers" {
  grep -q '## Activation Gates' "$EIDOLONS_ROOT/methodology/cortex/trance-matrix.md"
  awk '/<!-- always-loaded:end -->/{f=1} f && /## TRANCE Activation Gates/{found=1} END{exit !found}' "$EIDOLONS_ROOT/EIDOLONS.md"
}

@test "token-budget: AC-D04 — dispatch-predicate.md deep table (full lexicons/fixtures) lives outside the markers" {
  [ -f "$EIDOLONS_ROOT/methodology/cortex/dispatch-predicate.md" ]
  ! grep -q '<!-- always-loaded:start -->' "$EIDOLONS_ROOT/methodology/cortex/dispatch-predicate.md"
}

# ─── AC-D06 — chars/4 proxy within +/-15% of a recorded BPE reference ──────

@test "token-budget: AC-D06 — chars/4 proxy is within +/-15% of the recorded cl100k_base reference" {
  run bash "$SCRIPT" "$FIXTURES/bpe-reference.md" --ceiling 850
  [ "$status" -eq 0 ]
  proxy="$(echo "$output" | grep -oE 'ceil\) = [0-9]+ tokens' | grep -oE '[0-9]+')"
  [ -n "$proxy" ]
  # Recorded reference (see bpe-reference.md header): cl100k_base = 184 tokens.
  reference=184
  # +/-15% band computed in integer arithmetic (bash 3.2 safe): [ref*85/100, ref*115/100].
  lower=$(( reference * 85 / 100 ))
  upper=$(( (reference * 115 + 99) / 100 ))
  [ "$proxy" -ge "$lower" ]
  [ "$proxy" -le "$upper" ]
}

@test "token-budget: AC-D06 — recorded proxy count in the fixture matches what the script measures" {
  run bash "$SCRIPT" "$FIXTURES/bpe-reference.md" --ceiling 850
  [[ "$output" =~ "proxy(chars/4, ceil) = 199" ]]
}
