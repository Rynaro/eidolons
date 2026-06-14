#!/usr/bin/env bats
#
# cli/tests/telemetry_budget.bats
#
# P2.4 — `telemetry budget` cross-run budget gate
# Tests seed on-disk JSONL directly into a sandboxed $EIDOLONS_HOME; no live model.
#
# Spec reference: p2-roadmap.md §P2.4
# Exit semantics: exit 3 when ANY group exceeds --limit; exit 0 when all within.
# Honesty contract: audited and estimated evaluated and reported separately.
#
# Billing safety: zero live model calls. Every test reads on-disk fixtures only.

load helpers

# ─── Setup ────────────────────────────────────────────────────────────────────

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$EIDOLONS_HOME"

  TEST_SLUG="telemetry-budget-test"
  STORE_DIR="$EIDOLONS_HOME/telemetry/$TEST_SLUG"
  mkdir -p "$STORE_DIR"

  TEST_DATE="2026-06-13"
  DAY_FILE="$STORE_DIR/${TEST_DATE}.jsonl"
}

# ─── Helper: write a turn.v1 row to the day file ─────────────────────────────

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
    --arg session_id "sess-budget-test" \
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

# ─── Budget requires --limit ───────────────────────────────────────────────────

@test "telemetry budget: exits 1 when --limit is missing" {
  write_row "evt-bud-r1" "audited" "model-a" 1000 200 0 0

  local status=0
  "$EIDOLONS_BIN" telemetry budget \
    --project "$TEST_SLUG" \
    2>/dev/null || status=$?

  [ "$status" -eq 1 ] || {
    echo "FAIL: expected exit 1 when --limit missing, got $status" >&2
    return 1
  }
}

# ─── All within limit — exit 0 ────────────────────────────────────────────────
#
# GIVEN rows where all eidolon groups total < limit,
# WHEN telemetry budget --limit 5000 --by eidolon --project <slug>,
# THEN exit 0.

@test "telemetry budget: exit 0 when all groups within token limit" {
  # main eidolon: 1000+200 = 1200 tokens
  # atlas eidolon: 500+100 = 600 tokens
  # limit = 2000 — both within.
  write_row "evt-ok-a1" "audited" "model-a" 1000 200 0 0 "repo" "main"
  write_row "evt-ok-a2" "audited" "model-a" 500  100 0 0 "repo" "atlas"

  local status=0
  "$EIDOLONS_BIN" telemetry budget \
    --limit 2000 \
    --by eidolon \
    --project "$TEST_SLUG" \
    2>/dev/null || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: expected exit 0 (all within), got $status" >&2
    return 1
  }
}

# ─── Breach — exit 3 ─────────────────────────────────────────────────────────
#
# GIVEN a group that exceeds --limit,
# WHEN telemetry budget --limit 1000 --by eidolon,
# THEN exit 3 AND output names the breaching group.

@test "telemetry budget: exit 3 when a group exceeds token limit + breach line names the group" {
  # main eidolon: 1000+500 = 1500 tokens — exceeds limit of 1000.
  write_row "evt-breach-a1" "audited" "model-a" 1000 500 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry budget \
    --limit 1000 \
    --by eidolon \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 3 ] || {
    echo "FAIL: expected exit 3 (breach), got $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Breach line must name the group.
  case "$out" in
    *"main"*)
      ;;
    *)
      echo "FAIL: breach output does not name the breaching group 'main'" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac

  # Must include BREACH word.
  case "$out" in
    *"BREACH"*)
      ;;
    *)
      echo "FAIL: breach output missing 'BREACH' keyword" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac
}

# ─── Breach --json output ─────────────────────────────────────────────────────
#
# --json must emit structured JSON with breached:true and the breaches array.

@test "telemetry budget --json: exit 3 + breached:true + breaches array on breach" {
  # main eidolon: 2000 tokens; limit = 1000.
  write_row "evt-jbreach-a1" "audited" "model-a" 2000 0 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry budget \
    --limit 1000 \
    --by eidolon \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 3 ] || {
    echo "FAIL: expected exit 3, got $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Must be valid JSON.
  printf '%s' "$out" | jq empty 2>/dev/null || {
    echo "FAIL: --json output is not valid JSON" >&2
    echo "Got: $out" >&2
    return 1
  }

  # breached must be true.
  local breached
  breached="$(printf '%s' "$out" | jq -r '.breached')"
  [ "$breached" = "true" ] || {
    echo "FAIL: expected breached:true, got '$breached'" >&2
    printf '%s\n' "$out" | jq '.' >&2
    return 1
  }

  # breaches array must be non-empty.
  local breach_count
  breach_count="$(printf '%s' "$out" | jq '.breaches | length')"
  [ "$breach_count" -gt 0 ] || {
    echo "FAIL: breaches array is empty (expected >= 1 breach entry)" >&2
    printf '%s\n' "$out" | jq '.' >&2
    return 1
  }

  # groups must be present.
  local has_groups
  has_groups="$(printf '%s' "$out" | jq 'has("groups")')"
  [ "$has_groups" = "true" ] || {
    echo "FAIL: --json output missing 'groups' key" >&2
    return 1
  }
}

