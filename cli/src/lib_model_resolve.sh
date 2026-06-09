#!/usr/bin/env bash
# cli/src/lib_model_resolve.sh — vendor-neutral model resolution for Eidolons.
#
# SOURCE this file; do NOT execute it directly.
# Requires lib.sh to have been sourced first.
#
# Public API:
#   model_resolve_init          [PROFILES_FILE] [ROUTING_FILE] [CONSUMER_FILE]
#                               Load/export the three JSON blobs used by all
#                               resolve functions. Call once per script run.
#   model_resolve_for           EIDOLON_ID
#                               Echo "model<TAB>tier<TAB>profile<TAB>source"
#                               for the given Eidolon using full precedence.
#   model_tier_for              EIDOLON_ID
#                               Echo the resolved tier name (light|standard|deep).
#   model_tier_source           EIDOLON_ID
#                               Echo roster-tier | class-default
#   model_profile_lookup        PROFILE TIER
#                               Echo concrete model string; resolve-UP on missing
#                               tier; returns non-zero on hard miss.
#   model_list_ids              Echo all Eidolon ids from ROUTING_JSON, one per line.
#   model_profile_applies_to_host  PROFILE HOST
#                               Return 0 if the profile applies to this host.
#
# Resolution precedence (most-specific wins):
#   1. per-Eidolon model PIN    (eidolons.yaml models.members.<id>.model)
#   2. per-tier CALIBRATION     (eidolons.yaml models.calibration.<tier>)
#   3+6. active PROFILE         (eidolons.yaml models.profile | default_profile)
#   4. per-Eidolon roster TIER  (routing.yaml eidolons.<id>.suggested_tier)
#   5. class suggested TIER     (routing.yaml classes.default.suggested_tier)
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# All tier lookups are jq flat-key lookups; no in-shell map structures.
# ═══════════════════════════════════════════════════════════════════════════

# Guard against double-source.
if [ -n "${_LIB_MODEL_RESOLVE_LOADED:-}" ]; then
  return 0
fi
_LIB_MODEL_RESOLVE_LOADED=1

# ─── Init ─────────────────────────────────────────────────────────────────────

# model_resolve_init [PROFILES_FILE] [ROUTING_FILE] [CONSUMER_FILE]
# Loads the three data blobs into exported shell variables. Callers may
# pre-set PROFILES_JSON / ROUTING_JSON / CONSUMER_JSON to skip file reads
# (useful in test fixtures). If a consumer file is absent/empty, CONSUMER_JSON
# defaults to '{}' (no models block — all defaults apply).
model_resolve_init() {
  local profiles_file="${1:-}"
  local routing_file="${2:-}"
  local consumer_file="${3:-}"

  # Profiles
  if [ -z "${PROFILES_JSON:-}" ]; then
    if [ -z "$profiles_file" ]; then
      # Derive path from ROSTER_FILE (set by lib.sh).
      profiles_file="$(dirname "${ROSTER_FILE:-roster/index.yaml}")/model-profiles.yaml"
    fi
    if [ -f "$profiles_file" ]; then
      PROFILES_JSON="$(yaml_to_json "$profiles_file")"
    else
      PROFILES_JSON='{}'
    fi
  fi
  export PROFILES_JSON

  # Routing
  if [ -z "${ROUTING_JSON:-}" ]; then
    if [ -z "$routing_file" ]; then
      routing_file="$(dirname "${ROSTER_FILE:-roster/index.yaml}")/routing.yaml"
    fi
    if [ -f "$routing_file" ]; then
      ROUTING_JSON="$(yaml_to_json "$routing_file")"
    else
      ROUTING_JSON='{}'
    fi
  fi
  export ROUTING_JSON

  # Consumer (eidolons.yaml — may be absent)
  if [ -z "${CONSUMER_JSON:-}" ]; then
    if [ -z "$consumer_file" ]; then
      consumer_file="${PROJECT_MANIFEST:-eidolons.yaml}"
    fi
    if [ -f "$consumer_file" ]; then
      CONSUMER_JSON="$(yaml_to_json "$consumer_file" 2>/dev/null || echo '{}')"
    else
      CONSUMER_JSON='{}'
    fi
  fi
  export CONSUMER_JSON
}

# ─── Tier helpers ─────────────────────────────────────────────────────────────

# model_tier_for EIDOLON_ID
# Resolves the tier for an Eidolon using the precedence:
#   consumer member override → roster per-id suggested_tier → class default.
model_tier_for() {
  local _id="$1"
  local _t

  # Consumer per-member tier override
  _t=$(printf '%s' "$CONSUMER_JSON" \
       | jq -r --arg id "$_id" '.models.members[$id].tier // empty' 2>/dev/null || true)
  if [ -n "$_t" ]; then
    printf '%s\n' "$_t"
    return 0
  fi

  # Roster per-id suggested_tier
  _t=$(printf '%s' "$ROUTING_JSON" \
       | jq -r --arg id "$_id" '.eidolons[$id].suggested_tier // empty' 2>/dev/null || true)
  if [ -n "$_t" ]; then
    printf '%s\n' "$_t"
    return 0
  fi

  # Class default
  printf '%s' "$ROUTING_JSON" \
    | jq -r '.classes.default.suggested_tier // "standard"' 2>/dev/null || printf 'standard\n'
}

# model_tier_source EIDOLON_ID
# Returns 'roster-tier' when routing.yaml had a per-id value, else 'class-default'.
# Does NOT check consumer override (that affects source only in model_resolve_for).
model_tier_source() {
  local _id="$1"
  local _t

  _t=$(printf '%s' "$ROUTING_JSON" \
       | jq -r --arg id "$_id" '.eidolons[$id].suggested_tier // empty' 2>/dev/null || true)
  if [ -n "$_t" ]; then
    printf 'roster-tier\n'
  else
    printf 'class-default\n'
  fi
}

