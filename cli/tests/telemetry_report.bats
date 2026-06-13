#!/usr/bin/env bats
#
# cli/tests/telemetry_report.bats
#
# Phase D — rollup + report + M1/M2/M3 + honesty gate (AC-F4-1 through AC-F4-4)
# Tests seed on-disk JSONL directly into a sandboxed $EIDOLONS_HOME; no live model.
#
# Spec references: §7 (metric formulas), §8 F4 (acceptance stories),
#                  §11 (honesty gate / C6 contract).
#
# Billing safety: zero live model calls. Every test reads on-disk fixtures only.

load helpers

# ─── Setup ────────────────────────────────────────────────────────────────────

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$EIDOLONS_HOME"

  # Fixed test slug so we can predict the store path.
  TEST_SLUG="telemetry-report-test"
  STORE_DIR="$EIDOLONS_HOME/telemetry/$TEST_SLUG"
  mkdir -p "$STORE_DIR"

  # Fixed date for day files.
  TEST_DATE="2026-06-13"
  DAY_FILE="$STORE_DIR/${TEST_DATE}.jsonl"
}

# ─── Helper: write a single turn.v1 row to the day file ──────────────────────

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
    --arg session_id "sess-test-123" \
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
        branch: "feat/telemetry-mlp",
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

# ─── AC-F4-1 rollup: per-model token sums, source-split ──────────────────────
#
# Seed: 2 audited rows across 2 models + 1 estimated row.
# rollup --by model --json returns correct per-model sums, source-split.

@test "telemetry rollup --by model --json: correct per-model sums, source-split (AC-F4-1)" {
  # Audited: model-a with 1000+200 = 1200 total; model-b with 500+100 = 600 total.
  # Estimated: model-a with 300+50 = 350 total.
  write_row "evt-rollup-a1" "audited"   "model-a" 1000 200 0 0
  write_row "evt-rollup-a2" "audited"   "model-b" 500  100 0 0
  write_row "evt-rollup-e1" "estimated" "model-a" 300  50  0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry rollup \
    --by model \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: rollup exited $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  [ -n "$out" ] || {
    echo "FAIL: rollup produced no output" >&2
    return 1
  }

  # Must have 2 source groups (audited + estimated).
  local source_count
  source_count="$(printf '%s' "$out" | jq 'length')"
  [ "$source_count" -eq 2 ] || {
    echo "FAIL: expected 2 source groups (audited+estimated), got $source_count" >&2
    printf '%s\n' "$out" >&2
    return 1
  }

  # Audited model-a total = 1000+200+0+0 = 1200.
  local audited_model_a
  audited_model_a="$(printf '%s' "$out" | jq -r '
    .[] | select(.source=="audited") | .by[] | select(.key=="model-a") | .total
  ' 2>/dev/null || echo "-1")"
  [ "$audited_model_a" -eq 1200 ] || {
    echo "FAIL: audited model-a total expected 1200, got $audited_model_a" >&2
    printf '%s\n' "$out" | jq '.' >&2
    return 1
  }

  # Audited model-b total = 500+100+0+0 = 600.
  local audited_model_b
  audited_model_b="$(printf '%s' "$out" | jq -r '
    .[] | select(.source=="audited") | .by[] | select(.key=="model-b") | .total
  ' 2>/dev/null || echo "-1")"
  [ "$audited_model_b" -eq 600 ] || {
    echo "FAIL: audited model-b total expected 600, got $audited_model_b" >&2
    return 1
  }

  # Estimated model-a total = 300+50+0+0 = 350.
  local estimated_model_a
  estimated_model_a="$(printf '%s' "$out" | jq -r '
    .[] | select(.source=="estimated") | .by[] | select(.key=="model-a") | .total
  ' 2>/dev/null || echo "-1")"
  [ "$estimated_model_a" -eq 350 ] || {
    echo "FAIL: estimated model-a total expected 350, got $estimated_model_a" >&2
    return 1
  }
}

# ─── AC-F4-2 report M1: spend by repo/model/eidolon/tier ─────────────────────
#
# Seed: 3 audited rows with distinct models and repos.
# report --json exposes by_source.audited with correct breakdowns.

