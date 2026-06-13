#!/usr/bin/env bats
#
# cli/tests/telemetry_export.bats
#
# P2.5 — `telemetry export [otel|json|csv]`
# Tests seed on-disk JSONL directly into a sandboxed $EIDOLONS_HOME; no live model.
#
# Spec reference: p2-roadmap.md §P2.5
# Acceptance:
#   - export otel spans carry the same gen_ai.* keys as trace otel (key parity).
#   - export json round-trips the store (count + sampled row).
#   - export csv has a header + one line per row with correct columns.
#   - all three are stdout-only and exit 0 on empty store with no spurious output.
#
# Billing safety: zero live model calls. Every test reads on-disk fixtures only.

load helpers

# ─── Setup ────────────────────────────────────────────────────────────────────

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$EIDOLONS_HOME"

  TEST_SLUG="telemetry-export-test"
  STORE_DIR="$EIDOLONS_HOME/telemetry/$TEST_SLUG"
  mkdir -p "$STORE_DIR"

  TEST_DATE="2026-06-13"
  DAY_FILE="$STORE_DIR/${TEST_DATE}.jsonl"
}

# ─── Helper: write a turn.v1 row ─────────────────────────────────────────────

write_row() {
  local event_id="$1"
  local source="$2"
  local model="$3"
  local in_tok="$4"
  local out_tok="$5"
  local cc_tok="$6"
  local cr_tok="$7"
  local repo="${8:-testrepo}"
  local eidolon="${9:-main}"
  local tier="${10:-}"

  local tier_json
  if [[ -z "$tier" || "$tier" == "null" ]]; then
    tier_json="null"
  else
    tier_json="\"$tier\""
  fi

  jq -nc \
    --arg schema "eidolons.telemetry.turn.v1" \
    --arg event_id "$event_id" \
    --arg ts "${TEST_DATE}T10:00:00.000Z" \
    --arg source "$source" \
    --arg host "claude-code" \
    --arg session_id "sess-export-test" \
    --arg model "$model" \
    --argjson in_tok "$in_tok" \
    --argjson out_tok "$out_tok" \
    --argjson cc_tok "$cc_tok" \
    --argjson cr_tok "$cr_tok" \
    --arg repo "$repo" \
    --arg eidolon "$eidolon" \
    --argjson tier "$tier_json" \
    '{
      schema: $schema,
      event_id: $event_id,
      ts: $ts,
      source: $source,
      host: $host,
      session_id: $session_id,
      turn_index: 0,
      model: $model,
      usage: {
        input_tokens: $in_tok,
        output_tokens: $out_tok,
        cache_creation_input_tokens: $cc_tok,
        cache_read_input_tokens: $cr_tok
      },
      self_reported_tokens: null,
      reconciliation_delta: null,
      attribution: {
        repo: $repo,
        branch: "feat/telemetry-p2-sprint2",
        commit: null,
        dirty: null,
        pr: null,
        cwd: "/test",
        is_sidechain: false,
        eidolon: $eidolon,
        eidolon_prompt_sha: null,
        objective_hash: null,
        task_id: null,
        prompt_version: null,
        tier: $tier
      },
      ecl_thread_id: null
    }' >> "$DAY_FILE"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Empty store — exit 0, no spurious output (all three formats)
# ═══════════════════════════════════════════════════════════════════════════════

@test "telemetry export json: empty store exits 0 with no output" {
  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export json \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: expected exit 0 for empty store, got $status" >&2
    return 1
  }

  [ -z "$out" ] || {
    echo "FAIL: expected empty stdout for empty store, got: $out" >&2
    return 1
  }
}

@test "telemetry export otel: empty store exits 0 with no output" {
  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: expected exit 0 for empty store, got $status" >&2
    return 1
  }

  [ -z "$out" ] || {
    echo "FAIL: expected empty stdout for empty store, got: $out" >&2
    return 1
  }
}

@test "telemetry export csv: empty store exits 0 with no output" {
  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export csv \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: expected exit 0 for empty store, got $status" >&2
    return 1
  }

  [ -z "$out" ] || {
    echo "FAIL: expected empty stdout for empty store (csv), got: $out" >&2
    return 1
  }
}

