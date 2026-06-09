#!/usr/bin/env bats
#
# cli/tests/model_resolve.bats — model resolution algorithm tests.
#
# Stories:
#   DEFAULTS   default install resolves FORGE defaults per Eidolon.
#   PRECEDENCE pin > calibration > profile-base.
#   RESOLVE-UP missing tier resolves UP (light→standard→deep).
#   CLASS-DEF  unknown/absent Eidolon falls back to class default (standard).
#   HOST-INAPPLICABLE profile with wrong applies_to_hosts: resolve OK, wiring skip.
#
# Tests source lib_model_resolve.sh directly; no exec delegation needed.
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

RESOLVE_LIB="$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh"
PROFILES_FILE="$EIDOLONS_ROOT/roster/model-profiles.yaml"
ROUTING_FILE="$EIDOLONS_ROOT/roster/routing.yaml"

_json_from_yaml() {
  local file="$1"
  if command -v yq >/dev/null 2>&1; then
    yq eval -o json "$file"
  else
    python3 -c "import sys,json,yaml; print(json.dumps(yaml.safe_load(open('$file').read())))"
  fi
}

_init_resolve() {
  # Source lib.sh first (provides yaml_to_json etc).
  # shellcheck source=/dev/null
  . "$EIDOLONS_ROOT/cli/src/lib.sh"
  # shellcheck source=/dev/null
  . "$RESOLVE_LIB"
  export PROFILES_JSON="$(_json_from_yaml "$PROFILES_FILE")"
  export ROUTING_JSON="$(_json_from_yaml "$ROUTING_FILE")"
  export CONSUMER_JSON='{}'
}

# ─── DEFAULTS ─────────────────────────────────────────────────────────────────

@test "resolve: spectra resolves to deep tier (FORGE default)" {
  _init_resolve
  local tier
  tier="$(model_tier_for spectra)"
  [ "$tier" = "deep" ]
}

@test "resolve: forge resolves to deep tier" {
  _init_resolve
  local tier
  tier="$(model_tier_for forge)"
  [ "$tier" = "deep" ]
}

@test "resolve: vigil resolves to deep tier" {
  _init_resolve
  local tier
  tier="$(model_tier_for vigil)"
  [ "$tier" = "deep" ]
}

@test "resolve: atlas resolves to standard tier" {
  _init_resolve
  local tier
  tier="$(model_tier_for atlas)"
  [ "$tier" = "standard" ]
}

@test "resolve: apivr resolves to standard tier" {
  _init_resolve
  local tier
  tier="$(model_tier_for apivr)"
  [ "$tier" = "standard" ]
}

@test "resolve: idg resolves to light tier" {
  _init_resolve
  local tier
  tier="$(model_tier_for idg)"
  [ "$tier" = "light" ]
}

@test "resolve: kupo resolves to light tier" {
  _init_resolve
  local tier
  tier="$(model_tier_for kupo)"
  [ "$tier" = "light" ]
}

@test "resolve: spectra default anthropic profile resolves model" {
  _init_resolve
  local line em
  line="$(model_resolve_for spectra)"
  em="$(printf '%s' "$line" | cut -f1)"
  # Should be non-empty (vendor string from anthropic profile deep tier).
  [ -n "$em" ]
}

@test "resolve: atlas default anthropic profile resolves model" {
  _init_resolve
  local line em
  line="$(model_resolve_for atlas)"
  em="$(printf '%s' "$line" | cut -f1)"
  [ -n "$em" ]
}

@test "resolve: idg default anthropic profile resolves model" {
  _init_resolve
  local line em
  line="$(model_resolve_for idg)"
  em="$(printf '%s' "$line" | cut -f1)"
  [ -n "$em" ]
}

@test "resolve: source is roster-tier for spectra (has per-id entry)" {
  _init_resolve
  local line src
  line="$(model_resolve_for spectra)"
  src="$(printf '%s' "$line" | cut -f4)"
  [ "$src" = "roster-tier" ]
}

# ─── PRECEDENCE ───────────────────────────────────────────────────────────────

@test "resolve: per-member PIN wins over profile (source=pin)" {
  _init_resolve
  CONSUMER_JSON='{"models":{"members":{"spectra":{"model":"my-custom-model"}}}}'
  export CONSUMER_JSON
  local line em src
  line="$(model_resolve_for spectra)"
  em="$(printf '%s' "$line" | cut -f1)"
  src="$(printf '%s' "$line" | cut -f4)"
  [ "$em" = "my-custom-model" ]
  [ "$src" = "pin" ]
}

@test "resolve: calibration wins over profile base (source=calibration)" {
  _init_resolve
  # Set calibration for deep tier.
  CONSUMER_JSON='{"models":{"calibration":{"deep":"calibrated-deep-model"}}}'
  export CONSUMER_JSON
  # spectra is deep → should use calibration.
  local line em src
  line="$(model_resolve_for spectra)"
  em="$(printf '%s' "$line" | cut -f1)"
  src="$(printf '%s' "$line" | cut -f4)"
  [ "$em" = "calibrated-deep-model" ]
  [ "$src" = "calibration" ]
}