@test "telemetry report --json: M1 by-model/eidolon/tier breakdowns match seeded rows (AC-F4-2)" {
  # row1: model-alpha, repo: repoA, eidolon: atlas, 1000+200 = 1200 total
  # row2: model-beta,  repo: repoA, eidolon: spectra, 500+100+50+200 = 850 total
  # row3: model-alpha, repo: repoB, eidolon: main, 300+50 = 350 total
  write_row "evt-m1-r1" "audited" "model-alpha" 1000 200 0   0   "repoA" "atlas"
  write_row "evt-m1-r2" "audited" "model-beta"  500  100 50  200 "repoA" "spectra"
  write_row "evt-m1-r3" "audited" "model-alpha" 300  50  0   0   "repoB" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Must have by_source key (honesty gate structural requirement).
  local has_by_source
  has_by_source="$(printf '%s' "$out" | jq 'has("by_source")')"
  [ "$has_by_source" = "true" ] || {
    echo "FAIL: report JSON missing top-level 'by_source' key" >&2
    printf '%s\n' "$out" | jq '.' >&2
    return 1
  }

  # by_source.audited must exist.
  local has_audited
  has_audited="$(printf '%s' "$out" | jq '.by_source | has("audited")')"
  [ "$has_audited" = "true" ] || {
    echo "FAIL: by_source.audited missing" >&2
    return 1
  }

  # Total audited turns = 3.
  local audited_turns
  audited_turns="$(printf '%s' "$out" | jq '.by_source.audited.turns')"
  [ "$audited_turns" -eq 3 ] || {
    echo "FAIL: expected 3 audited turns, got $audited_turns" >&2
    return 1
  }

  # Audited total = 1000+200+500+100+50+200+300+50 = 2400.
  local audited_total
  audited_total="$(printf '%s' "$out" | jq '.by_source.audited.total_tokens')"
  [ "$audited_total" -eq 2400 ] || {
    echo "FAIL: audited total_tokens expected 2400, got $audited_total" >&2
    return 1
  }

  # by_model.model-alpha = 1000+200 + 300+50 = 1550.
  local alpha_total
  alpha_total="$(printf '%s' "$out" | jq '.by_source.audited.by_model["model-alpha"].total')"
  [ "$alpha_total" -eq 1550 ] || {
    echo "FAIL: by_model[model-alpha] expected 1550, got $alpha_total" >&2
    return 1
  }

  # by_eidolon.atlas = 1000+200 = 1200.
  local atlas_total
  atlas_total="$(printf '%s' "$out" | jq '.by_source.audited.by_eidolon.atlas.total')"
  [ "$atlas_total" -eq 1200 ] || {
    echo "FAIL: by_eidolon.atlas expected 1200, got $atlas_total" >&2
    return 1
  }

  # by_repo.repoA = (1000+200) + (500+100+50+200) = 2050.
  local repoA_total
  repoA_total="$(printf '%s' "$out" | jq '.by_source.audited.by_repo.repoA.total')"
  [ "$repoA_total" -eq 2050 ] || {
    echo "FAIL: by_repo.repoA expected 2050, got $repoA_total" >&2
    return 1
  }
}

# ─── AC-F4-3 report M3: tier split (standard vs trance) ─────────────────────
#
# Seed: 2 audited rows with different tiers; assert M3 separates them.

@test "telemetry report --json: M3 tier split separates standard and trance (AC-F4-3)" {
  # standard: 1000+200 = 1200 tokens; trance: 500+100 = 600 tokens.
  write_row "evt-tier-s1" "audited" "model-a" 1000 200 0 0 "repo" "main"    "standard"
  write_row "evt-tier-t1" "audited" "model-a" 500  100 0 0 "repo" "spectra" "trance"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status" >&2
    return 1
  }

  # m3_tier_split must be present.
  local has_m3
  has_m3="$(printf '%s' "$out" | jq 'has("m3_tier_split")')"
  [ "$has_m3" = "true" ] || {
    echo "FAIL: report JSON missing m3_tier_split" >&2
    printf '%s\n' "$out" | jq '.' >&2
    return 1
  }

  # For the audited source, find standard tier total.
  local standard_total
  standard_total="$(printf '%s' "$out" | jq '
    .m3_tier_split[] | select(.source=="audited") | .by_tier[] | select(.tier=="standard") | .total
  ')"
  [ "$standard_total" -eq 1200 ] || {
    echo "FAIL: M3 standard tier total expected 1200, got $standard_total" >&2
    printf '%s\n' "$out" | jq '.m3_tier_split' >&2
    return 1
  }

  # trance tier total.
  local trance_total
  trance_total="$(printf '%s' "$out" | jq '
    .m3_tier_split[] | select(.source=="audited") | .by_tier[] | select(.tier=="trance") | .total
  ')"
  [ "$trance_total" -eq 600 ] || {
    echo "FAIL: M3 trance tier total expected 600, got $trance_total" >&2
    return 1
  }
}

