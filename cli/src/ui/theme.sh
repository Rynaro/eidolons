#!/usr/bin/env bash
# cli/src/ui/theme.sh — capability detection + color/glyph palette.
#
# Sourced by lib.sh exactly once. Decides at source time whether the
# current invocation can render fancy output (ANSI colors, Unicode box
# drawing, sigils) or must degrade to plain text.
#
# Single source of truth for:
#   - EIDOLONS_FANCY (1 = fancy, 0 = plain)
#   - color variables (BOLD, DIM, GREEN, YELLOW, RED, BLUE, CYAN,
#     AMBER, MUTED, RESET) — empty strings in plain mode
#   - palette role aliases (UI_PRIMARY, UI_SUCCESS, UI_INFO, UI_WARN,
#     UI_ERROR, UI_ACCENT) — what subcommands actually use
#
# All other UI modules read these and never re-detect terminal state.
# ═══════════════════════════════════════════════════════════════════════════

# Re-source guard — sourced by lib.sh and possibly by individual modules.
[[ "${EIDOLONS_UI_THEME_LOADED:-0}" == "1" ]] && return 0
EIDOLONS_UI_THEME_LOADED=1

# ─── Capability detection ─────────────────────────────────────────────────
# Fancy mode requires:
#   1. stderr is a TTY (we write log output to fd 2 — see lib.sh).
#   2. NO_COLOR is unset (https://no-color.org/).
#   3. CI is unset (most CIs strip ANSI from logs anyway).
#   4. EIDOLONS_PLAIN is not "1" (manual override).
# FORCE_COLOR=1 overrides #1 (useful for previews piped to less -R).
_eidolons_detect_fancy() {
  if [[ "${EIDOLONS_PLAIN:-0}" == "1" ]]; then
    return 1
  fi
  if [[ -n "${NO_COLOR:-}" ]]; then
    return 1
  fi
  if [[ "${FORCE_COLOR:-0}" == "1" ]]; then
    return 0
  fi
  if [[ -n "${CI:-}" ]]; then
    return 1
  fi
  if [[ -t 2 ]]; then
    return 0
  fi
  return 1
}

if _eidolons_detect_fancy; then
  EIDOLONS_FANCY=1
else
  EIDOLONS_FANCY=0
fi
export EIDOLONS_FANCY

# ─── Color depth (256 vs 8) ───────────────────────────────────────────────
# tput is portable; missing tput just means we stick with 8-color.
EIDOLONS_COLOR_DEPTH=8
if [[ "$EIDOLONS_FANCY" == "1" ]] && command -v tput >/dev/null 2>&1; then
  _depth="$(tput colors 2>/dev/null || echo 8)"
  if [[ "$_depth" =~ ^[0-9]+$ ]] && [[ "$_depth" -ge 256 ]]; then
    EIDOLONS_COLOR_DEPTH=256
  fi
  unset _depth
fi
export EIDOLONS_COLOR_DEPTH

# ─── Palette ──────────────────────────────────────────────────────────────
# Themes are selected via EIDOLONS_THEME (default: "default" = cozy CRT).
# Each theme sets the role aliases (UI_PRIMARY etc) and may override the
# named color vars. Plain mode skips theme loading entirely — every var
# stays empty string.
BOLD=""; DIM=""
GREEN=""; YELLOW=""; RED=""; BLUE=""; CYAN=""
AMBER=""; MUTED=""
RESET=""

UI_PRIMARY=""; UI_SUCCESS=""; UI_INFO=""; UI_WARN=""; UI_ERROR=""; UI_ACCENT=""; UI_MUTED=""

if [[ "$EIDOLONS_FANCY" == "1" ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RESET=$'\033[0m'

  # Base 8-color (always available when fancy is on).
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
  BLUE=$'\033[34m'
  CYAN=$'\033[36m'

  _theme_dir="$(dirname "${BASH_SOURCE[0]}")/themes"
  _theme="${EIDOLONS_THEME:-default}"
  if [[ -f "$_theme_dir/${_theme}.sh" ]]; then
    # shellcheck disable=SC1090
    . "$_theme_dir/${_theme}.sh"
  else
    # Unknown theme name → fall back to default. Don't fail; theming is cosmetic.
    # shellcheck disable=SC1091
    . "$_theme_dir/default.sh"
  fi
  unset _theme _theme_dir
fi