@test "resolve: PIN wins over calibration" {
  _init_resolve
  CONSUMER_JSON='{"models":{"calibration":{"deep":"calibrated-model"},"members":{"spectra":{"model":"pinned-model"}}}}'
  export CONSUMER_JSON
  local line em src
  line="$(model_resolve_for spectra)"
  em="$(printf '%s' "$line" | cut -f1)"
  src="$(printf '%s' "$line" | cut -f4)"
  [ "$em" = "pinned-model" ]
  [ "$src" = "pin" ]
}

@test "resolve: consumer per-member tier override changes resolved tier" {
  _init_resolve
  # Force spectra (normally deep) down to standard.
  CONSUMER_JSON='{"models":{"members":{"spectra":{"tier":"standard"}}}}'
  export CONSUMER_JSON
  local tier
  tier="$(model_tier_for spectra)"
  [ "$tier" = "standard" ]
}

@test "resolve: consumer profile selection propagates to resolved profile" {
  _init_resolve
  CONSUMER_JSON='{"models":{"profile":"openai"}}'
  export CONSUMER_JSON
  local line profile
  line="$(model_resolve_for spectra)"
  profile="$(printf '%s' "$line" | cut -f3)"
  [ "$profile" = "openai" ]
}

# ─── RESOLVE-UP ───────────────────────────────────────────────────────────────

@test "resolve: light tier resolves UP when only standard+deep present in profile" {
  _init_resolve
  # Build a custom profile with no light tier.
  PROFILES_JSON='{"schema_version":1,"default_profile":"nolite","profiles":{"nolite":{"tiers":{"standard":"std-model","deep":"deep-model"}}}}'
  export PROFILES_JSON
  local model
  model="$(model_profile_lookup nolite light)"
  # Should resolve UP to standard.
  [ "$model" = "std-model" ]
}

@test "resolve: deep-only profile: all tiers resolve to deep model" {
  _init_resolve
  PROFILES_JSON='{"schema_version":1,"default_profile":"deeponly","profiles":{"deeponly":{"tiers":{"deep":"the-deep-model"}}}}'
  export PROFILES_JSON
  local lm sm dm
  lm="$(model_profile_lookup deeponly light)"
  sm="$(model_profile_lookup deeponly standard)"
  dm="$(model_profile_lookup deeponly deep)"
  [ "$lm" = "the-deep-model" ]
  [ "$sm" = "the-deep-model" ]
  [ "$dm" = "the-deep-model" ]
}

@test "resolve: missing deep tier returns non-zero (hard miss)" {
  _init_resolve
  PROFILES_JSON='{"schema_version":1,"default_profile":"incomplete","profiles":{"incomplete":{"tiers":{}}}}'
  export PROFILES_JSON
  run model_profile_lookup incomplete deep
  [ "$status" -ne 0 ]
}

# ─── CLASS-DEFAULT ────────────────────────────────────────────────────────────

@test "resolve: unknown Eidolon falls back to class default (standard)" {
  _init_resolve
  local tier
  tier="$(model_tier_for nonexistent-eidolon-xyz)"
  [ "$tier" = "standard" ]
}

@test "resolve: class default source is class-default" {
  _init_resolve
  local src
  src="$(model_tier_source nonexistent-eidolon-xyz)"
  [ "$src" = "class-default" ]
}

# ─── HOST-INAPPLICABLE ────────────────────────────────────────────────────────

@test "resolve: profile lookup succeeds for inapplicable host (resolution still works)" {
  _init_resolve
  # anthropic applies_to_hosts=[claude-code]; codex is not in the list.
  # But resolution itself (model string) should still return a value.
  local line em
  line="$(model_resolve_for atlas)"
  em="$(printf '%s' "$line" | cut -f1)"
  [ -n "$em" ]
}

@test "resolve: model_profile_applies_to_host returns false for wrong host" {
  _init_resolve
  # anthropic applies_to_hosts should NOT include codex.
  run model_profile_applies_to_host anthropic codex
  [ "$status" -ne 0 ]
}

@test "resolve: model_profile_applies_to_host returns true for correct host" {
  _init_resolve
  # anthropic applies_to_hosts should include claude-code.
  run model_profile_applies_to_host anthropic claude-code
  [ "$status" -eq 0 ]
}

@test "resolve: openai applies to codex" {
  _init_resolve
  run model_profile_applies_to_host openai codex
  [ "$status" -eq 0 ]
}

@test "resolve: openai does not apply to claude-code" {
  _init_resolve
  run model_profile_applies_to_host openai claude-code
  [ "$status" -ne 0 ]
}