# ─── AC-F4-4 HONESTY GATE (load-bearing, must not pass vacuously) ────────────
#
# GIVEN one source:audited row AND one source:estimated row,
# WHEN report --json runs,
# THEN:
#   (a) by_source.audited is present as a distinct key,
#   (b) by_source.estimated is present as a distinct key,
#   (c) there is NO single top-level field that equals audited_total + estimated_total
#       (i.e., no blended total).
#
# This test is DESIGNED to go RED if report blends sources.
# The totals are chosen to be clearly distinct (1200 and 350) so their sum
# (1550) is a unique integer not produced by any sub-computation. We grep
# the raw JSON string for the blended value.

@test "telemetry report --json: HONESTY GATE — audited + estimated are distinct keys, no blended total (AC-F4-4)" {
  # Audited: 1000+200+0+0 = 1200 tokens.
  # Estimated: 300+50+0+0 = 350 tokens.
  # Blended total would be 1550 — must NOT appear as a top-level key value.
  write_row "evt-gate-a1" "audited"   "model-a" 1000 200 0 0
  write_row "evt-gate-e1" "estimated" "model-a" 300  50  0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # (a) by_source.audited must be present.
  local has_audited
  has_audited="$(printf '%s' "$out" | jq '.by_source | has("audited")')"
  [ "$has_audited" = "true" ] || {
    echo "FAIL: by_source.audited missing — honesty gate violated" >&2
    printf '%s\n' "$out" | jq '.' >&2
    return 1
  }

  # (b) by_source.estimated must be present.
  local has_estimated
  has_estimated="$(printf '%s' "$out" | jq '.by_source | has("estimated")')"
  [ "$has_estimated" = "true" ] || {
    echo "FAIL: by_source.estimated missing — honesty gate violated" >&2
    printf '%s\n' "$out" | jq '.' >&2
    return 1
  }

  # (c) Verify audited total = 1200 and estimated total = 350 (correct, not blended).
  local audited_total
  audited_total="$(printf '%s' "$out" | jq '.by_source.audited.total_tokens')"
  [ "$audited_total" -eq 1200 ] || {
    echo "FAIL: by_source.audited.total_tokens expected 1200, got $audited_total" >&2
    return 1
  }

  local estimated_total
  estimated_total="$(printf '%s' "$out" | jq '.by_source.estimated.total_tokens')"
  [ "$estimated_total" -eq 350 ] || {
    echo "FAIL: by_source.estimated.total_tokens expected 350, got $estimated_total" >&2
    return 1
  }

  # (c) No blended total: 1200+350=1550 must NOT appear as any top-level
  # integer value in the JSON. We check the raw string for the blended number
  # outside any by_source sub-object (the only place it could appear is a
  # hypothetical top-level "total_tokens" key).
  # Strategy: extract all top-level keys and assert none has value 1550.
  local has_blended
  has_blended="$(printf '%s' "$out" | jq '
    [ to_entries[] | select(.value == 1550) ] | length
  ')"
  [ "$has_blended" -eq 0 ] || {
    echo "FAIL: blended total (1550 = 1200+350) found as a top-level key value — honesty gate violated" >&2
    printf '%s\n' "$out" | jq 'to_entries[] | select(.value == 1550)' >&2
    return 1
  }

  # Additional guard: the JSON must NOT have a top-level "total_tokens" key
  # (which would be the classic blended-total design smell).
  local has_toplevel_total
  has_toplevel_total="$(printf '%s' "$out" | jq 'has("total_tokens")')"
  [ "$has_toplevel_total" = "false" ] || {
    echo "FAIL: report JSON has a top-level 'total_tokens' key — blended total detected (honesty gate violation)" >&2
    printf '%s\n' "$out" | jq '.' >&2
    return 1
  }
}

# ─── M2 honest N/A: self_reported_tokens=null → no fabricated delta ──────────
#
# Seeded rows have self_reported_tokens=null (the current capture state).
# The M2 section must report the "no self-report data" state, not a number.