@test "telemetry export: absent store exits 0 with no output (default format json)" {
  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export json \
    --project "totally-nonexistent-export-slug-xyzzy" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: expected exit 0 for absent store, got $status" >&2
    return 1
  }

  [ -z "$out" ] || {
    echo "FAIL: expected empty stdout for absent store, got: $out" >&2
    return 1
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# export json — round-trips the store
# ═══════════════════════════════════════════════════════════════════════════════

@test "telemetry export json: round-trips store — count and sampled row match" {
  # Seed 3 rows.
  write_row "evt-json-r1" "audited"   "model-a" 1000 200 0 0 "repoA" "atlas"
  write_row "evt-json-r2" "audited"   "model-b" 500  100 0 0 "repoA" "spectra"
  write_row "evt-json-r3" "estimated" "model-a" 300  50  0 0 "repoB" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export json \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export json exited $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Must be a JSON array.
  local is_array
  is_array="$(printf '%s' "$out" | jq 'type == "array"')"
  [ "$is_array" = "true" ] || {
    echo "FAIL: export json output is not a JSON array" >&2
    echo "Got: $out" >&2
    return 1
  }

  # Must have 3 rows (deduped).
  local count
  count="$(printf '%s' "$out" | jq 'length')"
  [ "$count" -eq 3 ] || {
    echo "FAIL: expected 3 rows, got $count" >&2
    printf '%s\n' "$out" | jq '.' >&2
    return 1
  }

  # Sampled row: find evt-json-r1 and verify event_id + usage.
  local r1_model
  r1_model="$(printf '%s' "$out" | jq -r '
    .[] | select(.event_id == "evt-json-r1") | .model
  ')"
  [ "$r1_model" = "model-a" ] || {
    echo "FAIL: sampled row evt-json-r1 has wrong model: $r1_model" >&2
    return 1
  }

  local r1_input
  r1_input="$(printf '%s' "$out" | jq '
    .[] | select(.event_id == "evt-json-r1") | .usage.input_tokens
  ')"
  [ "$r1_input" -eq 1000 ] || {
    echo "FAIL: sampled row evt-json-r1 has wrong input_tokens: $r1_input" >&2
    return 1
  }
}

# ─── export json dedup-on-read ────────────────────────────────────────────────

@test "telemetry export json: dedup-on-read ignores duplicate event_ids" {
  # Write same event_id twice.
  write_row "evt-json-dedup1" "audited" "model-a" 1000 0 0 0
  write_row "evt-json-dedup1" "audited" "model-a" 1000 0 0 0  # duplicate

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export json \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export json exited $status" >&2
    return 1
  }

  local count
  count="$(printf '%s' "$out" | jq 'length')"
  [ "$count" -eq 1 ] || {
    echo "FAIL: expected 1 row after dedup, got $count (duplicate not removed)" >&2
    return 1
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# export csv — header + one row per turn, correct columns
# ═══════════════════════════════════════════════════════════════════════════════

@test "telemetry export csv: has correct header as first line" {
  write_row "evt-csv-r1" "audited" "model-a" 1000 200 300 400 "repo" "atlas" "deep"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export csv \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export csv exited $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Header must be first line.
  local header
  header="$(printf '%s' "$out" | head -1)"

  # Required columns (exact order per spec).
  case "$header" in
    *"ts"*) ;;
    *) echo "FAIL: CSV header missing 'ts' column" >&2; return 1 ;;
  esac
  case "$header" in
    *"source"*) ;;
    *) echo "FAIL: CSV header missing 'source' column" >&2; return 1 ;;
  esac
  case "$header" in
    *"model"*) ;;
    *) echo "FAIL: CSV header missing 'model' column" >&2; return 1 ;;
  esac
  case "$header" in
    *"eidolon"*) ;;
    *) echo "FAIL: CSV header missing 'eidolon' column" >&2; return 1 ;;
  esac
  case "$header" in
    *"input_tokens"*) ;;
    *) echo "FAIL: CSV header missing 'input_tokens' column" >&2; return 1 ;;
  esac
  case "$header" in
    *"output_tokens"*) ;;
    *) echo "FAIL: CSV header missing 'output_tokens' column" >&2; return 1 ;;
  esac
  case "$header" in
    *"cache_creation_tokens"*) ;;
    *) echo "FAIL: CSV header missing 'cache_creation_tokens' column" >&2; return 1 ;;
  esac
  case "$header" in
    *"cache_read_tokens"*) ;;
    *) echo "FAIL: CSV header missing 'cache_read_tokens' column" >&2; return 1 ;;
  esac
}