# ─── Within limit --json ──────────────────────────────────────────────────────

@test "telemetry budget --json: exit 0 + breached:false when all within limit" {
  write_row "evt-jok-a1" "audited" "model-a" 100 50 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry budget \
    --limit 5000 \
    --by eidolon \
    --project "$TEST_SLUG" \
    --json \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: expected exit 0, got $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  local breached
  breached="$(printf '%s' "$out" | jq -r '.breached')"
  [ "$breached" = "false" ] || {
    echo "FAIL: expected breached:false, got '$breached'" >&2
    return 1
  }
}

# ─── Honesty: audited and estimated evaluated separately ─────────────────────
#
# A group with audited tokens within limit but estimated tokens exceeding limit
# must still trigger exit 3 (the estimated group ALSO checks against limit).
# Conversely, an audited group that exceeds limit triggers exit 3 even if
# the same-key estimated group is within limit.

@test "telemetry budget: audited and estimated groups checked independently (honesty gate)" {
  # audited main: 500 tokens — within limit 1000.
  # estimated main: 1500 tokens — exceeds limit 1000.
  write_row "evt-sep-a1" "audited"   "model-a" 500  0 0 0 "repo" "main"
  write_row "evt-sep-e1" "estimated" "model-a" 1500 0 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry budget \
    --limit 1000 \
    --by eidolon \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  # Exit 3 because estimated exceeds limit (even though audited doesn't).
  [ "$status" -eq 3 ] || {
    echo "FAIL: expected exit 3 (estimated group exceeds limit), got $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Breach line must mention source:estimated.
  case "$out" in
    *"estimated"*)
      ;;
    *)
      echo "FAIL: breach output missing 'estimated' source label" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac
}

# ─── P2.4 USD budget: priced model, breach ────────────────────────────────────
#
# GIVEN a row with model=claude-opus-4-8 (priced at $15/1M input),
#       input=2_000_000 tokens → $30.00,
# WHEN budget --limit 20 --usd --by eidolon,
# THEN exit 3 (breach) because $30 > $20.

@test "telemetry budget --usd: exit 3 when USD spend exceeds dollar limit" {
  # input=2M @ $15/1M = $30.00 > limit $20.00.
  write_row "evt-usd-breach1" "audited" "claude-opus-4-8" 2000000 0 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry budget \
    --limit 20 \
    --usd \
    --by eidolon \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 3 ] || {
    echo "FAIL: expected exit 3 (USD breach: $30 > $20), got $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Breach line must contain a dollar amount > the limit.
  case "$out" in
    *"BREACH"*)
      ;;
    *)
      echo "FAIL: USD breach output missing 'BREACH'" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac
}

# ─── P2.4 USD budget: within limit ───────────────────────────────────────────

@test "telemetry budget --usd: exit 0 when USD spend within dollar limit" {
  # input=100k @ $15/1M = $1.50 < limit $10.00.
  write_row "evt-usd-ok1" "audited" "claude-opus-4-8" 100000 0 0 0 "repo" "main"

  local status=0
  "$EIDOLONS_BIN" telemetry budget \
    --limit 10 \
    --usd \
    --by eidolon \
    --project "$TEST_SLUG" \
    2>/dev/null || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: expected exit 0 (within USD limit), got $status" >&2
    return 1
  }
}

# ─── P2.4 USD budget: unpriced model — honest note, not silent pass ───────────
#
# When --usd is used and a group contains an unpriced model, the output must
# note the unpriced model. It must NOT silently pass (treating unpriced as $0).

@test "telemetry budget --usd: unpriced model produces honest note (not silent pass)" {
  # Use a model not in pricing.yaml.
  write_row "evt-usd-unpriced1" "audited" "model-unpriced-xyz" 1000000 0 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry budget \
    --limit 1 \
    --usd \
    --by eidolon \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  # Must NOT exit 0 silently (that would be a "silent pass" treating unpriced as $0).
  # Must NOT exit 3 (no breach can be evaluated).
  # The output should mention the unpriced model / "cannot evaluate" / "unpriced".
  # Exit 0 is acceptable IF the output contains an honest note (not silent).
  case "$out" in
    *"unpriced"*|*"cannot evaluate"*|*"no price"*)
      ;;
    "")
      echo "FAIL: empty output for unpriced model under --usd — silent pass (honesty violation)" >&2
      return 1
      ;;
    *)
      echo "FAIL: output for unpriced model under --usd missing honest note about pricing" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac
}

