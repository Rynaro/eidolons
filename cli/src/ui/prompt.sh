#!/usr/bin/env bash
# cli/src/ui/prompt.sh — interactive prompt primitives.
#
# Wraps `read -rp` with a consistent visual style and centralises the
# behaviour every subcommand wants:
#
#   - prompt + reply on stderr (so functions whose stdout is captured by
#     the caller — see lib.sh — stay clean)
#   - cozy palette (amber prompt char, primary-coloured prompt text)
#   - graceful fallback when `read` is interrupted (Ctrl-C / EOF)
#
# Public API:
#   ui_confirm <question> [default-y|default-n]   → returns 0 (yes) / 1 (no)
#   ui_input   <prompt>   [default-value]          → echoes reply on stdout
#
# Optional uplift: when `gum` is available on PATH, ui_confirm/ui_input
# defer to gum for richer interaction. The default path stays
# dependency-free and identical to the historical `read -rp` UX.
# ═══════════════════════════════════════════════════════════════════════════

[[ "${EIDOLONS_UI_PROMPT_LOADED:-0}" == "1" ]] && return 0
EIDOLONS_UI_PROMPT_LOADED=1

_ui_prompt_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$_ui_prompt_dir/theme.sh"
# shellcheck disable=SC1091
. "$_ui_prompt_dir/glyphs.sh"
unset _ui_prompt_dir

# Build the visible prompt prefix once. Plain mode → no color, no glyph.
_ui_prompt_prefix() {
  if [[ "${EIDOLONS_FANCY:-0}" == "1" ]]; then
    printf '%s%s%s ' "${UI_ACCENT}" "${GLYPH_BULLET}" "${RESET}"
  fi
}

# ─── Confirm (yes/no) ────────────────────────────────────────────────────
# Returns exit 0 for yes, 1 for no. Default applies on empty reply, EOF,
# or interrupt — so non-interactive callers should set EIDOLONS_NON_INTERACTIVE=1
# (or check upstream); this helper does NOT honour that env itself, on
# purpose, to stay single-responsibility.
ui_confirm() {
  local question="$1"
  local default="${2:-default-n}"
  local hint reply

  case "$default" in
    default-y) hint="[Y/n]" ;;
    default-n) hint="[y/N]" ;;
    *)         hint="[y/n]" ;;
  esac

  if command -v gum >/dev/null 2>&1 && [[ "${EIDOLONS_FANCY:-0}" == "1" ]]; then
    if [[ "$default" == "default-y" ]]; then
      gum confirm --default=true  "$question" && return 0 || return 1
    else
      gum confirm --default=false "$question" && return 0 || return 1
    fi
  fi

  local prefix; prefix="$(_ui_prompt_prefix)"
  printf '%s%s %s ' "$prefix" "$question" "$hint" >&2
  read -r reply || reply=""
  reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

  case "$reply" in
    y|yes) return 0 ;;
    n|no)  return 1 ;;
    "")    [[ "$default" == "default-y" ]] && return 0 || return 1 ;;
    *)     [[ "$default" == "default-y" ]] && return 0 || return 1 ;;
  esac
}

# ─── Free-text input ─────────────────────────────────────────────────────
# Echoes the reply on stdout. Empty reply → echoes the default (or empty
# string when no default given).
ui_input() {
  local question="$1"
  local default="${2:-}"
  local reply

  if command -v gum >/dev/null 2>&1 && [[ "${EIDOLONS_FANCY:-0}" == "1" ]]; then
    if [[ -n "$default" ]]; then
      gum input --placeholder "$question" --value "$default"
    else
      gum input --placeholder "$question"
    fi
    return $?
  fi

  local prefix; prefix="$(_ui_prompt_prefix)"
  if [[ -n "$default" ]]; then
    printf '%s%s [%s]: ' "$prefix" "$question" "$default" >&2
  else
    printf '%s%s: ' "$prefix" "$question" >&2
  fi
  read -r reply || reply=""
  if [[ -z "$reply" && -n "$default" ]]; then
    reply="$default"
  fi
  printf '%s\n' "$reply"
}
