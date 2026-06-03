#!/usr/bin/env bats
# cli/tests/trace.bats — ECL trace telemetry reader (roadmap #4).
# `eidolons trace cost` (per-Eidolon token attribution + budget-exhaustion abort)
# and `eidolons trace otel` (OpenTelemetry GenAI-convention span export).

load helpers

# Write one ECL envelope into $1 (dir): from=$2 to=$3 tokens=$4 model=$5.
_mkenv() {
  local dir="$1" from="$2" to="$3" tok="$4" model="${5:-claude-opus-4-7}"
  mkdir -p "$dir"
  cat > "$dir/${from}-${to}.envelope.json" <<EOF
{
  "envelope_version": "2.0",
  "message_id": "msg-${from}-${to}",
  "thread_id": "th-test",
  "from": {"eidolon": "${from}", "version": "1.0"},
  "to": {"eidolon": "${to}", "version": "1.0"},
  "performative": "PROPOSE",
  "artifact": {"kind": "spec", "path": "x.md"},
  "context_delta": {"token_budget": 4000, "tokens_used": ${tok}},
  "trace": {"ts": "2026-06-03T00:00:00Z", "host": "claude-code", "model": "${model}", "tier": "standard"}
}
EOF
}

# A 3-hop chain in $BATS_TEST_TMPDIR/th totalling 1000+2000+500 = 3500 tokens.
_chain() {
  local d="$BATS_TEST_TMPDIR/th"
  _mkenv "$d/S0" human atlas 1000
  _mkenv "$d/S1" atlas spectra 2000
  _mkenv "$d/S2" spectra apivr 500
  echo "$d"
}

@test "trace: --help exits 0" {
  run eidolons trace --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "token attribution" ]]
}

@test "trace: unknown subcommand errors" {
  run eidolons trace bogus "$BATS_TEST_TMPDIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unknown subcommand" ]]
}

@test "trace cost: no path is an error" {
  run eidolons trace cost
  [ "$status" -ne 0 ]
}

@test "trace cost: per-Eidolon token attribution + total" {
  d="$(_chain)"
  run eidolons trace cost "$d" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.total_tokens')" = "3500" ]
  [ "$(echo "$output" | jq -r '.hops')" = "3" ]
  # attribution is by the PRODUCER (from.eidolon): the atlas->spectra hop has
  # from=atlas tokens=2000, so atlas leads the ledger.
  [ "$(echo "$output" | jq -r '.by_eidolon[0].eidolon')" = "atlas" ]
  [ "$(echo "$output" | jq -r '.by_eidolon[0].tokens')" = "2000" ]
}

@test "trace cost --budget: exceeded total aborts with exit 3" {
  d="$(_chain)"
  run eidolons trace cost "$d" --budget 3000
  [ "$status" -eq 3 ]
  [[ "$output" =~ "budget exhausted" ]]
}

@test "trace cost --budget: within budget exits 0" {
  d="$(_chain)"
  run eidolons trace cost "$d" --budget 5000
  [ "$status" -eq 0 ]
  [[ "$output" =~ "within budget" ]]
}

@test "trace cost: ledger is a self-reported estimate (labelled)" {
  d="$(_chain)"
  run eidolons trace cost "$d" --json
  [[ "$(echo "$output" | jq -r '.note')" =~ "estimate" ]]
}

@test "trace otel: emits OTel GenAI-convention spans" {
  d="$(_chain)"
  run eidolons trace otel "$d"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.schema')" = "opentelemetry.gen_ai" ]
  [ "$(echo "$output" | jq -r '.spans | length')" = "3" ]
  # GenAI semantic-convention attributes present
  [ "$(echo "$output" | jq -r '.spans[0].attributes["gen_ai.operation.name"]')" = "invoke_agent" ]
  [ "$(echo "$output" | jq -r '.spans[0].attributes["gen_ai.system"]')" = "eidolons" ]
  [ "$(echo "$output" | jq -r '[.spans[].attributes["gen_ai.usage.output_tokens"]] | add')" = "3500" ]
}

@test "trace otel: convention version is pinned and overridable" {
  d="$(_chain)"
  run eidolons trace otel "$d" --otel-version 9.9.9
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.gen_ai_convention_version')" = "9.9.9" ]
}

@test "trace cost: accepts a single envelope file (not just a dir)" {
  d="$(_chain)"
  run eidolons trace cost "$d/S1/atlas-spectra.envelope.json" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.total_tokens')" = "2000" ]
}