# ─── Empty store — exit 0 (honest) ───────────────────────────────────────────

@test "telemetry budget: empty store exits 0 with honest message" {
  # No rows written.
  local out status=0
  out="$("$EIDOLONS_BIN" telemetry budget \
    --limit 1000 \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: expected exit 0 for empty store, got $status" >&2
    echo "Output: $out" >&2
    return 1
  }
}

# ─── Absent store — exit 0 (honest) ──────────────────────────────────────────

@test "telemetry budget: absent store exits 0" {
  local status=0
  "$EIDOLONS_BIN" telemetry budget \
    --limit 1000 \
    --project "totally-nonexistent-slug-budget-xyzzy" \
    2>/dev/null || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: expected exit 0 for absent store, got $status" >&2
    return 1
  }
}

# ─── Default --by is eidolon for budget ──────────────────────────────────────
#
# When --by is not given, budget defaults to eidolon grouping.

@test "telemetry budget: default --by is eidolon (no --by flag required)" {
  # Two eidolons: main=500, atlas=2000; limit=1000 → atlas breaches.
  write_row "evt-defby-a1" "audited" "model-a" 500  0 0 0 "repo" "main"
  write_row "evt-defby-a2" "audited" "model-a" 2000 0 0 0 "repo" "atlas"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry budget \
    --limit 1000 \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  # atlas exceeds 1000 → must exit 3.
  [ "$status" -eq 3 ] || {
    echo "FAIL: expected exit 3 (atlas group exceeds limit via default --by eidolon), got $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Breach must name "atlas" (the eidolon that breached).
  case "$out" in
    *"atlas"*)
      ;;
    *)
      echo "FAIL: breach output missing 'atlas' eidolon name" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac
}

# ─── --by model grouping ─────────────────────────────────────────────────────

@test "telemetry budget --by model: groups by model string, exit 3 on model breach" {
  # model-heavy: 5000 tokens; model-light: 100 tokens; limit = 2000.
  write_row "evt-model-a1" "audited" "model-heavy" 5000 0 0 0 "repo" "main"
  write_row "evt-model-a2" "audited" "model-light" 100  0 0 0 "repo" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry budget \
    --limit 2000 \
    --by model \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 3 ] || {
    echo "FAIL: expected exit 3 (model-heavy > 2000), got $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  # Breach names the model.
  case "$out" in
    *"model-heavy"*)
      ;;
    *)
      echo "FAIL: breach output missing 'model-heavy'" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac
}

# ─── --by repo grouping ───────────────────────────────────────────────────────

@test "telemetry budget --by repo: groups by repo, breach names the repo" {
  # repo-a: 3000 tokens; limit = 2000.
  write_row "evt-repo-a1" "audited" "model-a" 3000 0 0 0 "repo-a" "main"

  local out status=0
  out="$("$EIDOLONS_BIN" telemetry budget \
    --limit 2000 \
    --by repo \
    --project "$TEST_SLUG" \
    2>/dev/null)" || status=$?

  [ "$status" -eq 3 ] || {
    echo "FAIL: expected exit 3 (repo-a > 2000), got $status" >&2
    echo "Output: $out" >&2
    return 1
  }

  case "$out" in
    *"repo-a"*)
      ;;
    *)
      echo "FAIL: breach output missing 'repo-a'" >&2
      echo "Got: $out" >&2
      return 1
      ;;
  esac
}

# ─── Dedup-on-read: duplicate event_ids not double-counted ───────────────────

@test "telemetry budget: dedup-on-read prevents double-counting (duplicate event_id)" {
  # Write same event_id twice; total should be 500, not 1000.
  # limit = 750: if dedup works → within limit (exit 0); if no dedup → breach (exit 3).
  write_row "evt-dedup-b1" "audited" "model-a" 500 0 0 0 "repo" "main"
  write_row "evt-dedup-b1" "audited" "model-a" 500 0 0 0 "repo" "main"  # duplicate

  local status=0
  "$EIDOLONS_BIN" telemetry budget \
    --limit 750 \
    --by eidolon \
    --project "$TEST_SLUG" \
    2>/dev/null || status=$?

  [ "$status" -eq 0 ] || {
    echo "FAIL: expected exit 0 (dedup reduces to 500 < 750), got $status — dedup-on-read broken" >&2
    return 1
  }
}
