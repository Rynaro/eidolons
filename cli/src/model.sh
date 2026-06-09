#!/usr/bin/env bash
# cli/src/model.sh — 'eidolons model' sub-dispatcher.
#
# Routes: list | show | use | reset | profile | (bare/--help → picker/usage).
# Sourced libs: lib.sh, lib_model_resolve.sh, lib_model_wiring.sh, ui/prompt.sh.
#
# Exit codes:
#   0  OK
#   2  bad args / unknown Eidolon or profile
#   3  resolve hard-miss
#   4  frontmatter write failed
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# All log/prompt output to stderr. Only --json machine output to stdout.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_model_resolve.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_model_wiring.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/ui/prompt.sh"

# ─── Non-interactive flag parsing ─────────────────────────────────────────────
NON_INTERACTIVE=false
DRY_RUN=false
OUT=text
for _arg in "$@"; do
  case "$_arg" in
    --non-interactive) NON_INTERACTIVE=true ;;
    --dry-run)         DRY_RUN=true ;;
    --json)            OUT=json ;;
  esac
done
export NON_INTERACTIVE DRY_RUN OUT

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
eidolons model — vendor-neutral model management

Usage: eidolons model [<subcommand>] [options]

Subcommands:
  (bare)                         Interactive guided picker (TTY) / usage (non-interactive)
  list                           List profiles (mark active) + tier ladder + vendor mappings
  show [<eidolon>]               Show resolved model(s): eidolon | tier | profile | source | effective
  use <eidolon>@<tier|model>     Set per-member tier override or concrete model pin
  profile <name>                 Set the active profile; re-resolve all; rewrite frontmatter
  reset [<eidolon>]              Clear member override/pin (all members if no arg)

Options:
  --non-interactive   Never prompt; bare 'model' prints usage and exits 0
  --json              (show/list) machine-readable JSON output
  --dry-run           (use/profile/reset) resolve + print diff; do NOT write lock/frontmatter
  -h, --help          Show this help

Model tiers: light < standard < deep  (vendor-neutral)
Active profile maps tiers to concrete model strings.
Profile + calibration live in eidolons.yaml (models: block).
Vendor strings live ONLY in roster/model-profiles.yaml.

Examples:
  eidolons model list
  eidolons model show
  eidolons model show spectra
  eidolons model use spectra@deep
  eidolons model use apivr@sonnet        # concrete model pin
  eidolons model profile openai
  eidolons model reset spectra
  eidolons model reset                   # clear all overrides
EOF
}

# ─── Init resolve state ───────────────────────────────────────────────────────
model_resolve_init 2>/dev/null || true

# ─── Helpers ──────────────────────────────────────────────────────────────────

TIERS="light standard deep"

_is_tier() {
  local _v="$1"
  case "$_v" in
    light|standard|deep) return 0 ;;
    *) return 1 ;;
  esac
}

_assert_eidolon_known() {
  local _id="$1"
  local _known
  _known="$(model_list_ids 2>/dev/null | tr '\n' '|' || true)"
  case "|${_known}|" in
    *"|${_id}|"*) return 0 ;;
    *) die "Unknown Eidolon: '${_id}'. Known: $(model_list_ids 2>/dev/null | tr '\n' ' ' || true)" ;;
  esac
}

_assert_profile_known() {
  local _pname="$1"
  local _known
  _known="$(printf '%s' "$PROFILES_JSON" | jq -r '.profiles | keys[]' 2>/dev/null | tr '\n' '|' || true)"
  case "|${_known}|" in
    *"|${_pname}|"*) return 0 ;;
    *) die "Unknown profile: '${_pname}'. Known: $(printf '%s' "$PROFILES_JSON" | jq -r '.profiles | keys[]' 2>/dev/null | tr '\n' ' ' || true)" ;;
  esac
}

