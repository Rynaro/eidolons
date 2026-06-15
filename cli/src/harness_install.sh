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

# Canonical SessionStart matcher — single source of truth. Covers every CC
# source value (startup|resume|clear|compact) so the cortex is re-injected
# after auto-compaction. Changing the source-list touches ONLY this line.
_SS_MATCHER="startup|resume|clear|compact"

usage() {
  cat <<EOF
eidolons harness install — wire host hook shims for routing-context injection

Usage: eidolons harness install [OPTIONS]

Options:
  --hosts <csv>        Comma-separated list of hosts to wire (default: from eidolons.yaml)
                       Supported: claude-code, codex, copilot
  --strict             Enable strict tool-boundary BLOCK tier (opt-in; lock-recorded).
                       Sound on: claude-code (delegate-or-deny + protected-globs),
                                 codex (protected-globs only; delegate-or-deny refused).
                       Advisory plugin on: opencode (tool.execute.before; #5894 caveat).
                       Refused on: cursor (out of P3 scope).
  --force              Overwrite shims and re-merge settings even if already installed
  --non-interactive    Skip confirmation prompts (for CI / scripted use)
  --refresh-shims-only Re-render shim contents only; no lock or settings changes
                       (called internally by 'eidolons sync' when harness is installed)
  --no-heal            Skip the seamless SessionStart-matcher self-heal during
                       --refresh-shims-only (default: heal a stale 'startup'-only
                       matcher in .claude/settings.json in place).
  -h, --help           Show this help

Info:
  The new 'eidolons harness install' wires host hooks for routing injection.
  The old 'eidolons harness install <version>' (Junction install) has moved to:
    eidolons mcp install junction[@@<ver>]

Examples:
  eidolons harness install                    # wire hosts from eidolons.yaml
  eidolons harness install --hosts claude-code
  eidolons harness install --hosts claude-code,codex
  eidolons harness install --hosts copilot    # best-effort sessionStart adapter
  eidolons harness install --force            # overwrite existing shims
EOF
}

HOSTS_ARG=""
FORCE=false
NON_INTERACTIVE=false
REFRESH_SHIMS_ONLY=false
STRICT=false
WITH_TELEMETRY=false
NO_HEAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hosts)           HOSTS_ARG="${2:-}"; shift 2 ;;
    --force)           FORCE=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --refresh-shims-only) REFRESH_SHIMS_ONLY=true; shift ;;
    --no-heal)         NO_HEAL=true; shift ;;
    --strict)          STRICT=true; shift ;;
    --with-telemetry)  WITH_TELEMETRY=true; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 die "Unknown option: $1 (see 'eidolons harness install --help')" ;;
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
_supported_hosts="claude-code,codex,copilot,cursor,opencode"
_resolved_hosts=""
for _h in $(printf '%s' "$WIRE_HOSTS" | tr ',' ' '); do
  case "$_h" in
    claude-code|codex|copilot|cursor|opencode)
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
    # UserPromptSubmit shim (includes R21 #16952 guard)
    cat > "$shim_path" <<'SHIM'
#!/usr/bin/env bash
# Eidolons harness shim — UserPromptSubmit
# FAIL-OPEN: any error → exit 0, no stdout output.
# Stdout IS the hook context payload — only write when routing succeeds.
# R21: #16952 guard — skip kernel when prompt is a task-completion notification.
# (Claude bug: UserPromptSubmit also fires on Task/subagent completion; conservative
#  best-effort heuristic; fail-open: false-positive = one skipped inject, harmless.)
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
# #16952 guard: skip kernel when the prompt is a task-completion notification.
case "$_prompt" in
  "Agent "*" completed"*) exit 0 ;;
  *"<task-notification>"*) exit 0 ;;
esac
"$_bin" run --hook UPS_HOST --stdin <<< "$_input" 2>/dev/null || exit 0
SHIM
    sed -i '' "s/UPS_HOST/${host}/g" "$shim_path" 2>/dev/null \
      || sed -i "s/UPS_HOST/${host}/g" "$shim_path"
  fi

  chmod +x "$shim_path"
}

