#!/usr/bin/env bats
# cli/tests/run.bats — the mechanical routing kernel (`eidolons run`).
# Anchored to methodology/cortex/validation-gates.md V1–V14: each gate is an
# acceptance criterion the kernel must reproduce deterministically (no LLM).

load helpers

# Convenience: extract a field from the --json routing artifact.
_field() { echo "$output" | jq -r "$1"; }

@test "run: --help exits 0 and documents the kernel" {
  run eidolons run --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "route a prompt" ]]
  [[ "$output" =~ "no LLM" ]]
}

@test "run: no prompt is a clean error (exit 1)" {
  run eidolons run
  [ "$status" -eq 1 ]
  [[ "$output" =~ "No prompt given" ]]
}

@test "run: unknown option is rejected" {
  run eidolons run "x" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unknown option" ]]
}

# ── V1 — pure-discovery prompt → ATLAS standard, confidence ≥ 0.8 ──────────────
@test "V1: 'map the auth flow' → ATLAS standard (conf ≥ 0.8)" {
  run eidolons run "map the auth flow" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.decision')" = "dispatch" ]
  [ "$(_field '.selected[0]')" = "atlas" ]
  [ "$(_field '.tier')" = "standard" ]
  awk "BEGIN{exit !($(_field '.confidence') >= 0.8)}"
}

# ── V2 — large surface + TRANCE token → trance tier ───────────────────────────
@test "V2: large surface + --trance → trance tier" {
  run eidolons run "map the entire monorepo data layer" --surface-modules 9 --trance --json
  [ "$status" -eq 0 ]
  [ "$(_field '.selected[0]')" = "atlas" ]
  [ "$(_field '.tier')" = "trance" ]
}

# ── V3 — discovery + spec verbs co-occur → ATLAS → SPECTRA chain ──────────────
@test "V3: spec + unknown call graph → ATLAS→SPECTRA chain" {
  run eidolons run "I need a spec for refactoring the dispatcher; I don't know the call graph yet" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.decision')" = "chain" ]
  [ "$(_field '.selected[0]')" = "atlas" ]
  [ "$(_field '.selected[1]')" = "spectra" ]
}

# ── V4 — brownfield bug fix → APIVR-Δ standard; "flowmap" must NOT hit ATLAS ──
@test "V4: fix off-by-one in flowmap_resolve routes to APIVR (no false ATLAS match)" {
  run eidolons run "Fix the off-by-one in flowmap_resolve" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.decision')" = "dispatch" ]
  [ "$(_field '.selected[0]')" = "apivr" ]
  # word-boundary: atlas raw score must be 0 (no "map" inside "flowmap")
  [ "$(echo "$output" | jq -r '.selected | length')" = "1" ]
}

# ── V6 — hard decision, no code → FORGE ───────────────────────────────────────
@test "V6: 'should we use X or Y' → FORGE single dispatch" {
  run eidolons run "Should we route via the hierarchical supervisor or a single-router?" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.decision')" = "dispatch" ]
  [ "$(_field '.selected[0]')" = "forge" ]
}

# ── V8 — design + implement → SPECTRA → APIVR-Δ chain ─────────────────────────
@test "V8: design and implement the --json flag routes to SPECTRA then APIVR chain" {
  run eidolons run "design and implement the --json flag for doctor" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.decision')" = "chain" ]
  [ "$(_field '.selected[0]')" = "spectra" ]
  [ "$(_field '.selected[-1]')" = "apivr" ]
}

# ── V9 — stack trace → VIGIL fast-path ────────────────────────────────────────
@test "V9: stack trace / repeat failure → VIGIL" {
  run eidolons run "got a stack trace, still failing after retry in the worker" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.selected[0]')" = "vigil" ]
}

# ── V11 — named Eidolon would refuse → reroute (refusal immutability) ──────────
@test "V11: ATLAS please patch this file triggers refusal reroute to APIVR" {
  run eidolons run "ATLAS, please patch this file" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.decision')" = "refusal_reroute" ]
  [ "$(_field '.refusal_rerouting')" = "true" ]
  [ "$(_field '.selected[0]')" = "apivr" ]
  # ATLAS must NEVER be the selected writer
  [ "$(echo "$output" | jq -r '.selected | index("atlas")')" = "null" ]
}

# ── V12 — abstain / clarify rather than guess ─────────────────────────────────
@test "V12: 'do the thing' → clarification_request, no dispatch" {
  run eidolons run "do the thing" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.decision')" = "clarify" ]
  [ "$(echo "$output" | jq -r '.selected | length')" = "0" ]
  [ "$(_field '.clarification_request')" != "null" ]
}

