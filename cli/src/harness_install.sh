#!/usr/bin/env bash
# cli/src/harness_install.sh — eidolons harness install
# ═══════════════════════════════════════════════════════════════════════════
#
# Wires host hook shims (claude-code, codex) into the consumer project.
# Writes:
#   .eidolons/harness/hooks/<host>-<event>.sh  — executable shim scripts
#   .claude/settings.json                       — merged hooks block (claude-code)
#   .codex/hooks.json                           — conservative shape (codex)
#   eidolons.lock                               — harness: key extension
#
# Idempotent: jq -cS canonical compare before writing; repeat run = no-op.
# Opt-in: init/sync never calls this; only explicit `harness install` invocation.
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.
# Stderr discipline: all say/ok/info/warn/die to stderr; stdout reserved.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

HARNESS_SHIM_DIR=".eidolons/harness/hooks"

usage() {
  cat <<EOF
eidolons harness install — wire host hook shims for routing-context injection

Usage: eidolons harness install [OPTIONS]

Options:
  --hosts <csv>        Comma-separated list of hosts to wire (default: from eidolons.yaml)
                       Supported: claude-code, codex
  --force              Overwrite shims and re-merge settings even if already installed
  --non-interactive    Skip confirmation prompts (for CI / scripted use)
  --refresh-shims-only Re-render shim contents only; no lock or settings changes
                       (called internally by 'eidolons sync' when harness is installed)
  -h, --help           Show this help

Info:
  The new 'eidolons harness install' wires host hooks for routing injection.
  The old 'eidolons harness install <version>' (Junction install) has moved to:
    eidolons mcp install junction[@@<ver>]

Examples:
  eidolons harness install                    # wire hosts from eidolons.yaml
  eidolons harness install --hosts claude-code
  eidolons harness install --hosts claude-code,codex
  eidolons harness install --force            # overwrite existing shims
EOF
}

HOSTS_ARG=""
FORCE=false
NON_INTERACTIVE=false
REFRESH_SHIMS_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hosts)          HOSTS_ARG="${2:-}"; shift 2 ;;
    --force)          FORCE=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --refresh-shims-only) REFRESH_SHIMS_ONLY=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                die "Unknown option: $1 (see 'eidolons harness install --help')" ;;
  esac
done

manifest_exists || die "No eidolons.yaml found. Run 'eidolons init' first."

# ── Resolve hosts to wire ──────────────────────────────────────────────────
if [[ -n "$HOSTS_ARG" ]]; then
  WIRE_HOSTS="$HOSTS_ARG"
else
  MANIFEST_JSON="$(yaml_to_json "$PROJECT_MANIFEST")"
  WIRE_HOSTS="$(printf '%s' "$MANIFEST_JSON" | jq -r '.hosts.wire | join(",")' 2>/dev/null || echo "claude-code")"
fi

# Filter to supported harness hosts only.
_supported_hosts="claude-code,codex"
_resolved_hosts=""
for _h in $(printf '%s' "$WIRE_HOSTS" | tr ',' ' '); do
  case "$_h" in
    claude-code|codex)
      if [[ -z "$_resolved_hosts" ]]; then _resolved_hosts="$_h"; else _resolved_hosts="$_resolved_hosts,$_h"; fi
      ;;
    *)
      info "Skipping unsupported harness host: $_h (supported: $_supported_hosts)"
      ;;
  esac
done

if [[ -z "$_resolved_hosts" ]]; then
  info "No supported harness hosts found in wire list ($WIRE_HOSTS). Nothing to install."
  exit 0
fi

WIRE_HOSTS="$_resolved_hosts"

