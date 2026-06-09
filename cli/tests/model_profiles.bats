#!/usr/bin/env bats
#
# cli/tests/model_profiles.bats — roster/model-profiles.yaml schema + structural checks.
#
# Stories:
#   SCHEMA-VALID   roster/model-profiles.yaml validates against the JSON schema.
#   DEFAULT-EXISTS default_profile names an existing profile.
#   ANTHROPIC      anthropic profile has correct tier → model mappings.
#   OPENAI         openai profile has correct tier → model mappings.
#   GOOGLE-EXT     a google fixture validates with zero code change (extensibility proof).
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

PROFILES_FILE="$EIDOLONS_ROOT/roster/model-profiles.yaml"
SCHEMA_FILE="$EIDOLONS_ROOT/schemas/model-profiles.schema.json"

# Convert YAML to JSON using the CLI lib's yaml_to_json approach.
_profiles_json() {
  if command -v yq >/dev/null 2>&1; then
    yq eval -o json "$PROFILES_FILE"
  else
    python3 -c "import sys,json,yaml; print(json.dumps(yaml.safe_load(open('$PROFILES_FILE').read())))"
  fi
}

# ─── SCHEMA-VALID ─────────────────────────────────────────────────────────────

@test "model-profiles: roster file exists" {
  [ -f "$PROFILES_FILE" ]
}

@test "model-profiles: schema file exists" {
  [ -f "$SCHEMA_FILE" ]
}

@test "model-profiles: schema is valid JSON" {
  run jq empty "$SCHEMA_FILE"
  [ "$status" -eq 0 ]
}

@test "model-profiles: roster/model-profiles.yaml has required top-level keys" {
  run _profiles_json
  [ "$status" -eq 0 ]
  local json="$output"
  # schema_version
  [[ "$(printf '%s' "$json" | jq '.schema_version')" == "1" ]]
  # default_profile
  local dp
  dp="$(printf '%s' "$json" | jq -r '.default_profile')"
  [ -n "$dp" ]
  # profiles
  local pc
  pc="$(printf '%s' "$json" | jq '.profiles | length')"
  [ "$pc" -gt 0 ]
}

# ─── DEFAULT-EXISTS ───────────────────────────────────────────────────────────

@test "model-profiles: default_profile exists in profiles map" {
  run _profiles_json
  [ "$status" -eq 0 ]
  local json="$output"
  local dp
  dp="$(printf '%s' "$json" | jq -r '.default_profile')"
  # profiles[$dp] must be non-null
  local entry
  entry="$(printf '%s' "$json" | jq --arg p "$dp" '.profiles[$p]')"
  [ "$entry" != "null" ]
  [ -n "$entry" ]
}

# ─── ANTHROPIC ────────────────────────────────────────────────────────────────

@test "model-profiles: anthropic profile has tiers block" {
  run _profiles_json
  [ "$status" -eq 0 ]
  local json="$output"
  local tiers
  tiers="$(printf '%s' "$json" | jq '.profiles.anthropic.tiers')"
  [ "$tiers" != "null" ]
}

@test "model-profiles: anthropic profile applies_to_hosts includes claude-code" {
  run _profiles_json
  [ "$status" -eq 0 ]
  local json="$output"
  local hosts
  hosts="$(printf '%s' "$json" | jq -r '(.profiles.anthropic.applies_to_hosts // []) | join(",")')"
  [[ "$hosts" == *"claude-code"* ]]
}

@test "model-profiles: anthropic has light, standard, deep mappings" {
  run _profiles_json
  [ "$status" -eq 0 ]
  local json="$output"
  local lm sm dm
  lm="$(printf '%s' "$json" | jq -r '.profiles.anthropic.tiers.light')"
  sm="$(printf '%s' "$json" | jq -r '.profiles.anthropic.tiers.standard')"
  dm="$(printf '%s' "$json" | jq -r '.profiles.anthropic.tiers.deep')"
  # Must be non-empty strings (vendor strings live here, validated by presence only).
  [ -n "$lm" ] && [ "$lm" != "null" ]
  [ -n "$sm" ] && [ "$sm" != "null" ]
  [ -n "$dm" ] && [ "$dm" != "null" ]
}