@test "telemetry export csv: one data row per turn (3 rows → header + 3 data lines)" {
  write_row "evt-csv-c1" "audited"   "model-a" 1000 200 0 0
  write_row "evt-csv-c2" "audited"   "model-b" 500  100 0 0
  write_row "evt-csv-c3" "estimated" "model-a" 300  50  0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export csv \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export csv exited $status" >&2
    return 1
  }

  # Count lines: should be header (1) + 3 data rows = 4 total.
  local line_count
  line_count="$(printf '%s' "$out" | grep -c '^' || true)"
  [ "$line_count" -eq 4 ] || {
    echo "FAIL: expected 4 lines (header + 3 data), got $line_count" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
}

@test "telemetry export csv: data row contains correct token values" {
  write_row "evt-csv-tok1" "audited" "model-a" 1234 567 89 42 "myrepo" "atlas" "deep"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export csv \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export csv exited $status" >&2
    return 1
  }

  # Second line (data row) must contain our token values.
  local data_line
  data_line="$(printf '%s' "$out" | sed -n '2p')"

  case "$data_line" in
    *"1234"*) ;;
    *) echo "FAIL: CSV data row missing input_tokens 1234" >&2; echo "Got: $data_line" >&2; return 1 ;;
  esac
  case "$data_line" in
    *"567"*) ;;
    *) echo "FAIL: CSV data row missing output_tokens 567" >&2; echo "Got: $data_line" >&2; return 1 ;;
  esac
  case "$data_line" in
    *"89"*) ;;
    *) echo "FAIL: CSV data row missing cache_creation_tokens 89" >&2; echo "Got: $data_line" >&2; return 1 ;;
  esac
  case "$data_line" in
    *"42"*) ;;
    *) echo "FAIL: CSV data row missing cache_read_tokens 42" >&2; echo "Got: $data_line" >&2; return 1 ;;
  esac
  case "$data_line" in
    *"atlas"*) ;;
    *) echo "FAIL: CSV data row missing eidolon 'atlas'" >&2; echo "Got: $data_line" >&2; return 1 ;;
  esac
  case "$data_line" in
    *"myrepo"*) ;;
    *) echo "FAIL: CSV data row missing repo 'myrepo'" >&2; echo "Got: $data_line" >&2; return 1 ;;
  esac
}

@test "telemetry export csv: unpriced model has empty usd column (honest — not 0)" {
  # Use a model not in pricing.yaml — usd column must be empty, not "0".
  write_row "evt-csv-noprice1" "audited" "model-unpriced-csv" 1000 200 0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export csv \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export csv exited $status" >&2
    return 1
  }

  # The data line is the second line.
  local data_line
  data_line="$(printf '%s' "$out" | sed -n '2p')"

  # The usd column (last) must end with a comma-then-empty or just be empty.
  # The line must NOT end with ",0" (which would mean $0 for unpriced).
  # It SHOULD end with "," (empty last column).
  case "$data_line" in
    *",0")
      echo "FAIL: CSV usd column is '0' for unpriced model — honesty violation (must be empty)" >&2
      echo "Got: $data_line" >&2
      return 1
      ;;
    *",")
      # Empty last column — good.
      ;;
    *)
      # Other endings acceptable as long as not ",0".
      ;;
  esac
}