# _set_manifest_models_field PATH VALUE
# Set a dotted path in eidolons.yaml's models block using yq or python3.
# PATH examples: .models.profile  /  .models.members.spectra.tier
_set_manifest_models_field() {
  local path="$1"
  local value="$2"
  local manifest="${PROJECT_MANIFEST:-eidolons.yaml}"

  if [ ! -f "$manifest" ]; then
    die "No eidolons.yaml in current directory. Run 'eidolons init' first."
  fi

  local tmpf
  tmpf="$(mktemp)"

  if command -v yq >/dev/null 2>&1; then
    yq eval "${path} = \"${value}\"" "$manifest" > "$tmpf" && mv "$tmpf" "$manifest" && return 0
  fi

  # Python3 fallback (best-effort; yq is the canonical path).
  python3 - "$manifest" "$path" "$value" <<'PY' && return 0 || true
import sys, re
from pathlib import Path

manifest_path, dotpath, value = sys.argv[1], sys.argv[2], sys.argv[3]
# Simple path like .models.members.spectra.tier → split on dots, skip leading dot.
keys = [k for k in dotpath.split('.') if k]
text = Path(manifest_path).read_text()
# Rebuild: reload as YAML, mutate, dump.
try:
    import yaml
    data = yaml.safe_load(text) or {}
    obj = data
    for k in keys[:-1]:
        if k not in obj or not isinstance(obj[k], dict):
            obj[k] = {}
        obj = obj[k]
    obj[keys[-1]] = value
    Path(manifest_path).write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True))
    sys.exit(0)
except Exception as e:
    print(f"Warning: YAML edit failed: {e}", file=sys.stderr)
    sys.exit(1)
PY

  rm -f "$tmpf"
  die "Could not set ${path} in ${manifest} — install yq or python3-yaml"
}

# _delete_manifest_models_field PATH
_delete_manifest_models_field() {
  local path="$1"
  local manifest="${PROJECT_MANIFEST:-eidolons.yaml}"

  if [ ! -f "$manifest" ]; then
    return 0
  fi

  local tmpf
  tmpf="$(mktemp)"

  if command -v yq >/dev/null 2>&1; then
    yq eval "del(${path})" "$manifest" > "$tmpf" && mv "$tmpf" "$manifest" && return 0
  fi

  # Python3 fallback.
  python3 - "$manifest" "$path" <<'PY' && return 0 || true
import sys
from pathlib import Path

manifest_path, dotpath = sys.argv[1], sys.argv[2]
keys = [k for k in dotpath.split('.') if k]
try:
    import yaml
    text = Path(manifest_path).read_text()
    data = yaml.safe_load(text) or {}
    obj = data
    for k in keys[:-1]:
        if k not in obj:
            sys.exit(0)
        obj = obj[k]
    obj.pop(keys[-1], None)
    Path(manifest_path).write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True))
    sys.exit(0)
except Exception as e:
    print(f"Warning: YAML delete failed: {e}", file=sys.stderr)
    sys.exit(1)
PY

  rm -f "$tmpf"
}