# ── Shim template renderer ─────────────────────────────────────────────────
# _write_shim HOST EVENT [--session-start]
# Writes the shim to HARNESS_SHIM_DIR/<host>-<event>.sh
_write_shim() {
  local host="$1"
  local event="$2"
  local shim_path="$HARNESS_SHIM_DIR/${host}-${event}.sh"

  if [[ "$event" == "SessionStart" ]]; then
    cat > "$shim_path" <<'SHIM'
#!/usr/bin/env bash
# Eidolons harness shim — SessionStart
# FAIL-OPEN: any error → exit 0, no stdout output.
# Stdout IS the hook context payload — only write when routing succeeds.
set -euo pipefail

_eidolons_bin() {
  if command -v eidolons >/dev/null 2>&1; then
    echo "eidolons"
  elif [[ -x "${EIDOLONS_HOME:-$HOME/.eidolons}/nexus/cli/eidolons" ]]; then
    echo "${EIDOLONS_HOME:-$HOME/.eidolons}/nexus/cli/eidolons"
  else
    return 1
  fi
}

_bin="$(_eidolons_bin 2>/dev/null)" || exit 0
"$_bin" run --hook SESSION_HOST --session-start 2>/dev/null || exit 0
SHIM
    # Substitute SESSION_HOST with the actual host value (bash 3.2 safe: sed)
    sed -i '' "s/SESSION_HOST/${host}/g" "$shim_path" 2>/dev/null \
      || sed -i "s/SESSION_HOST/${host}/g" "$shim_path"
  else
    # UserPromptSubmit shim
    cat > "$shim_path" <<'SHIM'
#!/usr/bin/env bash
# Eidolons harness shim — UserPromptSubmit
# FAIL-OPEN: any error → exit 0, no stdout output.
# Stdout IS the hook context payload — only write when routing succeeds.
set -euo pipefail

_eidolons_bin() {
  if command -v eidolons >/dev/null 2>&1; then
    echo "eidolons"
  elif [[ -x "${EIDOLONS_HOME:-$HOME/.eidolons}/nexus/cli/eidolons" ]]; then
    echo "${EIDOLONS_HOME:-$HOME/.eidolons}/nexus/cli/eidolons"
  else
    return 1
  fi
}

_bin="$(_eidolons_bin 2>/dev/null)" || exit 0
# Read stdin into a variable (hook passes event JSON on stdin).
_input="$(cat 2>/dev/null)" || exit 0
# Extract .prompt field; if jq absent or field missing, fall through to empty stdout.
if command -v jq >/dev/null 2>&1 && [[ -n "$_input" ]]; then
  _prompt="$(printf '%s' "$_input" | jq -r '.prompt // empty' 2>/dev/null)" || _prompt=""
else
  _prompt=""
fi
[[ -n "$_prompt" ]] || exit 0
"$_bin" run --hook UPS_HOST --stdin <<< "$_input" 2>/dev/null || exit 0
SHIM
    sed -i '' "s/UPS_HOST/${host}/g" "$shim_path" 2>/dev/null \
      || sed -i "s/UPS_HOST/${host}/g" "$shim_path"
  fi

  chmod +x "$shim_path"
}

# ── Refresh-shims-only mode (called by sync) ──────────────────────────────
if [[ "$REFRESH_SHIMS_ONLY" == "true" ]]; then
  if [[ ! -f "$PROJECT_LOCK" ]]; then
    exit 0
  fi
  _lock_hosts="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r '(.harness.hosts_wired // []) | join(",")' 2>/dev/null || echo "")"
  [[ -n "$_lock_hosts" ]] || exit 0

  mkdir -p "$HARNESS_SHIM_DIR"
  for _host in $(printf '%s' "$_lock_hosts" | tr ',' ' '); do
    [[ -z "$_host" ]] && continue
    _write_shim "$_host" "UserPromptSubmit"
    _write_shim "$_host" "SessionStart"
    info "  refreshed shims for $_host"
  done
  ok "Harness shims refreshed"
  exit 0
fi

# ── Check if already installed (no-op gate) ───────────────────────────────
_already_installed=false
if [[ -f "$PROJECT_LOCK" ]] && [[ "$FORCE" == "false" ]]; then
  _lock_schema="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r '.harness.schema_version // "absent"' 2>/dev/null || echo "absent")"
  if [[ "$_lock_schema" != "absent" ]]; then
    _already_installed=true
  fi
fi

# ── Install shims ──────────────────────────────────────────────────────────
say "Installing harness shims for hosts: $WIRE_HOSTS"
mkdir -p "$HARNESS_SHIM_DIR"

_shim_paths=""
_hosts_wired_sorted=""