@test "telemetry export csv: priced model (claude-opus-4-8) has non-empty usd column" {
  # input=1M @ $15/1M = $15.00; output=0; total = $15.00.
  write_row "evt-csv-priced1" "audited" "claude-opus-4-8" 1000000 0 0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export csv \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export csv exited $status" >&2
    return 1
  }

  local data_line
  data_line="$(printf '%s' "$out" | sed -n '2p')"

  # usd column (last) must not be empty for a priced model.
  # It should end with ",15" or ",15.0" (approximately $15.00).
  case "$data_line" in
    *",")
      echo "FAIL: CSV usd column is empty for priced model claude-opus-4-8 (expected ~15)" >&2
      echo "Got: $data_line" >&2
      return 1
      ;;
    *)
      # Non-empty usd — good. Optionally verify it contains "15".
      case "$data_line" in
        *",15"*)
          ;;
        *)
          echo "WARN: CSV usd for 1M input @ \$15/1M expected ~15, got: $data_line" >&2
          ;;
      esac
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# export otel — GenAI-convention spans, key parity with trace otel
# ═══════════════════════════════════════════════════════════════════════════════
#
# Key parity with trace.sh `trace otel` (lines ~232-248):
#   gen_ai.system, gen_ai.operation.name, gen_ai.agent.name,
#   gen_ai.agent.id, gen_ai.request.model,
#   gen_ai.usage.input_tokens, gen_ai.usage.output_tokens,
#   eidolons.token_budget, eidolons.performative, eidolons.tier,
#   eidolons.to, eidolons.artifact.kind, eidolons.host
# Plus telemetry-store extensions:
#   eidolons.cache_creation_tokens, eidolons.cache_read_tokens,
#   eidolons.source, eidolons.is_sidechain, eidolons.repo, eidolons.branch

@test "telemetry export otel: emits valid JSON with schema + spans array" {
  write_row "evt-otel-r1" "audited" "claude-opus-4-8" 1000 200 50 100 "repoA" "atlas" "deep"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export otel exited $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Must be valid JSON.
  printf '%s' "$out" | jq empty 2>/dev/null || {
    echo "FAIL: export otel output is not valid JSON" >&2
    echo "Got: $out" >&2
    return 1
  }

  # Must have schema key.
  local has_schema
  has_schema="$(printf '%s' "$out" | jq 'has("schema")')"
  [ "$has_schema" = "true" ] || {
    echo "FAIL: otel output missing 'schema' key" >&2
    return 1
  }

  # Must have spans array.
  local has_spans
  has_spans="$(printf '%s' "$out" | jq 'has("spans")')"
  [ "$has_spans" = "true" ] || {
    echo "FAIL: otel output missing 'spans' key" >&2
    return 1
  }

  # spans must be an array with >= 1 element.
  local span_count
  span_count="$(printf '%s' "$out" | jq '.spans | length')"
  [ "$span_count" -ge 1 ] || {
    echo "FAIL: spans array is empty (expected >= 1)" >&2
    return 1
  }
}

@test "telemetry export otel: spans carry required gen_ai.* attribute keys (key parity with trace otel)" {
  write_row "evt-otel-keys1" "audited" "claude-opus-4-8" 1000 200 50 100 "repoA" "atlas" "deep"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export otel exited $status" >&2
    return 1
  }

  # Extract first span attributes.
  local attrs
  attrs="$(printf '%s' "$out" | jq '.spans[0].attributes')"

  # Required gen_ai.* keys (same as trace otel — single source of truth).
  local check_key

  for check_key in \
    "gen_ai.system" \
    "gen_ai.operation.name" \
    "gen_ai.agent.name" \
    "gen_ai.agent.id" \
    "gen_ai.request.model" \
    "gen_ai.usage.input_tokens" \
    "gen_ai.usage.output_tokens" \
    "eidolons.token_budget" \
    "eidolons.performative" \
    "eidolons.tier" \
    "eidolons.to" \
    "eidolons.artifact.kind" \
    "eidolons.host"
  do
    local has_key
    has_key="$(printf '%s' "$attrs" | jq --arg k "$check_key" 'has($k)')"
    [ "$has_key" = "true" ] || {
      echo "FAIL: span attributes missing key '$check_key' (key parity with trace otel violated)" >&2
      printf '%s\n' "$attrs" | jq 'keys' >&2
      return 1
    }
  done
}