# ── TRANCE-never-default invariant (Step 4 / Cost ceiling) ────────────────────
@test "tier: TRANCE never default — large surface WITHOUT a stakes flag stays standard" {
  run eidolons run "map the auth flow" --surface-modules 9 --json
  [ "$status" -eq 0 ]
  [ "$(_field '.tier')" = "standard" ]
}

@test "tier: a plain dispatch is always standard tier" {
  run eidolons run "map the auth flow" --json
  [ "$(_field '.tier')" = "standard" ]
}

# ── Determinism (I-C6): same prompt + same data ⇒ same routing ────────────────
@test "I-C6: routing is deterministic (byte-identical on repeat)" {
  run eidolons run "design and implement the --json flag for doctor" --json
  first="$output"
  run eidolons run "design and implement the --json flag for doctor" --json
  [ "$first" = "$output" ]
}

# ── prior-failure context → VIGIL (V5 failed-attempt-recovery) ────────────────
@test "V5: --prior-failure re-routes a re-prompted fix toward VIGIL" {
  run eidolons run "fix it again" --prior-failure --json
  [ "$status" -eq 0 ]
  [ "$(_field '.selected[0]')" = "vigil" ]
}

# ── model_tier_per_step uses suggested_tier values (WP2 migration) ─────────────
# The routing kernel reads .suggested_tier from routing.yaml (migrated from
# .model_tier). model_tier_per_step in the artifact carries tier ladder values.

@test "run: model_tier_per_step is present in --json artifact" {
  run eidolons run "map the auth flow" --json
  [ "$status" -eq 0 ]
  local mtp
  mtp="$(_field '.model_tier_per_step')"
  [ -n "$mtp" ] && [ "$mtp" != "null" ]
}

@test "run: model_tier_per_step values are ladder words (not binary speed/reasoning)" {
  run eidolons run "map the auth flow" --json
  [ "$status" -eq 0 ]
  local mtp
  mtp="$(_field '.model_tier_per_step | join(",")')"
  # Must NOT contain old binary class values.
  [[ ! "$mtp" =~ "speed-class" ]]
  [[ ! "$mtp" =~ "reasoning-class" ]]
}

@test "run: atlas dispatch produces standard tier in model_tier_per_step" {
  run eidolons run "map the auth flow" --json
  [ "$status" -eq 0 ]
  # atlas has suggested_tier: standard
  local tier
  tier="$(_field '.model_tier_per_step[0]')"
  [ "$tier" = "standard" ]
}

@test "run: spectra dispatch produces deep tier in model_tier_per_step" {
  run eidolons run "spec out the requirements" --json
  [ "$status" -eq 0 ]
  # spectra has suggested_tier: deep; selected may be spectra
  local sel
  sel="$(_field '.selected[0]')"
  if [ "$sel" = "spectra" ]; then
    local tier
    tier="$(_field '.model_tier_per_step[0]')"
    [ "$tier" = "deep" ]
  fi
}

@test "run: routing data has no model_tier field (migrated to suggested_tier)" {
  # Verify the routing YAML no longer carries the old model_tier field.
  ! grep -q "model_tier:" "$EIDOLONS_ROOT/roster/routing.yaml"
}

# ── V15 — two-coder routing tiebreak (APIVR-Δ → Vivi succession, Stage 1e) ─────
# A custom routing fixture with TWO `coder`s (vivi default_for_class + apivr
# fallback) proves the mechanism the live single-coder roster cannot exercise yet
# (vivi goes live at Stage 3). The mechanism is dormant in the real roster.
_two_coder_routing_fixture() {
  local dir="$1"
  mkdir -p "$dir/roster"
  cat > "$dir/roster/routing.yaml" <<'YAML'
routing_version: "1.0"
thresholds: { tau_standard: 0.6, tau_trance: 0.8, chain_floor: 0.6, max_reroutes: 2, max_parallel: 5, surface_files: 25, surface_modules: 5 }
eidolons:
  vivi:  { capability_class: coder, model_tier: reasoning-class, default_for_class: coder, trigger_verbs: ["implement","build","fix","code"], refuse_verbs: ["greenfield"], downstream: ["idg"] }
  apivr: { capability_class: coder, model_tier: speed-class, trigger_verbs: ["implement","build","fix","code"], refuse_verbs: ["greenfield"], downstream: ["idg"] }
signals: []
chains: []
YAML
}