# ─── Profile lookup ───────────────────────────────────────────────────────────

# model_profile_lookup PROFILE TIER
# Echo the concrete model string; resolve-UP (light→standard→deep) on missing
# tier. Returns non-zero on hard miss (deep absent for this profile).
# Bash 3.2 safe: pure jq + case, no associative arrays.
model_profile_lookup() {
  local _p="$1"
  local _t="$2"
  local _m

  _m=$(printf '%s' "$PROFILES_JSON" \
       | jq -r --arg p "$_p" --arg t "$_t" '.profiles[$p].tiers[$t] // empty' 2>/dev/null || true)
  if [ -n "$_m" ]; then
    printf '%s\n' "$_m"
    return 0
  fi

  # Resolve-UP: light→standard→deep (over-provision; FORGE-approved).
  case "$_t" in
    light)
      model_profile_lookup "$_p" standard
      return $?
      ;;
    standard)
      model_profile_lookup "$_p" deep
      return $?
      ;;
    deep)
      return 1   # Hard miss — nothing above deep.
      ;;
  esac
}

# ─── Per-Eidolon full resolution ─────────────────────────────────────────────

# model_resolve_for EIDOLON_ID
# Echoes "model<TAB>tier<TAB>profile<TAB>source" for the given Eidolon.
# All four fields are non-empty on success; returns non-zero on hard miss.
model_resolve_for() {
  local _id="$1"
  local _profile _pin _tier _src_tier _cal _m

  # Active profile (consumer → roster default).
  _profile=$(printf '%s' "$CONSUMER_JSON" \
             | jq -r '.models.profile // empty' 2>/dev/null || true)
  if [ -z "$_profile" ]; then
    _profile=$(printf '%s' "$PROFILES_JSON" \
               | jq -r '.default_profile // "anthropic"' 2>/dev/null || true)
  fi

  # 1. PIN — consumer per-member concrete model.
  _pin=$(printf '%s' "$CONSUMER_JSON" \
         | jq -r --arg id "$_id" '.models.members[$id].model // empty' 2>/dev/null || true)
  if [ -n "$_pin" ]; then
    _tier=$(model_tier_for "$_id")
    printf '%s\t%s\t%s\t%s\n' "$_pin" "$_tier" "$_profile" "pin"
    return 0
  fi

  # Resolve the tier and its source.
  _tier=$(model_tier_for "$_id")
  _src_tier=$(model_tier_source "$_id")
  # When the consumer had a per-member tier override, source is 'roster-tier'
  # by convention (it's a user-directed tier, not a class default).
  _consumer_tier=$(printf '%s' "$CONSUMER_JSON" \
    | jq -r --arg id "$_id" '.models.members[$id].tier // empty' 2>/dev/null || true)
  if [ -n "$_consumer_tier" ]; then
    _src_tier="roster-tier"
  fi

  # 2. CALIBRATION — per-tier override within the active profile.
  _cal=$(printf '%s' "$CONSUMER_JSON" \
         | jq -r --arg t "$_tier" '.models.calibration[$t] // empty' 2>/dev/null || true)
  if [ -n "$_cal" ]; then
    printf '%s\t%s\t%s\t%s\n' "$_cal" "$_tier" "$_profile" "calibration"
    return 0
  fi

  # 3. PROFILE base mapping (with resolve-UP).
  if _m=$(model_profile_lookup "$_profile" "$_tier"); then
    printf '%s\t%s\t%s\t%s\n' "$_m" "$_tier" "$_profile" "$_src_tier"
    return 0
  fi

  # Hard miss — profile doesn't cover this tier even after resolve-UP.
  warn "model_resolve_for: no model found for '$_id' (profile=$_profile tier=$_tier)"
  return 1
}

# ─── Utility ──────────────────────────────────────────────────────────────────

# model_list_ids — echo all Eidolon ids from ROUTING_JSON, one per line.
model_list_ids() {
  printf '%s' "$ROUTING_JSON" \
    | jq -r '(.eidolons // {}) | keys[]' 2>/dev/null || true
}

# model_profile_applies_to_host PROFILE HOST
# Return 0 if applies_to_hosts for this profile includes HOST; else 1.
model_profile_applies_to_host() {
  local _p="$1"
  local _h="$2"
  local _res

  _res=$(printf '%s' "$PROFILES_JSON" \
         | jq -r --arg p "$_p" --arg h "$_h" \
           '(.profiles[$p].applies_to_hosts // []) | any(. == $h) | if . then "yes" else "no" end' \
           2>/dev/null || echo "no")
  [ "$_res" = "yes" ]
}

# model_active_profile — echo the active profile name, honoring consumer override.
model_active_profile() {
  local _p
  _p=$(printf '%s' "$CONSUMER_JSON" \
       | jq -r '.models.profile // empty' 2>/dev/null || true)
  if [ -z "$_p" ]; then
    _p=$(printf '%s' "$PROFILES_JSON" \
         | jq -r '.default_profile // "anthropic"' 2>/dev/null || true)
  fi
  printf '%s\n' "${_p:-anthropic}"
}

# model_has_block — return 0 when eidolons.yaml has a non-trivial models block.
model_has_block() {
  local _has
  _has=$(printf '%s' "$CONSUMER_JSON" \
         | jq 'has("models") and (.models != null) and (.models != {})' 2>/dev/null || echo "false")
  [ "$_has" = "true" ]
}