# ─── Subcommand: list ─────────────────────────────────────────────────────────
_cmd_list() {
  local active_profile
  active_profile="$(model_active_profile 2>/dev/null || echo 'anthropic')"

  if [ "$OUT" = "json" ]; then
    # Emit the full profiles object with active profile annotated.
    printf '%s' "$PROFILES_JSON" \
      | jq --arg a "$active_profile" '. + {active_profile: $a}'
    return 0
  fi

  printf '\nTier ladder: light < standard < deep\n\n'
  printf 'Profiles:\n'
  printf '%s' "$PROFILES_JSON" | jq -r '.profiles | keys[]' 2>/dev/null | while IFS= read -r pname; do
    local active_mark=""
    [ "$pname" = "$active_profile" ] && active_mark=" [active]"
    local desc
    desc="$(printf '%s' "$PROFILES_JSON" | jq -r --arg p "$pname" '.profiles[$p].description // ""' 2>/dev/null || true)"
    local hosts
    hosts="$(printf '%s' "$PROFILES_JSON" | jq -r --arg p "$pname" '(.profiles[$p].applies_to_hosts // []) | join(", ")' 2>/dev/null || true)"
    printf '\n  %s%s\n' "$pname" "$active_mark"
    [ -n "$desc" ] && printf '    %s\n' "$desc"
    [ -n "$hosts" ] && printf '    applies to: %s\n' "$hosts"
    printf '    %-10s  %-10s  %-10s\n' "light" "standard" "deep"
    local lm sm dm
    lm="$(printf '%s' "$PROFILES_JSON" | jq -r --arg p "$pname" '.profiles[$p].tiers.light // "(none)"' 2>/dev/null || echo '(none)')"
    sm="$(printf '%s' "$PROFILES_JSON" | jq -r --arg p "$pname" '.profiles[$p].tiers.standard // "(none)"' 2>/dev/null || echo '(none)')"
    dm="$(printf '%s' "$PROFILES_JSON" | jq -r --arg p "$pname" '.profiles[$p].tiers.deep // "(none)"' 2>/dev/null || echo '(none)')"
    printf '    %-10s  %-10s  %-10s\n' "$lm" "$sm" "$dm"
  done
  printf '\n'
}

# ─── Subcommand: show ─────────────────────────────────────────────────────────
_cmd_show() {
  local target_id="${1:-}"

  # Strip flags that were already parsed globally.
  case "$target_id" in
    --json|--dry-run|--non-interactive) target_id="" ;;
  esac

  if [ "$OUT" = "json" ]; then
    local out_arr="[]"

    _show_one_json() {
      local id="$1"
      local rl
      rl="$(model_resolve_for "$id" 2>/dev/null || true)"
      if [ -z "$rl" ]; then
        printf '{"eidolon":"%s","error":"resolve-miss"}' "$id"
        return
      fi
      local em ti pr so
      em="$(printf '%s' "$rl" | cut -f1)"
      ti="$(printf '%s' "$rl" | cut -f2)"
      pr="$(printf '%s' "$rl" | cut -f3)"
      so="$(printf '%s' "$rl" | cut -f4)"
      local ln
      ln="$(printf '%s' "$ROUTING_JSON" | jq -r --arg id "$id" '.eidolons[$id].loop_native // false' 2>/dev/null || echo false)"
      printf '%s' "$(jq -n --arg id "$id" --arg em "$em" --arg ti "$ti" \
                         --arg pr "$pr" --arg so "$so" --argjson ln "$ln" \
                       '{eidolon:$id,tier:$ti,profile:$pr,source:$so,effective_model:$em,loop_native:$ln}')"
    }

    if [ -n "$target_id" ]; then
      if ! _assert_eidolon_known "$target_id" 2>/dev/null; then
        printf '{"error":"unknown eidolon","id":"%s"}\n' "$target_id"
        exit 2
      fi
      _show_one_json "$target_id"
      printf '\n'
    else
      local first=1
      printf '['
      model_list_ids 2>/dev/null | while IFS= read -r id; do
        [ -z "$id" ] && continue
        if [ "$first" = "1" ]; then first=0; else printf ','; fi
        _show_one_json "$id"
      done
      printf ']\n'
    fi
    return 0
  fi

  # Human-readable table.
  printf '\n%-12s  %-10s  %-12s  %-16s  %s\n' \
    "EIDOLON" "TIER" "PROFILE" "SOURCE" "EFFECTIVE MODEL"
  printf '%s\n' "$(printf '─%.0s' $(seq 1 70))"

  _show_one_row() {
    local id="$1"
    local rl
    rl="$(model_resolve_for "$id" 2>/dev/null || true)"
    if [ -z "$rl" ]; then
      printf '%-12s  %s\n' "$id" "(resolve-miss)"
      return
    fi
    local em ti pr so
    em="$(printf '%s' "$rl" | cut -f1)"
    ti="$(printf '%s' "$rl" | cut -f2)"
    pr="$(printf '%s' "$rl" | cut -f3)"
    so="$(printf '%s' "$rl" | cut -f4)"
    # loop_native note for apivr.
    local ln_note=""
    local ln
    ln="$(printf '%s' "$ROUTING_JSON" | jq -r --arg id "$id" '.eidolons[$id].loop_native // empty' 2>/dev/null || true)"
    [ "$ln" = "false" ] && ln_note=" [loop_native:false — deep is benchmark-gated]"
    printf '%-12s  %-10s  %-12s  %-16s  %s%s\n' "$id" "$ti" "$pr" "$so" "$em" "$ln_note"
  }

  if [ -n "$target_id" ]; then
    if ! model_list_ids 2>/dev/null | grep -Fxq "$target_id" 2>/dev/null; then
      printf 'Unknown Eidolon: %s\n' "$target_id" >&2
      exit 2
    fi
    _show_one_row "$target_id"
  else
    model_list_ids 2>/dev/null | while IFS= read -r id; do
      [ -z "$id" ] && continue
      _show_one_row "$id"
    done
  fi
  printf '\n'
}