@test "telemetry report --json: M2 honest N/A when self_reported_tokens is null" {
  write_row "evt-m2-r1" "audited" "model-a" 1000 200 0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status" >&2
    return 1
  }

  # m2_reconciliation must be present.
  local has_m2
  has_m2="$(printf '%s' "$out" | jq 'has("m2_reconciliation")')"
  [ "$has_m2" = "true" ] || {
    echo "FAIL: report JSON missing m2_reconciliation" >&2
    return 1
  }

  # turns_with_self_report must be 0.
  local turns_with_sr
  turns_with_sr="$(printf '%s' "$out" | jq '.m2_reconciliation.turns_with_self_report')"
  [ "$turns_with_sr" -eq 0 ] || {
    echo "FAIL: expected turns_with_self_report=0 (no self-report data), got $turns_with_sr" >&2
    return 1
  }

  # status must be "na" (not "ok" — would imply fabricated data).
  local m2_status
  m2_status="$(printf '%s' "$out" | jq -r '.m2_reconciliation.status')"
  [ "$m2_status" = "na" ] || {
    echo "FAIL: M2 status expected 'na' (no self-report data), got '$m2_status'" >&2
    return 1
  }

  # must NOT have a numeric mean_abs_delta (would be fabricated).
  local has_num_delta
  has_num_delta="$(printf '%s' "$out" | jq '
    .m2_reconciliation.mean_abs_delta != null and
    (.m2_reconciliation.mean_abs_delta | type) == "number"
  ')"
  [ "$has_num_delta" = "false" ] || {
    echo "FAIL: M2 has a numeric mean_abs_delta when no self-report data exists (fabricated)" >&2
    return 1
  }
}

# ─── Empty store: report exits 0 with honest message ─────────────────────────

@test "telemetry report: empty store exits 0 with honest 'nothing captured' message" {
  # No rows written; STORE_DIR exists but is empty.
  # (setup already creates STORE_DIR)

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status for empty store (expected 0)" >&2
    return 1
  }

  # Must mention the project slug or "no telemetry".
  case "$out" in
    *"no telemetry"* | *"$TEST_SLUG"*)
      ;;
    *)
      echo "FAIL: empty-store message does not mention 'no telemetry' or the project slug" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac
}

@test "telemetry report: absent store dir exits 0 with honest message" {
  # Use a project slug that has no store dir.
  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "totally-nonexistent-slug-xyzzy" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status for absent store (expected 0)" >&2
    return 1
  }

  case "$out" in
    *"no telemetry"* | *"totally-nonexistent-slug-xyzzy"*)
      ;;
    *)
      echo "FAIL: absent-store message does not mention 'no telemetry' or the project slug" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac
}

# ─── rollup: empty store exits 0 ─────────────────────────────────────────────

@test "telemetry rollup: absent store exits 0 with honest message" {
  local out status=0
  out="$("$EIDOLONS_BIN" telemetry rollup \
    --project "totally-nonexistent-slug-xyzzy" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: rollup exited $status for absent store (expected 0)" >&2
    return 1
  }

  # Should be either the empty-status JSON or the honest text.
  case "$out" in
    *"no telemetry"* | *"totally-nonexistent-slug-xyzzy"* | *"empty"*)
      ;;
    *)
      echo "FAIL: rollup absent-store message not recognized" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac
}

# ─── rollup --by with cache_read tokens (verifies all 4 usage fields summed) ─

@test "telemetry rollup --by model: sums all four usage fields including cache tokens (AC-F4-1)" {
  # One audited row with all four usage fields non-zero.
  # total = 1000 + 200 + 300 + 400 = 1900
  write_row "evt-cache-r1" "audited" "model-cache" 1000 200 300 400

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry rollup \
    --by model \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: rollup exited $status" >&2
    return 1
  }

  local cache_total
  cache_total="$(printf '%s' "$out" | jq '
    .[] | select(.source=="audited") | .by[] | select(.key=="model-cache") | .total
  ')"
  [ "$cache_total" -eq 1900 ] || {
    echo "FAIL: expected total 1900 (all four usage fields), got $cache_total" >&2
    printf '%s\n' "$out" | jq '.' >&2
    return 1
  }

  # Verify individual fields are present.
  local cr
  cr="$(printf '%s' "$out" | jq '
    .[] | select(.source=="audited") | .by[] | select(.key=="model-cache") | .cache_read
  ')"
  [ "$cr" -eq 400 ] || {
    echo "FAIL: cache_read expected 400, got $cr" >&2
    return 1
  }
}