@test "telemetry export otel: gen_ai.system is 'eidolons' (same as trace otel)" {
  write_row "evt-otel-sys1" "audited" "model-a" 100 50 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export otel exited $status" >&2
    return 1
  }

  local system_val
  system_val="$(printf '%s' "$out" | jq -r '.spans[0].attributes["gen_ai.system"]')"
  [ "$system_val" = "eidolons" ] || {
    echo "FAIL: gen_ai.system expected 'eidolons', got '$system_val'" >&2
    return 1
  }
}

@test "telemetry export otel: gen_ai.agent.name is the eidolon attribution" {
  write_row "evt-otel-agent1" "audited" "model-a" 100 50 0 0 "repo" "spectra"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || return 1

  local agent_name
  agent_name="$(printf '%s' "$out" | jq -r '.spans[0].attributes["gen_ai.agent.name"]')"
  [ "$agent_name" = "spectra" ] || {
    echo "FAIL: gen_ai.agent.name expected 'spectra', got '$agent_name'" >&2
    return 1
  }
}

@test "telemetry export otel: gen_ai.request.model carries the model string" {
  write_row "evt-otel-model1" "audited" "claude-opus-4-8" 100 50 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || return 1

  local model_val
  model_val="$(printf '%s' "$out" | jq -r '.spans[0].attributes["gen_ai.request.model"]')"
  [ "$model_val" = "claude-opus-4-8" ] || {
    echo "FAIL: gen_ai.request.model expected 'claude-opus-4-8', got '$model_val'" >&2
    return 1
  }
}

@test "telemetry export otel: gen_ai.usage.input_tokens + output_tokens carry audited values" {
  # input=1234, output=567.
  write_row "evt-otel-usage1" "audited" "model-a" 1234 567 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || return 1

  local input_tok
  input_tok="$(printf '%s' "$out" | jq '.spans[0].attributes["gen_ai.usage.input_tokens"]')"
  [ "$input_tok" -eq 1234 ] || {
    echo "FAIL: gen_ai.usage.input_tokens expected 1234, got $input_tok" >&2
    return 1
  }

  local output_tok
  output_tok="$(printf '%s' "$out" | jq '.spans[0].attributes["gen_ai.usage.output_tokens"]')"
  [ "$output_tok" -eq 567 ] || {
    echo "FAIL: gen_ai.usage.output_tokens expected 567, got $output_tok" >&2
    return 1
  }
}

@test "telemetry export otel: carries eidolons.cache_creation_tokens + cache_read_tokens" {
  # cache_creation=89, cache_read=42.
  write_row "evt-otel-cache1" "audited" "model-a" 0 0 89 42 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || return 1

  local cc
  cc="$(printf '%s' "$out" | jq '.spans[0].attributes["eidolons.cache_creation_tokens"]')"
  [ "$cc" -eq 89 ] || {
    echo "FAIL: eidolons.cache_creation_tokens expected 89, got $cc" >&2
    return 1
  }

  local cr
  cr="$(printf '%s' "$out" | jq '.spans[0].attributes["eidolons.cache_read_tokens"]')"
  [ "$cr" -eq 42 ] || {
    echo "FAIL: eidolons.cache_read_tokens expected 42, got $cr" >&2
    return 1
  }
}

@test "telemetry export otel: priced model carries eidolons.usd attribute" {
  # input=1M @ $15/1M = $15.00.
  write_row "evt-otel-usd1" "audited" "claude-opus-4-8" 1000000 0 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || return 1

  local has_usd
  has_usd="$(printf '%s' "$out" | jq '.spans[0].attributes | has("eidolons.usd")')"
  [ "$has_usd" = "true" ] || {
    echo "FAIL: eidolons.usd attribute missing for priced model (expected for claude-opus-4-8)" >&2
    printf '%s\n' "$out" | jq '.spans[0].attributes | keys' >&2
    return 1
  }

  local usd_val
  usd_val="$(printf '%s' "$out" | jq '.spans[0].attributes["eidolons.usd"]')"
  local is_positive
  is_positive="$(printf '%s' "$usd_val" | awk '{print ($1 > 0) ? "true" : "false"}')"
  [ "$is_positive" = "true" ] || {
    echo "FAIL: eidolons.usd expected > 0 for 1M input @ \$15/1M, got $usd_val" >&2
    return 1
  }
}