# _write_pretooluse_shim HOST PROTECT_GLOBS_CONTENT
# Writes the strict PreToolUse deny shim for HOST (claude-code or codex).
# PROTECT_GLOBS_CONTENT is a newline-joined list of glob patterns (may be empty).
_write_pretooluse_shim() {
  local host="$1"
  local protect_globs="$2"
  local shim_path="$HARNESS_SHIM_DIR/${host}-PreToolUse.sh"

  if [[ "$host" == "claude-code" ]]; then
    cat > "$shim_path" <<'SHIM'
#!/usr/bin/env bash
# Eidolons strict-tier shim — claude-code PreToolUse
# Stateless delegate-or-deny + protected-globs deny (anti-reward-hack).
# Rule order: (1) protected-glob check FIRST (denies in ALL contexts, including subagents);
#             (2) delegate-or-deny: agent_id ABSENT => main loop => deny.
# FAIL-OPEN: any error/malformed stdin => exit 0 empty (allow). ONLY deny paths emit deny.
# Deny shape (verified): hookSpecificOutput.permissionDecision:"deny" + permissionDecisionReason.
set -euo pipefail

_deny() {
  jq -n --arg r "Eidolons strict tier: $1." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
}

_main() {
  command -v jq >/dev/null 2>&1 || return 0
  _in="$(cat 2>/dev/null)" || return 0
  [[ -n "$_in" ]] || return 0
  _tool="$(printf '%s' "$_in" | jq -r '.tool_name // empty' 2>/dev/null)" || return 0
  case "$_tool" in Edit|Write|MultiEdit|NotebookEdit) : ;; *) return 0 ;; esac
  _fp="$(printf '%s' "$_in" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || _fp=""
  # 1) Protected-glob check FIRST (denies in ALL contexts — anti-reward-hack).
  if [[ -n "$_fp" ]]; then
    while IFS= read -r _g; do
      [[ -z "$_g" ]] && continue
      # Normalize /**  to /* so bash case * matches recursively (A4 verified).
      _gn="${_g%/**}/*"
      case "$_fp" in
        "$_g"|$_gn) _deny "$_fp matches protected glob $_g"; return 0 ;;
      esac
    done <<'GLOBS'
PROTECT_GLOBS_PLACEHOLDER
GLOBS
  fi
  # 2) Delegate-or-deny: agent_id ABSENT => main loop => deny.
  _aid="$(printf '%s' "$_in" | jq -r '.agent_id // empty' 2>/dev/null)" || _aid=""
  if [[ -z "$_aid" ]]; then
    _deny "direct edits from the main loop are denied. Delegate this edit to a coder Eidolon (Vivi) per the routing artifact. Re-issue the edit from within the delegated subagent"
    return 0
  fi
  return 0
}
_main 2>/dev/null || true
SHIM
    # Replace PROTECT_GLOBS_PLACEHOLDER with actual globs.
    # Use python3-free line-by-line approach: read the shim, emit lines,
    # replace the placeholder line with the globs content.
    local tmp_shim
    tmp_shim="$(mktemp)"
    local _saw_placeholder=false
    while IFS= read -r _sline; do
      if [[ "$_sline" == "PROTECT_GLOBS_PLACEHOLDER" ]]; then
        # Emit each glob on its own line.
        if [[ -n "$protect_globs" ]]; then
          printf '%s\n' "$protect_globs" >> "$tmp_shim"
        fi
        _saw_placeholder=true
      else
        printf '%s\n' "$_sline" >> "$tmp_shim"
      fi
    done < "$shim_path"
    mv "$tmp_shim" "$shim_path"

  elif [[ "$host" == "codex" ]]; then
    cat > "$shim_path" <<'SHIM'