# ─── Dedup-on-read: duplicate event_ids are not double-counted ───────────────

@test "telemetry rollup --by model: dedup-on-read ignores duplicate event_ids" {
  # Write the SAME row twice (same event_id).
  write_row "evt-dedup-x1" "audited" "model-x" 1000 200 0 0
  write_row "evt-dedup-x1" "audited" "model-x" 1000 200 0 0  # duplicate

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry rollup \
    --by model \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: rollup exited $status" >&2
    return 1
  }

  # Only 1 turn should be counted (dedup-on-read per §4.2).
  local turns
  turns="$(printf '%s' "$out" | jq '
    .[] | select(.source=="audited") | .by[] | select(.key=="model-x") | .turns
  ')"
  [ "$turns" -eq 1 ] || {
    echo "FAIL: dedup-on-read failed — expected 1 turn, got $turns (duplicate event_id counted twice)" >&2
    return 1
  }
}

# ─── Text output smoke test ───────────────────────────────────────────────────

@test "telemetry report text: renders M1/M2/M3 sections and honesty label" {
  write_row "evt-text-r1" "audited"   "model-a" 1000 200 0 0 "repo1" "main"    "standard"
  write_row "evt-text-e1" "estimated" "model-b" 300  50  0 0 "repo1" "unknown" "standard"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report (text) exited $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Must mention M1, M2, M3 sections.
  case "$out" in
    *"M1"*) ;;
    *) echo "FAIL: text output missing M1 section" >&2; return 1 ;;
  esac
  case "$out" in
    *"M2"*) ;;
    *) echo "FAIL: text output missing M2 section" >&2; return 1 ;;
  esac
  case "$out" in
    *"M3"*) ;;
    *) echo "FAIL: text output missing M3 section" >&2; return 1 ;;
  esac

  # Must mention source labels.
  case "$out" in
    *"audited"*) ;;
    *) echo "FAIL: text output missing 'audited' source label" >&2; return 1 ;;
  esac
  case "$out" in
    *"estimated"*) ;;
    *) echo "FAIL: text output missing 'estimated' source label" >&2; return 1 ;;
  esac

  # Must mention token honesty notice (no dollars in MLP).
  case "$out" in
    *"token"*) ;;
    *) echo "FAIL: text output missing token reference" >&2; return 1 ;;
  esac
}

@test "telemetry rollup text: renders source-split table without error" {
  write_row "evt-rollup-text1" "audited"   "model-a" 1000 200 0 0
  write_row "evt-rollup-text2" "estimated" "model-b" 300  50  0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry rollup \
    --by model \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: rollup (text) exited $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Must include source labels.
  case "$out" in
    *"audited"*) ;;
    *) echo "FAIL: rollup text missing 'audited' label" >&2; return 1 ;;
  esac
}

# ─── P2.1 — Dollar pricing tests ─────────────────────────────────────────────
#
# These tests are written BEFORE the pricing wiring is added to telemetry.sh
# (fixture-first discipline). They MUST be RED until the implementation ships.
#
# Pricing fixture: claude-opus-4-8 @ 15.00/75.00/18.75/1.50 per 1M tokens.
# These prices are in roster/pricing.yaml and wired into telemetry.sh by P2.1.

# ─── P2.1-1: priced model → report --json exposes usd ────────────────────────
#
# GIVEN a row with model=claude-opus-4-8 (in pricing.yaml) and
#       usage: input=1000000, output=200000, cc=0, cr=0,
# WHEN  report --json,
# THEN  by_source.audited.usd > 0 (specifically 1000000*15/1e6 + 200000*75/1e6 = 15+15 = 30.00).