# ─── Subcommand: use ─────────────────────────────────────────────────────────
_cmd_use() {
  local spec="${1:-}"
  if [ -z "$spec" ]; then
    usage >&2; exit 2
  fi
  # Require @ separator.
  case "$spec" in
    *@*) : ;;
    *) printf "Usage: eidolons model use <eidolon>@<tier|model>\n" >&2; exit 2 ;;
  esac

  local eid rhs
  eid="${spec%%@*}"
  rhs="${spec#*@}"

  if [ -z "$eid" ] || [ -z "$rhs" ]; then
    printf "Usage: eidolons model use <eidolon>@<tier|model>\n" >&2; exit 2
  fi

  # Validate eidolon.
  if ! model_list_ids 2>/dev/null | grep -Fxq "$eid" 2>/dev/null; then
    printf "Unknown Eidolon: '%s'\n" "$eid" >&2; exit 2
  fi

  if "$DRY_RUN"; then
    # Show what would happen.
    if _is_tier "$rhs"; then
      printf "[dry-run] Would set models.members.%s.tier = %s\n" "$eid" "$rhs" >&2
    else
      printf "[dry-run] Would set models.members.%s.model = %s (PIN)\n" "$eid" "$rhs" >&2
    fi
    # Show resolved model under proposed change.
    local old_consumer="$CONSUMER_JSON"
    if _is_tier "$rhs"; then
      CONSUMER_JSON="$(printf '%s' "$CONSUMER_JSON" \
        | jq --arg id "$eid" --arg t "$rhs" \
          '.models.members[$id].tier = $t | del(.models.members[$id].model)')"
    else
      CONSUMER_JSON="$(printf '%s' "$CONSUMER_JSON" \
        | jq --arg id "$eid" --arg m "$rhs" '.models.members[$id].model = $m')"
    fi
    export CONSUMER_JSON
    local rl
    rl="$(model_resolve_for "$eid" 2>/dev/null || true)"
    if [ -n "$rl" ]; then
      local em ti pr so
      em="$(printf '%s' "$rl" | cut -f1)"
      ti="$(printf '%s' "$rl" | cut -f2)"
      pr="$(printf '%s' "$rl" | cut -f3)"
      so="$(printf '%s' "$rl" | cut -f4)"
      printf "[dry-run] Resolved: %s | tier=%s | profile=%s | source=%s\n" "$em" "$ti" "$pr" "$so" >&2
    fi
    CONSUMER_JSON="$old_consumer"
    export CONSUMER_JSON
    return 0
  fi

  # Mutate eidolons.yaml.
  if _is_tier "$rhs"; then
    _set_manifest_models_field ".models.members.${eid}.tier" "$rhs"
    _delete_manifest_models_field ".models.members.${eid}.model" 2>/dev/null || true
    ok "Set models.members.${eid}.tier = ${rhs}"
  else
    _set_manifest_models_field ".models.members.${eid}.model" "$rhs"
    _delete_manifest_models_field ".models.members.${eid}.tier" 2>/dev/null || true
    ok "Set models.members.${eid}.model = ${rhs} (PIN)"
  fi

  # Reload consumer JSON and re-resolve.
  CONSUMER_JSON="$(yaml_to_json "${PROJECT_MANIFEST:-eidolons.yaml}" 2>/dev/null || echo '{}')"
  export CONSUMER_JSON

  local rl
  rl="$(model_resolve_for "$eid" 2>/dev/null || true)"
  if [ -z "$rl" ]; then
    warn "Could not resolve model for '$eid' after update."
    exit 3
  fi

  local em ti pr so
  em="$(printf '%s' "$rl" | cut -f1)"
  ti="$(printf '%s' "$rl" | cut -f2)"
  pr="$(printf '%s' "$rl" | cut -f3)"
  so="$(printf '%s' "$rl" | cut -f4)"

  info "Resolved: ${em} (tier=${ti}, profile=${pr}, source=${so})"

  # Patch frontmatter (clobber mode — explicit command consent).
  model_wiring_apply_for_member "$eid" 1 2>/dev/null || {
    warn "Frontmatter write failed for $eid"
    exit 4
  }
  # Update lock provenance.
  model_wiring_update_lock_for_member "$eid" 2>/dev/null || true
}