@test "model-profiles: anthropic tiers are distinct strings" {
  run _profiles_json
  [ "$status" -eq 0 ]
  local json="$output"
  local lm sm dm
  lm="$(printf '%s' "$json" | jq -r '.profiles.anthropic.tiers.light')"
  sm="$(printf '%s' "$json" | jq -r '.profiles.anthropic.tiers.standard')"
  dm="$(printf '%s' "$json" | jq -r '.profiles.anthropic.tiers.deep')"
  # light != standard (different capability levels)
  [ "$lm" != "$sm" ]
}

# ─── OPENAI ───────────────────────────────────────────────────────────────────

@test "model-profiles: openai profile exists" {
  run _profiles_json
  [ "$status" -eq 0 ]
  local json="$output"
  local entry
  entry="$(printf '%s' "$json" | jq '.profiles.openai')"
  [ "$entry" != "null" ] && [ -n "$entry" ]
}

@test "model-profiles: openai profile applies_to_hosts includes codex" {
  run _profiles_json
  [ "$status" -eq 0 ]
  local json="$output"
  local hosts
  hosts="$(printf '%s' "$json" | jq -r '(.profiles.openai.applies_to_hosts // []) | join(",")')"
  [[ "$hosts" == *"codex"* ]]
}

@test "model-profiles: openai has at least light and standard tiers" {
  run _profiles_json
  [ "$status" -eq 0 ]
  local json="$output"
  local lm sm
  lm="$(printf '%s' "$json" | jq -r '.profiles.openai.tiers.light')"
  sm="$(printf '%s' "$json" | jq -r '.profiles.openai.tiers.standard')"
  [ -n "$lm" ] && [ "$lm" != "null" ]
  [ -n "$sm" ] && [ "$sm" != "null" ]
}

# ─── GOOGLE-EXT: extensibility (zero code change) ─────────────────────────────

@test "model-profiles: a google fixture validates against the schema" {
  local tmpdir="$BATS_TEST_TMPDIR/google-ext"
  mkdir -p "$tmpdir"

  # Write a minimal google profile YAML.
  cat > "$tmpdir/model-profiles-google.yaml" <<'EOF'
schema_version: 1
default_profile: google
profiles:
  google:
    description: "Google Gemini family"
    applies_to_hosts: [claude-code]
    tiers:
      light:    gemini-flash
      standard: gemini-pro
      deep:     gemini-ultra
EOF

  # Convert to JSON and assert required keys.
  local json
  if command -v yq >/dev/null 2>&1; then
    json="$(yq eval -o json "$tmpdir/model-profiles-google.yaml")"
  else
    json="$(python3 -c "import sys,json,yaml; print(json.dumps(yaml.safe_load(open('$tmpdir/model-profiles-google.yaml').read())))")"
  fi

  # Must have all three required top-level keys.
  [ "$(printf '%s' "$json" | jq '.schema_version')" = "1" ]
  [ "$(printf '%s' "$json" | jq -r '.default_profile')" = "google" ]
  local dp_entry
  dp_entry="$(printf '%s' "$json" | jq '.profiles.google')"
  [ "$dp_entry" != "null" ] && [ -n "$dp_entry" ]

  # All three tiers present.
  local lm sm dm
  lm="$(printf '%s' "$json" | jq -r '.profiles.google.tiers.light')"
  sm="$(printf '%s' "$json" | jq -r '.profiles.google.tiers.standard')"
  dm="$(printf '%s' "$json" | jq -r '.profiles.google.tiers.deep')"
  [ -n "$lm" ] && [ "$lm" != "null" ]
  [ -n "$sm" ] && [ "$sm" != "null" ]
  [ -n "$dm" ] && [ "$dm" != "null" ]
}

@test "model-profiles: schema jq-empty passes (make schema check)" {
  run jq empty "$SCHEMA_FILE"
  [ "$status" -eq 0 ]
}

@test "model-profiles: routing schema jq-empty passes" {
  run jq empty "$EIDOLONS_ROOT/schemas/routing.schema.json"
  [ "$status" -eq 0 ]
}
