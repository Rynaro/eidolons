#!/usr/bin/env bash
# cli/src/ui/panel.sh — banners, section panels, dividers.
#
# Output destination: stderr. Same invariant as lib.sh's logging helpers
# — captured stdout (e.g. fetch_eidolon) must stay clean.
#
# Public API:
#   ui_banner [version]            top-of-CLI wordmark + tagline
#   ui_section <title>             rule + bold title (open a visual group)
#   ui_section_end                 closing rule (optional pair for ui_section)
#   ui_divider                     plain horizontal rule, full width
#   ui_kv <key> <value>            two-column "  key  value" pair
#
# All helpers degrade safely when EIDOLONS_FANCY=0: ui_banner prints
# `eidolons vX.Y.Z`, ui_section prints `=== Title ===`, etc. — no
# Unicode, no ANSI, identical informational content.
# ═══════════════════════════════════════════════════════════════════════════

[[ "${EIDOLONS_UI_PANEL_LOADED:-0}" == "1" ]] && return 0
EIDOLONS_UI_PANEL_LOADED=1

# Dependencies — these guard against double-load themselves.
_ui_panel_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$_ui_panel_dir/theme.sh"
# shellcheck disable=SC1091
. "$_ui_panel_dir/glyphs.sh"
unset _ui_panel_dir

# ─── Width detection ──────────────────────────────────────────────────────
# Used by dividers and section rules. Capped at 78 so output stays
# readable on wide terminals; floored at 40 so narrow terminals don't
# produce broken art.
_ui_width() {
  local w="${COLUMNS:-0}"
  if [[ "$w" -le 0 ]] && command -v tput >/dev/null 2>&1; then
    w="$(tput cols 2>/dev/null || echo 0)"
  fi
  [[ "$w" -le 0 ]] && w=72
  [[ "$w" -gt 78 ]] && w=78
  [[ "$w" -lt 40 ]] && w=40
  echo "$w"
}

# Repeat a single character N times. Bash 3.2 compatible (no `printf '%.0sX'`
# trick portability concern — that one happens to work in bash 3.2 but
# is fragile; we use a simple loop instead).
_ui_repeat() {
  local char="$1" count="$2" out=""
  while [[ "$count" -gt 0 ]]; do
    out="${out}${char}"
    count=$((count - 1))
  done
  printf '%s' "$out"
}

# ─── Banner ───────────────────────────────────────────────────────────────
# Reads art/banner.txt from the nexus checkout when available. Falls back
# to a minimal text banner when the art file is missing or fancy mode is
# off — which is exactly what bats sees, keeping `eidolons --help` test
# assertions stable.
ui_banner() {
  local version="${1:-${EIDOLONS_VERSION:-}}"
  if [[ "${EIDOLONS_FANCY:-0}" != "1" ]]; then
    return 0
  fi

  local nexus="${NEXUS:-${EIDOLONS_NEXUS:-}}"
  local banner_file=""
  if [[ -n "$nexus" && -f "$nexus/art/banner.txt" ]]; then
    banner_file="$nexus/art/banner.txt"
  fi

  printf '\n' >&2
  if [[ -n "$banner_file" ]]; then
    # Color the whole banner amber. ANSI prefix per line keeps colors
    # from bleeding past it into subsequent output.
    while IFS= read -r line; do
      printf '%s%s%s\n' "${UI_ACCENT}" "$line" "${RESET}" >&2
    done < "$banner_file"
  else
    printf '%s%seidolons%s\n' "${BOLD}" "${UI_ACCENT}" "${RESET}" >&2
  fi
  if [[ -n "$version" ]]; then
    printf '  %sv%s%s  %s· personal team of AI agents%s\n' \
      "${UI_MUTED}" "$version" "${RESET}" \
      "${UI_MUTED}" "${RESET}" >&2
  fi
  printf '\n' >&2
}

# ─── Section header ───────────────────────────────────────────────────────
# Renders:  ── Title ─────────────────────────────────
# Used by doctor/sync/init to visually group streaming output.
ui_section() {
  local title="$*"
  local w; w="$(_ui_width)"
  if [[ "${EIDOLONS_FANCY:-0}" != "1" ]]; then
    # ASCII fallback — preserves the title substring tests assert on.
    printf '\n=== %s ===\n' "$title" >&2
    return 0
  fi
  local title_len=${#title}
  local prefix_rule=2
  local trailing=$((w - title_len - prefix_rule - 2))   # -2 for spaces around title
  [[ "$trailing" -lt 2 ]] && trailing=2
  local left right
  left="$(_ui_repeat "$GLYPH_R_H" "$prefix_rule")"
  right="$(_ui_repeat "$GLYPH_R_H" "$trailing")"
  printf '\n%s%s %s%s%s %s%s\n' \
    "${UI_PRIMARY}" "$left" \
    "${BOLD}${UI_ACCENT}" "$title" "${RESET}" \
    "${UI_PRIMARY}${right}" "${RESET}" >&2
}

# Optional closer for a ui_section — symmetry only, no state tracking.
ui_section_end() {
  ui_divider
}

# Same as ui_section but writes to stdout. Use this for "report" output
# (doctor checks, sync preview) where the section header should land in
# the same stream as the data the user is piping or capturing. The
# stderr variant is for log-context group headers.
ui_section_out() {
  local title="$*"
  local w; w="$(_ui_width)"
  if [[ "${EIDOLONS_FANCY:-0}" != "1" ]]; then
    printf '\n=== %s ===\n' "$title"
    return 0
  fi
  local title_len=${#title}
  local prefix_rule=2
  local trailing=$((w - title_len - prefix_rule - 2))
  [[ "$trailing" -lt 2 ]] && trailing=2
  local left right
  left="$(_ui_repeat "$GLYPH_R_H" "$prefix_rule")"
  right="$(_ui_repeat "$GLYPH_R_H" "$trailing")"
  printf '\n%s%s %s%s%s %s%s\n' \
    "${UI_PRIMARY}" "$left" \
    "${BOLD}${UI_ACCENT}" "$title" "${RESET}" \
    "${UI_PRIMARY}${right}" "${RESET}"
}

# ─── Divider ──────────────────────────────────────────────────────────────
ui_divider() {
  local w; w="$(_ui_width)"
  if [[ "${EIDOLONS_FANCY:-0}" != "1" ]]; then
    _ui_repeat "-" "$w" >&2
    printf '\n' >&2
    return 0
  fi
  printf '%s' "${UI_MUTED}" >&2
  _ui_repeat "$GLYPH_R_H" "$w" >&2
  printf '%s\n' "${RESET}" >&2
}

# ─── Key/value row ────────────────────────────────────────────────────────
# Two-column aligned line used inside section bodies. Key gets a fixed
# 14-col gutter so consecutive ui_kv calls line up.
ui_kv() {
  local key="$1"; shift
  local val="$*"
  if [[ "${EIDOLONS_FANCY:-0}" != "1" ]]; then
    printf '  %-14s %s\n' "$key" "$val" >&2
    return 0
  fi
  printf '  %s%-14s%s %s\n' "${UI_MUTED}" "$key" "${RESET}" "$val" >&2
}