# ─── Subcommand: profile ──────────────────────────────────────────────────────
_cmd_profile() {
  local pname="${1:-}"
  if [ -z "$pname" ]; then
    usage >&2; exit 2
  fi

  # Validate profile exists.
  if ! printf '%s' "$PROFILES_JSON" | jq -r '.profiles | keys[]' 2>/dev/null \
       | grep -Fxq "$pname" 2>/dev/null; then
    printf "Unknown profile: '%s'. Known: %s\n" "$pname" \
      "$(printf '%s' "$PROFILES_JSON" | jq -r '.profiles | keys[]' 2>/dev/null | tr '\n' ' ')" >&2
    exit 2
  fi

  if "$DRY_RUN"; then
    printf "[dry-run] Would set models.profile = %s and re-resolve all members.\n" "$pname" >&2
    return 0
  fi

  _set_manifest_models_field ".models.profile" "$pname"
  ok "Set models.profile = ${pname}"

  # Reload and re-resolve all members.
  CONSUMER_JSON="$(yaml_to_json "${PROJECT_MANIFEST:-eidolons.yaml}" 2>/dev/null || echo '{}')"
  export CONSUMER_JSON

  # Re-apply model wiring for all members (clobber mode).
  model_wiring_apply_all 1 2>/dev/null || true
  ok "Re-applied model wiring for all members (profile=${pname})"
}

# ─── Subcommand: reset ────────────────────────────────────────────────────────
_cmd_reset() {
  local target_id="${1:-}"
  case "$target_id" in
    --json|--dry-run|--non-interactive) target_id="" ;;
  esac

  if [ -n "$target_id" ]; then
    # Validate eidolon.
    if ! model_list_ids 2>/dev/null | grep -Fxq "$target_id" 2>/dev/null; then
      printf "Unknown Eidolon: '%s'\n" "$target_id" >&2; exit 2
    fi
  fi

  if "$DRY_RUN"; then
    if [ -n "$target_id" ]; then
      printf "[dry-run] Would clear models.members.%s overrides.\n" "$target_id" >&2
    else
      printf "[dry-run] Would clear all models.members overrides and calibration.\n" >&2
    fi
    return 0
  fi

  if [ -n "$target_id" ]; then
    _delete_manifest_models_field ".models.members.${target_id}" 2>/dev/null || true
    ok "Cleared models.members.${target_id} overrides"
  else
    _delete_manifest_models_field ".models.members" 2>/dev/null || true
    _delete_manifest_models_field ".models.calibration" 2>/dev/null || true
    ok "Cleared all models.members overrides and calibration"
  fi

  # Reload and re-apply.
  CONSUMER_JSON="$(yaml_to_json "${PROJECT_MANIFEST:-eidolons.yaml}" 2>/dev/null || echo '{}')"
  export CONSUMER_JSON

  if [ -n "$target_id" ]; then
    model_wiring_apply_for_member "$target_id" 1 2>/dev/null || true
  else
    model_wiring_apply_all 1 2>/dev/null || true
  fi
}