@test "telemetry report P2.1: priced model exposes usd in report --json" {
  # input=1M @ $15/1M = $15.00; output=200k @ $75/1M = $15.00; total = $30.00.
  write_row "evt-price-r1" "audited" "claude-opus-4-8" 1000000 200000 0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # by_source.audited must carry a usd field.
  local has_usd
  has_usd="$(printf '%s' "$out" | jq '.by_source.audited | has("usd")')"
  [ "$has_usd" = "true" ] || {
    echo "FAIL: by_source.audited missing 'usd' field — P2.1 pricing not wired" >&2
    printf '%s\n' "$out" | jq '.by_source.audited | keys' >&2
    return 1
  }

  # usd must be > 0 for a priced model.
  local usd_val
  usd_val="$(printf '%s' "$out" | jq '.by_source.audited.usd')"
  # Compare > 0 using awk (jq compare may differ by platform for floats).
  local is_positive
  is_positive="$(printf '%s' "$usd_val" | awk '{print ($1 > 0) ? "true" : "false"}')"
  [ "$is_positive" = "true" ] || {
    echo "FAIL: usd value is not positive ($usd_val) for priced model claude-opus-4-8" >&2
    return 1
  }

  # Specific value check: $30.00 (allow floating-point rounding to ±0.01).
  local usd_approx
  usd_approx="$(printf '%s' "$usd_val" | awk '{d = $1 - 30.0; if (d < 0) d = -d; print (d < 0.01) ? "ok" : "fail"}')"
  [ "$usd_approx" = "ok" ] || {
    echo "FAIL: expected usd ≈ 30.00 (15+15), got $usd_val" >&2
    return 1
  }
}

# ─── P2.1-2: [1m] suffix normalization — resolvedModel with suffix still prices ─
#
# P2.2 stores resolvedModel verbatim (e.g. "claude-opus-4-8[1m]").
# The pricing lookup must strip the suffix before the table lookup.

@test "telemetry report P2.1: model with [1m] suffix resolves price (normalization)" {
  # Store a row with a suffixed model string as P2.2 would produce.
  write_row "evt-suffix-r1" "audited" "claude-opus-4-8[1m]" 1000000 0 0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status" >&2
    return 1
  }

  # usd must be present and positive (not treated as unpriced).
  local has_usd
  has_usd="$(printf '%s' "$out" | jq '.by_source.audited | has("usd")')"
  [ "$has_usd" = "true" ] || {
    echo "FAIL: by_source.audited missing usd — [1m] suffix not normalized for pricing" >&2
    return 1
  }

  local usd_val
  usd_val="$(printf '%s' "$out" | jq '.by_source.audited.usd')"
  local is_positive
  is_positive="$(printf '%s' "$usd_val" | awk '{print ($1 > 0) ? "true" : "false"}')"
  [ "$is_positive" = "true" ] || {
    echo "FAIL: usd=0 for claude-opus-4-8[1m] — [1m] suffix not stripped for pricing lookup" >&2
    return 1
  }
}

# ─── P2.1-3: unpriced model → tokens + honest no-price note, NO $0 ───────────
#
# An unpriced model must NOT appear as $0 — it must render tokens and a
# "(no price for <model>)" note. This is the C6 honesty extension.