#!/usr/bin/env bash
# Eidolons strict-tier shim — codex PreToolUse
# Protected-globs ONLY. Delegate-or-deny REFUSED (Codex PreToolUse has no agent_id;
# subagent firing is undocumented — cannot discriminate main-loop vs subagent).
# [ASSUMPTION A5]: apply_patch path in tool_input.file_path OR tool_input.path;
#                  shim tries both; fails open if neither resolves.
# FAIL-OPEN: any error/malformed stdin => exit 0 empty (allow). Only glob path denies.
# Deny shape (codex): {"decision":"block","reason":"..."} exit 0.
set -euo pipefail

_deny_codex() {
  jq -n --arg r "Eidolons strict: $1." '{decision:"block",reason:$r}'
}

_main() {
  command -v jq >/dev/null 2>&1 || return 0
  _in="$(cat 2>/dev/null)" || return 0
  [[ -n "$_in" ]] || return 0
  # Extract the edit target: try file_path first, then path (A5 — both fields tried).
  _fp="$(printf '%s' "$_in" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)" || _fp=""
  [[ -n "$_fp" ]] || return 0
  # Protected-glob check (denies in ALL contexts — the only check for codex).
  while IFS= read -r _g; do
    [[ -z "$_g" ]] && continue
    _gn="${_g%/**}/*"
    case "$_fp" in
      "$_g"|$_gn) _deny_codex "$_fp matches protected glob $_g"; return 0 ;;
    esac
  done <<'GLOBS'
PROTECT_GLOBS_PLACEHOLDER
GLOBS
  return 0
}
_main 2>/dev/null || true
SHIM
    local tmp_shim2
    tmp_shim2="$(mktemp)"
    local _saw_placeholder2=false
    while IFS= read -r _sline2; do
      if [[ "$_sline2" == "PROTECT_GLOBS_PLACEHOLDER" ]]; then
        if [[ -n "$protect_globs" ]]; then
          printf '%s\n' "$protect_globs" >> "$tmp_shim2"
        fi
        _saw_placeholder2=true
      else
        printf '%s\n' "$_sline2" >> "$tmp_shim2"
      fi
    done < "$shim_path"
    mv "$tmp_shim2" "$shim_path"
  fi

  chmod +x "$shim_path"
}

# _write_stop_shim HOST
# Writes the zero-logic telemetry Stop shim for HOST.
# Mirrors the UPS shim pattern (§4.1). Only called when --with-telemetry is set.
_write_stop_shim() {
  local host="$1"
  local shim_path="$HARNESS_SHIM_DIR/${host}-Stop.sh"

  cat > "$shim_path" <<'SHIM'
#!/usr/bin/env bash
# Eidolons telemetry shim — STOP_HOST Stop
# ZERO LOGIC: cat stdin → exec telemetry capture. No parsing. No decisions.
# FAIL-OPEN: any error → exit 0.
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
_input="$(cat 2>/dev/null)" || exit 0
[[ -n "$_input" ]] || exit 0
"$_bin" telemetry capture --hook STOP_HOST --stdin <<< "$_input" 2>/dev/null || exit 0
SHIM
  sed -i '' "s/STOP_HOST/${host}/g" "$shim_path" 2>/dev/null \
    || sed -i "s/STOP_HOST/${host}/g" "$shim_path"
  chmod +x "$shim_path"
}