# ─── Interactive picker ───────────────────────────────────────────────────────
_cmd_picker() {
  # Guard: non-interactive or no TTY → print usage and exit 0.
  if "$NON_INTERACTIVE" || [ ! -t 0 ] || [ ! -t 1 ]; then
    usage
    exit 0
  fi

  # Render current state.
  printf '\nCurrent model assignments:\n'
  _cmd_show

  # Main menu loop.
  while true; do
    {
      printf '\n  [1] Change an Eidolon'\''s tier\n'
      printf '  [2] Pin a concrete model\n'
      printf '  [3] Change active profile\n'
      printf '  [4] Reset overrides\n'
      printf '  [q] Quit\n\n'
    } >&2
    local choice
    printf 'Choice: ' >&2
    read -r choice || choice="q"
    choice="$(printf '%s' "$choice" | tr -d '[:space:]')"

    case "$choice" in
      q|Q|"") exit 0 ;;

      1)
        # Pick Eidolon.
        local ids id_list i selected_id selected_tier
        ids="$(model_list_ids 2>/dev/null || true)"
        i=1
        printf '\nEidolons:\n' >&2
        while IFS= read -r _eid; do
          [ -z "$_eid" ] && continue
          printf '  [%s] %s\n' "$i" "$_eid" >&2
          i=$((i + 1))
        done <<EOF
$ids
EOF
        printf 'Pick Eidolon number: ' >&2
        read -r _pick || _pick=""
        _pick="$(printf '%s' "$_pick" | tr -d '[:space:]')"
        # Resolve number → id.
        i=1
        selected_id=""
        while IFS= read -r _eid; do
          [ -z "$_eid" ] && continue
          if [ "$i" = "$_pick" ]; then selected_id="$_eid"; break; fi
          i=$((i + 1))
        done <<EOF
$ids
EOF
        if [ -z "$selected_id" ]; then
          printf 'Invalid selection.\n' >&2; continue
        fi
        # Pick tier.
        printf '\nTiers: [1] light  [2] standard  [3] deep\n' >&2
        printf 'Pick tier number: ' >&2
        read -r _tpick || _tpick=""
        case "$(printf '%s' "$_tpick" | tr -d '[:space:]')" in
          1) selected_tier="light" ;;
          2) selected_tier="standard" ;;
          3) selected_tier="deep" ;;
          *) printf 'Invalid tier.\n' >&2; continue ;;
        esac
        _cmd_use "${selected_id}@${selected_tier}"
        printf '\nUpdated model assignments:\n' >&2
        _cmd_show
        ;;

      2)
        # Pin a model.
        local ids2 i2 selected_id2 pinned_model
        ids2="$(model_list_ids 2>/dev/null || true)"
        i2=1
        printf '\nEidolons:\n' >&2
        while IFS= read -r _eid; do
          [ -z "$_eid" ] && continue
          printf '  [%s] %s\n' "$i2" "$_eid" >&2
          i2=$((i2 + 1))
        done <<EOF