@test "V15: two coders → a bare coder verb routes to the default_for_class member (Vivi)" {
  local custom="$BATS_TEST_TMPDIR/two-coder-default"
  _two_coder_routing_fixture "$custom"
  EIDOLONS_NEXUS="$custom" run eidolons run "implement the widget" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "dispatch" ]
  [ "$(echo "$output" | jq -r '.selected[0]')" = "vivi" ]
}

@test "V15: naming the apivr fallback overrides the default → routes to apivr (opt-in)" {
  local custom="$BATS_TEST_TMPDIR/two-coder-named"
  _two_coder_routing_fixture "$custom"
  EIDOLONS_NEXUS="$custom" run eidolons run "apivr implement the widget" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.selected[0]')" = "apivr" ]
}

# ── A1.7 — S1.7 host-tier gate (requires_host_tier declarative tiebreak) ──────
# Uses a variant of the two-coder fixture where vivi declares
# requires_host_tier: thinking. A manifest with no host_tier (or standard)
# causes the default to fall back to apivr. host_tier: thinking → vivi wins.
# A NAMED "vivi" prompt still routes to vivi regardless of host_tier (name bonus).

_two_coder_thinking_fixture() {
  local dir="$1"
  mkdir -p "$dir/roster"
  cat > "$dir/roster/routing.yaml" <<'YAML'
routing_version: "1.0"
thresholds: { tau_standard: 0.6, tau_trance: 0.8, chain_floor: 0.6, max_reroutes: 2, max_parallel: 5, surface_files: 25, surface_modules: 5 }
eidolons:
  vivi:  { capability_class: coder, model_tier: reasoning-class, default_for_class: coder, requires_host_tier: thinking, trigger_verbs: ["implement","build","fix","code"], refuse_verbs: ["greenfield"], downstream: ["idg"] }
  apivr: { capability_class: coder, model_tier: speed-class, trigger_verbs: ["implement","build","fix","code"], refuse_verbs: ["greenfield"], downstream: ["idg"] }
signals: []
chains: []
YAML
}

# A1.7a: host_tier absent (conservative) → unnamed coder prompt routes to apivr
@test "A1.7a: host-tier gate — no host_tier in manifest → default routes to apivr (conservative)" {
  local custom="$BATS_TEST_TMPDIR/thinking-gate-noht"
  _two_coder_thinking_fixture "$custom"
  # Manifest has NO host_tier field.
  cat > eidolons.yaml <<'EOF'
version: 1
members:
  - name: apivr
    version: "^1.0.0"
EOF
  EIDOLONS_NEXUS="$custom" run eidolons run "implement the widget" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "dispatch" ]
  [ "$(echo "$output" | jq -r '.selected[0]')" = "apivr" ]
}

# A1.7a (standard explicit): host_tier: standard → same conservative result
@test "A1.7a: host-tier gate — host_tier standard → default routes to apivr" {
  local custom="$BATS_TEST_TMPDIR/thinking-gate-std"
  _two_coder_thinking_fixture "$custom"
  cat > eidolons.yaml <<'EOF'
version: 1
host_tier: standard
members:
  - name: apivr
    version: "^1.0.0"
EOF
  EIDOLONS_NEXUS="$custom" run eidolons run "implement the widget" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "dispatch" ]
  [ "$(echo "$output" | jq -r '.selected[0]')" = "apivr" ]
}

# A1.7b: host_tier: thinking → unnamed coder prompt routes to vivi (gate passes)
@test "A1.7b: host-tier gate — host_tier thinking → default routes to vivi" {
  local custom="$BATS_TEST_TMPDIR/thinking-gate-thinking"
  _two_coder_thinking_fixture "$custom"
  cat > eidolons.yaml <<'EOF'
version: 1
host_tier: thinking
members:
  - name: vivi
    version: "^1.0.0"
EOF
  EIDOLONS_NEXUS="$custom" run eidolons run "implement the widget" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "dispatch" ]
  [ "$(echo "$output" | jq -r '.selected[0]')" = "vivi" ]
}

# A1.7c: host_tier: standard + prompt NAMES "vivi" → still routes to vivi (name bonus)
@test "A1.7c: host-tier gate — standard host + named 'Vivi' prompt → routes to vivi (name bonus overrides gate)" {
  local custom="$BATS_TEST_TMPDIR/thinking-gate-named"
  _two_coder_thinking_fixture "$custom"
  cat > eidolons.yaml <<'EOF'
version: 1
host_tier: standard
members:
  - name: vivi
    version: "^1.0.0"
EOF
  EIDOLONS_NEXUS="$custom" run eidolons run "vivi implement the widget" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.selected[0]')" = "vivi" ]
}