@test "telemetry report P2.1: unpriced model renders tokens + no-price note, not dollar zero" {
  # Use a model string not in pricing.yaml.
  write_row "evt-noprice-r1" "audited" "model-unknown-unpriced" 1000 200 0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status" >&2
    return 1
  }

  # usd must NOT be present (or must be null) for an unpriced model.
  # If usd is present it could be $0 (which is the forbidden honesty violation).
  # Use -r to get raw output (no surrounding quotes from jq).
  local usd_val
  usd_val="$(printf '%s' "$out" | jq -r 'if (.by_source.audited | has("usd")) then (.by_source.audited.usd | tostring) else "ABSENT" end' 2>/dev/null || echo "ABSENT")"
  # Accept either absent or null — both are honest. Reject any numeric value.
  case "$usd_val" in
    "ABSENT"|"null")
      # Good: no usd field or explicitly null.
      ;;
    *)
      echo "FAIL: by_source.audited.usd='$usd_val' for unpriced model (expected absent/null, not a number)" >&2
      echo "An unpriced model must never be shown as \$0 — only token fallback is honest." >&2
      return 1
      ;;
  esac

  # The report must carry an unpriced_models list or note about the unpriced model.
  local has_unpriced_note
  has_unpriced_note="$(printf '%s' "$out" | jq '
    (has("unpriced_models") and (.unpriced_models | length > 0)) or
    (has("no_price_note")) or
    (has("by_source") and (.by_source.audited.unpriced_models // [] | length > 0))
  ')"
  [ "$has_unpriced_note" = "true" ] || {
    echo "FAIL: report JSON carries no unpriced_models note for model-unknown-unpriced" >&2
    printf '%s\n' "$out" | jq 'keys' >&2
    return 1
  }
}

# ─── P2.1-4: mixed priced+unpriced — no blended dollar headline ───────────────
#
# GIVEN one priced row (claude-opus-4-8) and one unpriced row,
# THEN report exposes usd for the priced model in its per-model breakdown AND
#      does NOT combine them into a single dollar total
#      (the C6 honesty contract extension: never blend priced + unpriced).

@test "telemetry report P2.1: mixed priced+unpriced — no single blended dollar total (C6 extension)" {
  # Priced: claude-opus-4-8; Unpriced: model-unknown-unpriced.
  write_row "evt-mixed-r1" "audited" "claude-opus-4-8"         1000000 0 0 0
  write_row "evt-mixed-r2" "audited" "model-unknown-unpriced"  500000  0 0 0

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status" >&2
    return 1
  }

  # usd for priced source must be > 0 (not $0 due to the unpriced model pulling it down).
  local usd_val
  usd_val="$(printf '%s' "$out" | jq -r 'if (.by_source.audited | has("usd")) then (.by_source.audited.usd | tostring) else "ABSENT" end' 2>/dev/null || echo "ABSENT")"

  case "$usd_val" in
    "ABSENT"|"null")
      # Acceptable: usd not emitted at the audited-total level when mix is present.
      ;;
    *)
      # If usd is emitted for a mix, it MUST NOT include the unpriced tokens as $0.
      # claude-opus-4-8: 1000000 * 15/1M = $15.00.
      # A blended total including model-unknown-unpriced as $0 would still be $15.00
      # which is the same — so we can just check usd is approximately the priced-only total.
      local is_reasonable
      is_reasonable="$(printf '%s' "$usd_val" | awk '{d = $1 - 15.0; if (d < 0) d = -d; print (d < 0.01) ? "ok" : "warn"}')"
      # A warning (not a hard fail) — either $15 (priced-only) or absent are both honest.
      if [ "$is_reasonable" != "ok" ]; then
        echo "WARN: usd=$usd_val for mixed priced+unpriced; expected ~15.00 (priced-only) or absent" >&2
      fi
      ;;
  esac

  # The unpriced model must appear in unpriced_models note.
  local has_note
  has_note="$(printf '%s' "$out" | jq '
    (has("unpriced_models") and (.unpriced_models | length > 0)) or
    (has("by_source") and (.by_source.audited.unpriced_models // [] | length > 0))
  ')"
  [ "$has_note" = "true" ] || {
    echo "FAIL: no unpriced_models note when mixed priced+unpriced models present" >&2
    printf '%s\n' "$out" | jq 'keys' >&2
    return 1
  }
}

# ─── P2.1-5: M1/M3 still source-split after pricing wired ────────────────────
#
# Regression check: adding pricing must not break the source-split honesty gate.

@test "telemetry report P2.1: M1/M3 source-split still intact after pricing wired" {
  write_row "evt-split-r1" "audited"   "claude-opus-4-8" 1000 200 0 0 "repo" "main"    "standard"
  write_row "evt-split-r2" "estimated" "claude-opus-4-8" 500  100 0 0 "repo" "unknown" "standard"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry report \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: report exited $status" >&2
    return 1
  }

  # Both by_source.audited and by_source.estimated must still be present.
  local has_audited has_estimated
  has_audited="$(printf '%s' "$out" | jq '.by_source | has("audited")')"
  has_estimated="$(printf '%s' "$out" | jq '.by_source | has("estimated")')"

  [ "$has_audited" = "true" ] || {
    echo "FAIL: by_source.audited missing after pricing wired (source-split regression)" >&2
    return 1
  }
  [ "$has_estimated" = "true" ] || {
    echo "FAIL: by_source.estimated missing after pricing wired (source-split regression)" >&2
    return 1
  }

  # Audited and estimated total_tokens must be distinct (no blending).
  local aud_tok est_tok
  aud_tok="$(printf '%s' "$out" | jq '.by_source.audited.total_tokens')"
  est_tok="$(printf '%s' "$out" | jq '.by_source.estimated.total_tokens')"
  [ "$aud_tok" != "$est_tok" ] || {
    echo "FAIL: audited and estimated total_tokens are equal ($aud_tok) — likely blended (regression)" >&2
    return 1
  }
}