$ids2
EOF
        printf 'Pick Eidolon number: ' >&2
        read -r _pick2 || _pick2=""
        _pick2="$(printf '%s' "$_pick2" | tr -d '[:space:]')"
        i2=1
        selected_id2=""
        while IFS= read -r _eid; do
          [ -z "$_eid" ] && continue
          if [ "$i2" = "$_pick2" ]; then selected_id2="$_eid"; break; fi
          i2=$((i2 + 1))
        done <<EOF
$ids2
EOF
        if [ -z "$selected_id2" ]; then
          printf 'Invalid selection.\n' >&2; continue
        fi
        printf 'Enter model string (e.g. sonnet, gpt-5): ' >&2
        read -r pinned_model || pinned_model=""
        pinned_model="$(printf '%s' "$pinned_model" | tr -d '[:space:]')"
        if [ -z "$pinned_model" ]; then
          printf 'Empty model — skipping.\n' >&2; continue
        fi
        _cmd_use "${selected_id2}@${pinned_model}"
        printf '\nUpdated model assignments:\n' >&2
        _cmd_show
        ;;

      3)
        # Change active profile.
        local pnames pi selected_pname
        pnames="$(printf '%s' "$PROFILES_JSON" | jq -r '.profiles | keys[]' 2>/dev/null || true)"
        pi=1
        printf '\nProfiles:\n' >&2
        while IFS= read -r _pn; do
          [ -z "$_pn" ] && continue
          printf '  [%s] %s\n' "$pi" "$_pn" >&2
          pi=$((pi + 1))
        done <<EOF
$pnames
EOF
        printf 'Pick profile number: ' >&2
        read -r _ppick || _ppick=""
        _ppick="$(printf '%s' "$_ppick" | tr -d '[:space:]')"
        pi=1
        selected_pname=""
        while IFS= read -r _pn; do
          [ -z "$_pn" ] && continue
          if [ "$pi" = "$_ppick" ]; then selected_pname="$_pn"; break; fi
          pi=$((pi + 1))
        done <<EOF
$pnames
EOF
        if [ -z "$selected_pname" ]; then
          printf 'Invalid selection.\n' >&2; continue
        fi
        _cmd_profile "$selected_pname"
        # Reload consumer JSON after profile change.
        CONSUMER_JSON="$(yaml_to_json "${PROJECT_MANIFEST:-eidolons.yaml}" 2>/dev/null || echo '{}')"
        export CONSUMER_JSON
        printf '\nUpdated model assignments:\n' >&2
        _cmd_show
        ;;

      4)
        # Reset.
        printf 'Reset all overrides (tier/pin/calibration)? [y/N] ' >&2
        read -r _rconfirm || _rconfirm=""
        case "$(printf '%s' "$_rconfirm" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
          y|yes)
            _cmd_reset
            # Reload consumer JSON.
            CONSUMER_JSON="$(yaml_to_json "${PROJECT_MANIFEST:-eidolons.yaml}" 2>/dev/null || echo '{}')"
            export CONSUMER_JSON
            printf '\nUpdated model assignments:\n' >&2
            _cmd_show
            ;;
          *) printf 'Aborted.\n' >&2 ;;
        esac
        ;;

      *)
        printf 'Unknown option. Choose 1-4 or q.\n' >&2
        ;;
    esac
  done
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────

subcmd="${1:-}"
[ $# -gt 0 ] && shift

case "$subcmd" in
  list)      _cmd_list     "$@" ;;
  show)      _cmd_show     "$@" ;;
  use)       _cmd_use      "$@" ;;
  profile)   _cmd_profile  "$@" ;;
  reset)     _cmd_reset    "$@" ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  "")
    _cmd_picker
    ;;
  *)
    printf "Unknown model subcommand: '%s'\n" "$subcmd" >&2
    printf "\n" >&2
    printf "Available subcommands: list show use profile reset\n" >&2
    printf "Run 'eidolons model --help' for usage.\n" >&2
    exit 2
    ;;
esac
