#!/usr/bin/env bash
# cli/src/ui/themes/default.sh — "cozy CRT" palette.
#
# Warm tertiaries that read like a JRPG menu under amber phosphor — not
# the bright primary 8-color VGA palette. When the terminal supports 256
# colors we use the warmer xterm-256 codes; otherwise we fall back to
# the standard 8-color names already set in theme.sh.
# ═══════════════════════════════════════════════════════════════════════════

if [[ "${EIDOLONS_COLOR_DEPTH:-8}" -ge 256 ]]; then
  # 256-color cozy palette
  AMBER=$'\033[38;5;179m'   # warm amber — primary brand
  MUTED=$'\033[38;5;243m'   # dusty grey — secondary text

  UI_PRIMARY=$'\033[38;5;179m'   # amber
  UI_SUCCESS=$'\033[38;5;108m'   # soft sage green
  UI_INFO=$'\033[38;5;67m'       # dusty blue
  UI_WARN=$'\033[38;5;180m'      # warm yellow
  UI_ERROR=$'\033[38;5;167m'     # muted red
  UI_ACCENT=$'\033[38;5;214m'    # bright amber accent (titles, sigils)
  UI_MUTED="$MUTED"
else
  # 8-color fallback — reuse the named ANSI colors theme.sh already set.
  AMBER="$YELLOW"
  MUTED="$DIM"

  UI_PRIMARY="$YELLOW"
  UI_SUCCESS="$GREEN"
  UI_INFO="$BLUE"
  UI_WARN="$YELLOW"
  UI_ERROR="$RED"
  UI_ACCENT="$CYAN"
  UI_MUTED="$DIM"
fi