# Collect and sort hosts (canonical for lockfile).
_hosts_sorted="$(printf '%s' "$WIRE_HOSTS" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')"

for _host in $(printf '%s' "$_hosts_sorted" | tr ',' ' '); do
  [[ -z "$_host" ]] && continue

  _write_shim "$_host" "UserPromptSubmit"
  _write_shim "$_host" "SessionStart"
  info "  wrote shims for $_host"

  _ups_path="$HARNESS_SHIM_DIR/${_host}-UserPromptSubmit.sh"
  _ss_path="$HARNESS_SHIM_DIR/${_host}-SessionStart.sh"
  if [[ -z "$_shim_paths" ]]; then
    _shim_paths="$_ups_path,$_ss_path"
  else
    _shim_paths="$_shim_paths,$_ups_path,$_ss_path"
  fi
  if [[ -z "$_hosts_wired_sorted" ]]; then
    _hosts_wired_sorted="$_host"
  else
    _hosts_wired_sorted="$_hosts_wired_sorted,$_host"
  fi
done

# ── Wire claude-code settings.json ────────────────────────────────────────
# Spec R2: append our entries to each event array only if not already present.
# Never replace sibling events or other entries (FINDING-1 fix).
if printf '%s' ",$_hosts_wired_sorted," | grep -q ",claude-code,"; then
  mkdir -p .claude
  SETTINGS_JSON=".claude/settings.json"

  _ups_cmd="$HARNESS_SHIM_DIR/claude-code-UserPromptSubmit.sh"
  _ss_cmd="$HARNESS_SHIM_DIR/claude-code-SessionStart.sh"

  if [[ ! -f "$SETTINGS_JSON" ]]; then
    # Fresh file — write with only our hooks entries.
    jq -n \
      --arg ups "$_ups_cmd" \
      --arg ss "$_ss_cmd" \
      '{"hooks": {
          "UserPromptSubmit": [{"hooks": [{"type": "command", "command": $ups}]}],
          "SessionStart": [{"matcher": "startup", "hooks": [{"type": "command", "command": $ss}]}]
       }}' > "$SETTINGS_JSON"
    ok "Wrote .claude/settings.json with hooks block"
  else
    # Existing file — surgical append: for each event, add our entry only if
    # no entry with our command already exists; create event array if absent.
    if ! jq empty "$SETTINGS_JSON" 2>/dev/null; then
      warn ".claude/settings.json is not valid JSON — skipping hooks merge (manual merge required)"
    else
      _existing_canonical="$(jq -cS . "$SETTINGS_JSON" 2>/dev/null || echo "")"
      _merged="$(jq \
        --arg ups "$_ups_cmd" \
        --arg ss "$_ss_cmd" \
        '
        # Append UserPromptSubmit entry only if command not already present.
        .hooks.UserPromptSubmit = (
          (.hooks.UserPromptSubmit // []) as $arr |
          if ($arr | map(.hooks[]?.command? // "") | any(. == $ups)) then $arr
          else $arr + [{"hooks": [{"type": "command", "command": $ups}]}]
          end
        ) |
        # Append SessionStart entry only if command not already present.
        .hooks.SessionStart = (
          (.hooks.SessionStart // []) as $arr |
          if ($arr | map(.hooks[]?.command? // "") | any(. == $ss)) then $arr
          else $arr + [{"matcher": "startup", "hooks": [{"type": "command", "command": $ss}]}]
          end
        )
        ' "$SETTINGS_JSON")"
      _merged_canonical="$(printf '%s' "$_merged" | jq -cS . 2>/dev/null || echo "")"
      if [[ "$_existing_canonical" != "$_merged_canonical" ]]; then
        printf '%s\n' "$_merged" > "$SETTINGS_JSON"
        ok "Merged hooks entries into .claude/settings.json"
      else
        info ".claude/settings.json already has identical hooks entries (no-op)"
      fi
    fi
  fi
fi

# ── Wire codex hooks.json ──────────────────────────────────────────────────
if printf '%s' ",$_hosts_wired_sorted," | grep -q ",codex,"; then
  mkdir -p .codex
  CODEX_HOOKS=".codex/hooks.json"
  # [ASSUMPTION A1]: codex hooks.json project-scope shape:
  # {"hooks": {"UserPromptSubmit": [{"command": "..."}], "SessionStart": [{"command": "..."}]}}
  warn "[ASSUMPTION A1] .codex/hooks.json schema — verify with 'eidolons doctor' once Codex hook support is confirmed."
  _codex_ups_cmd="$HARNESS_SHIM_DIR/codex-UserPromptSubmit.sh"
  _codex_ss_cmd="$HARNESS_SHIM_DIR/codex-SessionStart.sh"
  _codex_json="$(jq -n \
    --arg ups "$_codex_ups_cmd" \
    --arg ss "$_codex_ss_cmd" \
    '{"hooks": {"UserPromptSubmit": [{"command": $ups}], "SessionStart": [{"command": $ss}]}}')"

  if [[ ! -f "$CODEX_HOOKS" ]]; then
    printf '%s\n' "$_codex_json" > "$CODEX_HOOKS"
    ok "Wrote .codex/hooks.json"
  else
    _existing_codex="$(jq -cS . "$CODEX_HOOKS" 2>/dev/null || echo "")"
    _new_codex="$(printf '%s' "$_codex_json" | jq -cS . 2>/dev/null || echo "")"
    if [[ "$_existing_codex" != "$_new_codex" ]]; then
      printf '%s\n' "$_codex_json" > "$CODEX_HOOKS"
      ok "Overwrote .codex/hooks.json"
    else
      info ".codex/hooks.json already up-to-date (no-op)"
    fi
  fi
fi

# ── Update eidolons.lock harness key ──────────────────────────────────────
if [[ -f "$PROJECT_LOCK" ]]; then
  # Build the harness YAML block (no run-state fields — FINDING-2 fix).
  _hosts_yaml=""
  for _h in $(printf '%s' "$_hosts_wired_sorted" | tr ',' ' '); do
    [[ -z "$_h" ]] && continue
    _hosts_yaml="${_hosts_yaml}    - $_h
"
  done

  _shims_yaml=""
  for _sp in $(printf '%s' "$_shim_paths" | tr ',' ' '); do
    [[ -z "$_sp" ]] && continue
    _shims_yaml="${_shims_yaml}    - $_sp
"
  done

  # Build the new harness block text.
  _new_harness_block="$(printf 'harness:\n  schema_version: 1\n  hosts_wired:\n%s  shim_paths:\n%s' \
    "$_hosts_yaml" "$_shims_yaml")"

  # Read existing lock, strip any existing harness: block using awk (FINDING-3 fix).
  # awk prints lines, suppresses from /^harness:/ until the next top-level key or EOF.
  _lock_no_harness="$(awk '
    /^harness:/ { skip=1; next }
    skip && /^[^[:space:]]/ { skip=0 }
    !skip { print }
  ' "$PROJECT_LOCK" | sed -e 's/[[:space:]]*$//' | awk 'NR==1{p=$0; next} /^$/{if(p!="") print p; p=""; next} {if(p!="") print p; p=$0} END{if(p!="") print p}')"

  # No-op check: compare new harness block against existing one in lock (FINDING-2 fix).
  _existing_harness_block="$(awk '
    /^harness:/ { skip=1; print; next }
    skip && /^[^[:space:]]/ { skip=0 }
    skip { print }
  ' "$PROJECT_LOCK")"

  if [[ "$_existing_harness_block" = "$_new_harness_block" ]]; then
    info "eidolons.lock harness: block unchanged (no-op)"
  else
    {
      printf '%s\n' "$_lock_no_harness"
      printf '%s\n' "$_new_harness_block"
    } > "${PROJECT_LOCK}.harness.tmp"
    mv "${PROJECT_LOCK}.harness.tmp" "$PROJECT_LOCK"
    ok "Updated eidolons.lock with harness: key"
  fi
else
  warn "eidolons.lock not found — harness: key not written. Run 'eidolons sync' first."
fi

ok "Harness installed for hosts: $_hosts_wired_sorted"
info "Shims: $HARNESS_SHIM_DIR/"
info "Run 'eidolons harness status' to verify."