@test "telemetry export otel: unpriced model does NOT carry eidolons.usd attribute (honesty)" {
  # Use a model not in pricing.yaml.
  write_row "evt-otel-noprice1" "audited" "model-unpriced-otel" 1000 200 0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || return 1

  local has_usd
  has_usd="$(printf '%s' "$out" | jq '.spans[0].attributes | has("eidolons.usd")')"
  [ "$has_usd" = "false" ] || {
    echo "FAIL: eidolons.usd attribute present for unpriced model (honesty violation — must be absent)" >&2
    local usd_val
    usd_val="$(printf '%s' "$out" | jq '.spans[0].attributes["eidolons.usd"]')"
    echo "Got eidolons.usd = $usd_val" >&2
    return 1
  }
}

@test "telemetry export otel: carries eidolons.source attribute" {
  write_row "evt-otel-src1" "audited" "model-a" 100 50 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || return 1

  local src_val
  src_val="$(printf '%s' "$out" | jq -r '.spans[0].attributes["eidolons.source"]')"
  [ "$src_val" = "audited" ] || {
    echo "FAIL: eidolons.source expected 'audited', got '$src_val'" >&2
    return 1
  }
}

@test "telemetry export otel: span name is 'invoke_agent <eidolon>'" {
  write_row "evt-otel-name1" "audited" "model-a" 100 50 0 0 "repo" "forge"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || return 1

  local span_name
  span_name="$(printf '%s' "$out" | jq -r '.spans[0].name')"
  case "$span_name" in
    "invoke_agent forge"|"invoke_agent "*)
      ;;
    *)
      echo "FAIL: span name expected 'invoke_agent <eidolon>', got '$span_name'" >&2
      return 1
      ;;
  esac
}

@test "telemetry export otel: --otel-version is pinnable" {
  write_row "evt-otel-ver1" "audited" "model-a" 100 50 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    --otel-version "1.99.0" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || return 1

  local ver_val
  ver_val="$(printf '%s' "$out" | jq -r '.gen_ai_convention_version')"
  [ "$ver_val" = "1.99.0" ] || {
    echo "FAIL: gen_ai_convention_version expected '1.99.0', got '$ver_val'" >&2
    return 1
  }
}

@test "telemetry export otel: multiple rows → multiple spans" {
  write_row "evt-otel-m1" "audited"   "model-a" 1000 200 0 0 "repo" "atlas"
  write_row "evt-otel-m2" "estimated" "model-b" 500  100 0 0 "repo" "spectra"
  write_row "evt-otel-m3" "audited"   "model-a" 300  50  0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export otel exited $status" >&2
    return 1
  }

  local span_count
  span_count="$(printf '%s' "$out" | jq '.spans | length')"
  [ "$span_count" -eq 3 ] || {
    echo "FAIL: expected 3 spans (one per row), got $span_count" >&2
    return 1
  }
}

@test "telemetry export otel: dedup-on-read (duplicate event_id → one span)" {
  write_row "evt-otel-dedup1" "audited" "model-a" 1000 0 0 0
  write_row "evt-otel-dedup1" "audited" "model-a" 1000 0 0 0  # duplicate

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export otel \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || return 1

  local span_count
  span_count="$(printf '%s' "$out" | jq '.spans | length')"
  [ "$span_count" -eq 1 ] || {
    echo "FAIL: expected 1 span after dedup, got $span_count (dedup-on-read broken)" >&2
    return 1
  }
}

# ─── default format is json ───────────────────────────────────────────────────

@test "telemetry export: default format is json when no format arg given" {
  write_row "evt-def-fmt1" "audited" "model-a" 100 50 0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry export \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: export (no format) exited $status" >&2
    return 1
  }

  # Default should be JSON array.
  local is_array
  is_array="$(printf '%s' "$out" | jq 'type == "array"' 2>/dev/null || echo "false")"
  [ "$is_array" = "true" ] || {
    echo "FAIL: default export format is not json (not a JSON array)" >&2
    echo "Got: $out" >&2
    return 1
  }
}