# _register_stop_in_settings SHIM_CMD SETTINGS_JSON
# Idempotent surgical-append of a Stop hook entry into .claude/settings.json.
# Mirrors the UPS/SessionStart pattern (harness_install.sh:497-550).
_register_stop_in_settings() {
  local stop_cmd="$1"
  local settings_file="$2"

  if [[ ! -f "$settings_file" ]]; then
    jq -n \
      --arg stop "$stop_cmd" \
      '{"hooks": {
          "Stop": [{"hooks": [{"type": "command", "command": $stop}]}]
       }}' > "$settings_file"
    ok "Wrote $settings_file with Stop hook"
    return
  fi
  if ! jq empty "$settings_file" 2>/dev/null; then
    warn "$settings_file is not valid JSON — skipping Stop hook merge"
    return
  fi
  local _existing_canonical _merged _merged_canonical
  _existing_canonical="$(jq -cS . "$settings_file" 2>/dev/null || echo "")"
  _merged="$(jq \
    --arg stop "$stop_cmd" \
    '
    .hooks.Stop = (
      (.hooks.Stop // []) as $arr |
      if ($arr | map(.hooks[]?.command? // "") | any(. == $stop)) then $arr
      else $arr + [{"hooks": [{"type": "command", "command": $stop}]}]
      end
    )
    ' "$settings_file")"
  _merged_canonical="$(printf '%s' "$_merged" | jq -cS . 2>/dev/null || echo "")"
  if [[ "$_existing_canonical" != "$_merged_canonical" ]]; then
    printf '%s\n' "$_merged" > "$settings_file"
    ok "Merged Stop hook entry into $settings_file"
  else
    info "$settings_file already has Stop hook entry (no-op)"
  fi
}

# _heal_session_start_matcher SETTINGS_JSON SHIM_CMD
# Seamless self-heal: if SETTINGS_JSON has OUR SessionStart entry (command ==
# SHIM_CMD), force its matcher to the canonical $_SS_MATCHER (upsert: heal-in-place
# if present, else append). Foreign entries and sibling events are never touched.
# Idempotent: jq -cS canonical compare before writing; write ONLY on change.
# Fail-SOFT: any jq/IO error → warn + return (never abort the caller).
_heal_session_start_matcher() {
  local settings_file="$1"
  local ss_cmd="$2"
  [[ -f "$settings_file" ]] || return 0
  if ! jq empty "$settings_file" 2>/dev/null; then
    warn "$settings_file is not valid JSON — skipping SessionStart matcher heal"
    return 0
  fi
  local _before _healed _after
  _before="$(jq -cS . "$settings_file" 2>/dev/null)" || { warn "could not read $settings_file — skipping heal"; return 0; }
  _healed="$(jq \
    --arg ss "$ss_cmd" \
    --arg m "$_SS_MATCHER" \
    '
    .hooks.SessionStart = (
      (.hooks.SessionStart // []) as $arr |
      if ($arr | map(.hooks[]?.command? // "") | any(. == $ss)) then
        ($arr | map(if ((.hooks // []) | any(.command? == $ss)) then (.matcher = $m) else . end))
      else
        $arr + [{"matcher": $m, "hooks": [{"type": "command", "command": $ss}]}]
      end
    )
    ' "$settings_file" 2>/dev/null)" || { warn "SessionStart matcher heal failed (jq) — leaving $settings_file unchanged"; return 0; }
  _after="$(printf '%s' "$_healed" | jq -cS . 2>/dev/null)" || { warn "SessionStart matcher heal produced invalid JSON — leaving $settings_file unchanged"; return 0; }
  if [[ "$_before" != "$_after" ]]; then
    printf '%s\n' "$_healed" > "$settings_file" 2>/dev/null \
      || { warn "could not write $settings_file — heal skipped"; return 0; }
    ok "healed stale SessionStart matcher (startup -> $_SS_MATCHER) in $settings_file"
  fi
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
    # Copilot: SessionStart only (no UserPromptSubmit — copilot-cli#1139).
    if [[ "$_host" == "copilot" ]]; then
      _write_shim "$_host" "SessionStart"
      info "  refreshed SessionStart shim for $_host"
    else
      _write_shim "$_host" "UserPromptSubmit"
      _write_shim "$_host" "SessionStart"
      info "  refreshed shims for $_host"
    fi
    # Seamless self-heal: correct a stale 'startup'-only SessionStart matcher
    # in .claude/settings.json (claude-code only). Opt out with --no-heal.
    if [[ "$_host" == "claude-code" ]] && [[ "$NO_HEAL" != "true" ]]; then
      _heal_session_start_matcher ".claude/settings.json" "$HARNESS_SHIM_DIR/claude-code-SessionStart.sh"
    fi
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

  # Copilot: SessionStart only (userPromptSubmitted output is unprocessed — per-prompt
  # injection impossible, copilot-cli#1139). All other supported-shim hosts get both.
  # Cursor/opencode: no base UPS/SessionStart shims (they surface via sync/strict only).
  if [[ "$_host" == "cursor" ]] || [[ "$_host" == "opencode" ]]; then
    info "  $_host: no base-tier UPS/SessionStart shims (static surfaces via sync; strict via --strict)"
    # No shim file written; host is still recorded in hosts_wired for status/strict routing.
  elif [[ "$_host" == "copilot" ]]; then
    _write_shim "$_host" "SessionStart"
    info "  wrote SessionStart shim for $_host (SessionStart-only; see caveat below)"
    _ss_path="$HARNESS_SHIM_DIR/${_host}-SessionStart.sh"
    if [[ -z "$_shim_paths" ]]; then
      _shim_paths="$_ss_path"
    else
      _shim_paths="$_shim_paths,$_ss_path"
    fi
  else
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
  fi

  if [[ -z "$_hosts_wired_sorted" ]]; then
    _hosts_wired_sorted="$_host"
  else
    _hosts_wired_sorted="$_hosts_wired_sorted,$_host"
  fi
done

# ── Strict tier: PreToolUse shims + advisory plugin (R18/R19/R20) ────────
# Only written when --strict is set. Sound strict hosts: claude-code (block),
# codex (protected-globs only). Advisory: opencode. Refused: cursor.
_strict_hosts=""       # sorted CSV of strict-wired hosts
_strict_modes_yaml=""  # per-host mode for lock strict_modes:
_protect_globs=""      # newline-joined globs from harness.protect

if [[ "$STRICT" == "true" ]]; then
  # Read protected globs from eidolons.yaml harness.protect (may be empty).
  MANIFEST_JSON_STRICT="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null || echo '{}')"
  _protect_globs="$(printf '%s' "$MANIFEST_JSON_STRICT" \
    | jq -r '(.harness.protect // [])[]' 2>/dev/null || echo "")"

  for _sh in $(printf '%s' "$_hosts_wired_sorted" | tr ',' '\n' | sort); do
    [[ -z "$_sh" ]] && continue
    case "$_sh" in
      claude-code)
        # R19: write claude-code PreToolUse shim (delegate-or-deny + protected-globs).
        _write_pretooluse_shim "claude-code" "$_protect_globs"
        info "  wrote claude-code-PreToolUse.sh (strict: delegate-or-deny + protected-globs)"
        _strict_hosts="${_strict_hosts:+${_strict_hosts},}claude-code"
        _strict_modes_yaml="${_strict_modes_yaml}    claude-code: block\n"
        # Add shim path to shim_paths.
        _pts_path="$HARNESS_SHIM_DIR/claude-code-PreToolUse.sh"
        _shim_paths="${_shim_paths:+${_shim_paths},}${_pts_path}"
        ;;
      codex)
        # R20: write codex PreToolUse shim (protected-globs only; delegate-or-deny refused).
        warn "refuse: codex strict delegate-or-deny is not implemented — Codex PreToolUse does not expose agent_id/agent_type (only SubagentStart/Stop do), so main-loop vs subagent edits cannot be distinguished. Codex strict enforces protected-globs only. (undocumented subagent firing)"
        _write_pretooluse_shim "codex" "$_protect_globs"
        info "  wrote codex-PreToolUse.sh (strict: protected-globs only)"
        if [[ -z "$_protect_globs" ]]; then
          info "  codex strict: harness.protect is empty — codex strict has no globs to enforce (near no-op)"
        fi
        _strict_hosts="${_strict_hosts:+${_strict_hosts},}codex"
        _strict_modes_yaml="${_strict_modes_yaml}    codex: protected-globs-only\n"
        _pts_path="$HARNESS_SHIM_DIR/codex-PreToolUse.sh"
        _shim_paths="${_shim_paths:+${_shim_paths},}${_pts_path}"
        ;;
      opencode)
        # R18/R-plugin: advisory plugin (tool.execute.before; #5894 subagent bypass — unsound hard block).
        warn "refuse: opencode tool.execute.before block is unsound (subagent bypass #5894) — writing advisory plugin only, no hard block"
        _oc_plugin_dir=".opencode/plugins"
        _oc_plugin_file="${_oc_plugin_dir}/eidolons.js"
        _oc_plugin_tmpl="${SELF_DIR}/../templates/harness/opencode-eidolons.js"
        mkdir -p "$_oc_plugin_dir"
        if [ -f "$_oc_plugin_tmpl" ]; then
          cp "$_oc_plugin_tmpl" "$_oc_plugin_file"
          ok "  wrote ${_oc_plugin_file} (strict: advisory plugin, primary-agent-only)"
        else
          warn "  opencode-eidolons.js template not found at ${_oc_plugin_tmpl} — skipping plugin write"
        fi
        _strict_hosts="${_strict_hosts:+${_strict_hosts},}opencode"
        _strict_modes_yaml="${_strict_modes_yaml}    opencode: advisory\n"
        ;;
      cursor)
        # cursor strict is OUT of P3 scope.
        warn "refuse: cursor strict (delegate-or-deny) is out of P3 scope — no cursor PreToolUse surface written"
        ;;
    esac
  done
fi

# ── Wire claude-code settings.json ────────────────────────────────────────
# Spec R2: append our entries to each event array only if not already present.
# Never replace sibling events or other entries (FINDING-1 fix).
if printf '%s' ",$_hosts_wired_sorted," | grep -q ",claude-code,"; then
  mkdir -p .claude
  SETTINGS_JSON=".claude/settings.json"

  _ups_cmd="$HARNESS_SHIM_DIR/claude-code-UserPromptSubmit.sh"
  _ss_cmd="$HARNESS_SHIM_DIR/claude-code-SessionStart.sh"

  _ptu_cmd="$HARNESS_SHIM_DIR/claude-code-PreToolUse.sh"
  _ptu_matcher="Edit|Write|MultiEdit|NotebookEdit"

  if [[ ! -f "$SETTINGS_JSON" ]]; then
    # Fresh file — write with only our hooks entries.
    if [[ "$STRICT" == "true" ]] && printf '%s' ",$_strict_hosts," | grep -q ",claude-code,"; then
      jq -n \
        --arg ups "$_ups_cmd" \
        --arg ss "$_ss_cmd" \
        --arg ptu "$_ptu_cmd" \
        --arg ptm "$_ptu_matcher" \
        --arg m "$_SS_MATCHER" \
        '{"hooks": {
            "UserPromptSubmit": [{"hooks": [{"type": "command", "command": $ups}]}],
            "SessionStart": [{"matcher": $m, "hooks": [{"type": "command", "command": $ss}]}],
            "PreToolUse": [{"matcher": $ptm, "hooks": [{"type": "command", "command": $ptu}]}]
         }}' > "$SETTINGS_JSON"
    else
      jq -n \
        --arg ups "$_ups_cmd" \
        --arg ss "$_ss_cmd" \
        --arg m "$_SS_MATCHER" \
        '{"hooks": {
            "UserPromptSubmit": [{"hooks": [{"type": "command", "command": $ups}]}],
            "SessionStart": [{"matcher": $m, "hooks": [{"type": "command", "command": $ss}]}]
         }}' > "$SETTINGS_JSON"
    fi
    ok "Wrote .claude/settings.json with hooks block"
  else
    # Existing file — surgical append: for each event, add our entry only if
    # no entry with our command already exists; create event array if absent.
    if ! jq empty "$SETTINGS_JSON" 2>/dev/null; then
      warn ".claude/settings.json is not valid JSON — skipping hooks merge (manual merge required)"
    else
      _existing_canonical="$(jq -cS . "$SETTINGS_JSON" 2>/dev/null || echo "")"
      if [[ "$STRICT" == "true" ]] && printf '%s' ",$_strict_hosts," | grep -q ",claude-code,"; then
        _merged="$(jq \
          --arg ups "$_ups_cmd" \
          --arg ss "$_ss_cmd" \
          --arg ptu "$_ptu_cmd" \
          --arg ptm "$_ptu_matcher" \
          --arg m "$_SS_MATCHER" \
          '
          # Append UserPromptSubmit entry only if command not already present.
          .hooks.UserPromptSubmit = (
            (.hooks.UserPromptSubmit // []) as $arr |
            if ($arr | map(.hooks[]?.command? // "") | any(. == $ups)) then $arr
            else $arr + [{"hooks": [{"type": "command", "command": $ups}]}]
            end
          ) |
          # SessionStart UPSERT: heal-our-matcher-in-place if present, else append.
          # (Heals a stale "startup"-only matcher so --force self-heals.)
          .hooks.SessionStart = (
            (.hooks.SessionStart // []) as $arr |
            if ($arr | map(.hooks[]?.command? // "") | any(. == $ss)) then
              ($arr | map(if ((.hooks // []) | any(.command? == $ss)) then (.matcher = $m) else . end))
            else
              $arr + [{"matcher": $m, "hooks": [{"type": "command", "command": $ss}]}]
            end
          ) |
          # Append PreToolUse entry only if command not already present (R19 AC-R19-1).
          .hooks.PreToolUse = (
            (.hooks.PreToolUse // []) as $arr |
            if ($arr | map(.hooks[]?.command? // "") | any(. == $ptu)) then $arr
            else $arr + [{"matcher": $ptm, "hooks": [{"type": "command", "command": $ptu}]}]
            end
          )
          ' "$SETTINGS_JSON")"
      else
        _merged="$(jq \
          --arg ups "$_ups_cmd" \
          --arg ss "$_ss_cmd" \
          --arg m "$_SS_MATCHER" \
          '
          # Append UserPromptSubmit entry only if command not already present.
          .hooks.UserPromptSubmit = (
            (.hooks.UserPromptSubmit // []) as $arr |
            if ($arr | map(.hooks[]?.command? // "") | any(. == $ups)) then $arr
            else $arr + [{"hooks": [{"type": "command", "command": $ups}]}]
            end
          ) |
          # SessionStart UPSERT: heal-our-matcher-in-place if present, else append.
          # (Heals a stale "startup"-only matcher so --force self-heals.)
          .hooks.SessionStart = (
            (.hooks.SessionStart // []) as $arr |
            if ($arr | map(.hooks[]?.command? // "") | any(. == $ss)) then
              ($arr | map(if ((.hooks // []) | any(.command? == $ss)) then (.matcher = $m) else . end))
            else
              $arr + [{"matcher": $m, "hooks": [{"type": "command", "command": $ss}]}]
            end
          )
          ' "$SETTINGS_JSON")"
      fi
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

# ── Wire telemetry Stop shim (--with-telemetry opt-in) ───────────────────
# Only written when --with-telemetry is explicitly passed. Does NOT alter
# the existing UPS/SessionStart/PreToolUse behavior when flag is absent.
if [[ "$WITH_TELEMETRY" == "true" ]]; then
  if printf '%s' ",$_hosts_wired_sorted," | grep -q ",claude-code,"; then
    _tel_stop_path="$HARNESS_SHIM_DIR/claude-code-Stop.sh"
    _tel_stop_cmd="$_tel_stop_path"
    _write_stop_shim "claude-code"
    info "  wrote claude-code-Stop.sh (telemetry Stop shim)"
    _shim_paths="${_shim_paths:+${_shim_paths},}${_tel_stop_path}"
    _register_stop_in_settings "$_tel_stop_cmd" ".claude/settings.json"
  fi
fi

# ── Wire copilot .github/hooks/eidolons.json ─────────────────────────────
# Best-effort sessionStart adapter (R12). Wholly eidolons-owned file.
# sibling .github/hooks/*.json files (user-managed) are not touched.
if printf '%s' ",$_hosts_wired_sorted," | grep -q ",copilot,"; then
  warn "Copilot sessionStart additionalContext may be dropped by the Copilot CLI (upstream bug #2142); the cloud-agent path is unverified. Per-prompt injection is not possible (userPromptSubmitted output is unprocessed, copilot-cli#1139)."
  mkdir -p .github/hooks
  COPILOT_HOOKS=".github/hooks/eidolons.json"
  _copilot_ss_cmd="$HARNESS_SHIM_DIR/copilot-SessionStart.sh"
  _copilot_json="$(jq -n \
    --arg ss "$_copilot_ss_cmd" \
    '{"version": 1, "hooks": {"sessionStart": [{"type": "command", "bash": $ss, "timeoutSec": 10}]}}')"

  _existing_copilot="$(jq -cS . "$COPILOT_HOOKS" 2>/dev/null || echo "")"
  _new_copilot="$(printf '%s' "$_copilot_json" | jq -cS . 2>/dev/null || echo "")"
  if [[ "$_existing_copilot" != "$_new_copilot" ]]; then
    printf '%s\n' "$_copilot_json" > "$COPILOT_HOOKS"
    ok "Wrote .github/hooks/eidolons.json"
  else
    info ".github/hooks/eidolons.json already up-to-date (no-op)"
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
  _codex_ptu_cmd="$HARNESS_SHIM_DIR/codex-PreToolUse.sh"

  if [[ "$STRICT" == "true" ]] && printf '%s' ",$_strict_hosts," | grep -q ",codex,"; then
    # Strict codex: add PreToolUse entry (R20 AC-R20-1).
    _codex_json="$(jq -n \
      --arg ups "$_codex_ups_cmd" \
      --arg ss "$_codex_ss_cmd" \
      --arg ptu "$_codex_ptu_cmd" \
      '{"hooks": {"UserPromptSubmit": [{"command": $ups}], "SessionStart": [{"command": $ss}], "PreToolUse": [{"command": $ptu}]}}')"
  else
    _codex_json="$(jq -n \
      --arg ups "$_codex_ups_cmd" \
      --arg ss "$_codex_ss_cmd" \
      '{"hooks": {"UserPromptSubmit": [{"command": $ups}], "SessionStart": [{"command": $ss}]}}')"
  fi

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

  # Build strict: and protect: YAML sections (only when strict mode active).
  _strict_yaml_section=""
  if [[ "$STRICT" == "true" ]] && [[ -n "$_strict_hosts" ]]; then
    _strict_hosts_yaml=""
    for _sh in $(printf '%s' "$_strict_hosts" | tr ',' '\n' | sort); do
      [[ -z "$_sh" ]] && continue
      _strict_hosts_yaml="${_strict_hosts_yaml}    - $_sh
"
    done
    _strict_yaml_section="$(printf '  strict:\n%s  strict_modes:\n%b  protect:\n' \
      "$_strict_hosts_yaml" "$_strict_modes_yaml")"
    # Append protect globs (may be empty list).
    if [[ -n "$_protect_globs" ]]; then
      _protect_globs_yaml=""
      while IFS= read -r _pg; do
        [[ -z "$_pg" ]] && continue
        _protect_globs_yaml="${_protect_globs_yaml}    - \"${_pg}\"
"
      done <<EOF
$_protect_globs
EOF
      _strict_yaml_section="${_strict_yaml_section}${_protect_globs_yaml}"
    fi
  fi

  # Build the new harness block text.
  _new_harness_block="$(printf 'harness:\n  schema_version: 1\n  hosts_wired:\n%s  shim_paths:\n%s%s' \
    "$_hosts_yaml" "$_shims_yaml" "$_strict_yaml_section")"

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
