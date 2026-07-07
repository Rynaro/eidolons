#!/usr/bin/env bats
# cli/tests/trace_reader.bats — the read-only ECL trace consumer (roadmap #5).
# `eidolons trace show` (hand-off chain), `graph` (hand-off DAG), and `verify`
# (batch SHA-256 integrity across a thread — the CLI half of the ECL gate).

load helpers

# Write a full ECL hop (envelope + matching payload with a correct SHA-256) into
# stage dir $1: from=$2 to=$3 performative=$4 kind=$5 tokens=$6.
_mkhop() {
  local dir="$1" from="$2" to="$3" perf="$4" kind="$5" tok="$6"
  mkdir -p "$dir"
  local payload="$dir/${kind}.md"
  printf 'payload %s->%s\n' "$from" "$to" > "$payload"
  local sha size
  sha="$( { shasum -a 256 "$payload" 2>/dev/null || sha256sum "$payload"; } | awk '{print $1}')"
  size="$(wc -c < "$payload" | tr -d '[:space:]')"
  cat > "$dir/${kind}.md.envelope.json" <<EOF
{
  "envelope_version": "2.0",
  "message_id": "m-${from}-${to}",
  "thread_id": "th-reader",
  "parent_id": null,
  "from": {"eidolon": "${from}", "version": "1.0"},
  "to": {"eidolon": "${to}", "version": "1.0"},
  "performative": "${perf}",
  "artifact": {"kind": "${kind}", "path": "${kind}.md", "sha256": "${sha}", "size_bytes": ${size}},
  "context_delta": {"token_budget": 4000, "tokens_used": ${tok}},
  "integrity": {"method": "sha256", "value": "${sha}"},
  "trace": {"ts": "2026-06-03T00:00:00Z", "host": "claude-code", "model": "claude-opus-4-7", "tier": "standard"}
}
EOF
}

# A 3-hop chain in stage dirs S0/S1/S2 (find|sort yields stage order).
_chain() {
  local d="$BATS_TEST_TMPDIR/th"
  _mkhop "$d/S0" human atlas REQUEST prompt 580
  _mkhop "$d/S1" atlas spectra PROPOSE scout-report 2600
  _mkhop "$d/S2" spectra apivr PROPOSE spec 3200
  echo "$d"
}

@test "trace show: renders the hand-off chain in stage order (--json)" {
  d="$(_chain)"
  run eidolons trace show "$d" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = "3" ]
  [ "$(echo "$output" | jq -r '.[0].from')" = "human" ]
  [ "$(echo "$output" | jq -r '.[0].to')" = "atlas" ]
  [ "$(echo "$output" | jq -r '.[2].to')" = "apivr" ]
  [ "$(echo "$output" | jq -r '.[1].tokens')" = "2600" ]
}

@test "trace show: text mode renders hops" {
  d="$(_chain)"
  run eidolons trace show "$d"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "hand-off chain" ]]
  [[ "$output" =~ "human → atlas" ]]
}

@test "trace graph: unique from->to edges (--json)" {
  d="$(_chain)"
  run eidolons trace graph "$d" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.edges | length')" = "3" ]
  [ "$(echo "$output" | jq -r '.nodes | sort | join(",")')" = "apivr,atlas,human,spectra" ]
}

@test "trace verify: clean thread — all hops pass" {
  d="$(_chain)"
  run eidolons trace verify "$d" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.total')" = "3" ]
  [ "$(echo "$output" | jq -r '.failed')" = "0" ]
  [ "$(echo "$output" | jq -r '.all_pass')" = "true" ]
}

@test "trace verify --block: a tampered payload fails the thread (exit 3)" {
  d="$(_chain)"
  echo "TAMPERED" >> "$d/S1/scout-report.md"   # mutate a payload after its envelope was sealed
  run eidolons trace verify "$d" --block
  [ "$status" -eq 3 ]
}

@test "trace verify (warn): a tampered payload is reported but does not block" {
  d="$(_chain)"
  echo "TAMPERED" >> "$d/S2/spec.md"
  run eidolons trace verify "$d" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.failed')" = "1" ]
  [ "$(echo "$output" | jq -r '.all_pass')" = "false" ]
}

@test "trace verify --json: per-hop verdicts present" {
  d="$(_chain)"
  run eidolons trace verify "$d" --json
  [ "$(echo "$output" | jq -r '[.results[].verdict] | unique | join(",")')" = "pass" ]
}
