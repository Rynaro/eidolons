#!/usr/bin/env bash
# cli/src/ui/glyphs.sh — box-drawing characters and status icons.
#
# In fancy mode these are Unicode box-drawing chars (U+2500 block) and
# Unicode status symbols. In plain mode they degrade to ASCII so output
# stays readable in pipes, log aggregators, and terminals without UTF-8.
#
# Three box sets ship: SINGLE (light line), DOUBLE (heavy authority),
# ROUNDED (cozy info). Subcommands pick which one fits the context;
# none "wins" by default.
# ═══════════════════════════════════════════════════════════════════════════

[[ "${EIDOLONS_UI_GLYPHS_LOADED:-0}" == "1" ]] && return 0
EIDOLONS_UI_GLYPHS_LOADED=1

if [[ "${EIDOLONS_FANCY:-0}" == "1" ]]; then
  # ─── Single line ────────────────────────────────────────────────────────
  GLYPH_S_H="─"; GLYPH_S_V="│"
  GLYPH_S_TL="┌"; GLYPH_S_TR="┐"; GLYPH_S_BL="└"; GLYPH_S_BR="┘"
  GLYPH_S_T="┬"; GLYPH_S_B="┴"; GLYPH_S_L="├"; GLYPH_S_R="┤"; GLYPH_S_X="┼"

  # ─── Double line ────────────────────────────────────────────────────────
  GLYPH_D_H="═"; GLYPH_D_V="║"
  GLYPH_D_TL="╔"; GLYPH_D_TR="╗"; GLYPH_D_BL="╚"; GLYPH_D_BR="╝"
  GLYPH_D_T="╦"; GLYPH_D_B="╩"; GLYPH_D_L="╠"; GLYPH_D_R="╣"; GLYPH_D_X="╬"

  # ─── Rounded ────────────────────────────────────────────────────────────
  # Same horizontals/verticals as single, just rounded corners.
  GLYPH_R_H="─"; GLYPH_R_V="│"
  GLYPH_R_TL="╭"; GLYPH_R_TR="╮"; GLYPH_R_BL="╰"; GLYPH_R_BR="╯"

  # ─── Status icons ───────────────────────────────────────────────────────
  # Mirrored from the historical lib.sh set. Tests pin these characters.
  GLYPH_PROGRESS="▸"
  GLYPH_OK="✓"
  GLYPH_INFO="·"
  GLYPH_WARN="⚠"
  GLYPH_ERROR="✗"

  # ─── Misc ───────────────────────────────────────────────────────────────
  GLYPH_BULLET="•"
  GLYPH_ARROW_UP="↑"
  GLYPH_ARROW_DOWN="↓"
  GLYPH_ARROW_RIGHT="→"
  GLYPH_DOT="·"
else
  # Plain mode — ASCII fallback. Box chars become "+" / "-" / "|" so
  # the layout still parses visually. Status icons keep the historical
  # symbols when stderr happens to be a non-TTY but UTF-8 capable; tests
  # specifically assert these substrings, so we keep them as-is.
  GLYPH_S_H="-"; GLYPH_S_V="|"
  GLYPH_S_TL="+"; GLYPH_S_TR="+"; GLYPH_S_BL="+"; GLYPH_S_BR="+"
  GLYPH_S_T="+"; GLYPH_S_B="+"; GLYPH_S_L="+"; GLYPH_S_R="+"; GLYPH_S_X="+"

  GLYPH_D_H="="; GLYPH_D_V="|"
  GLYPH_D_TL="+"; GLYPH_D_TR="+"; GLYPH_D_BL="+"; GLYPH_D_BR="+"
  GLYPH_D_T="+"; GLYPH_D_B="+"; GLYPH_D_L="+"; GLYPH_D_R="+"; GLYPH_D_X="+"

  GLYPH_R_H="-"; GLYPH_R_V="|"
  GLYPH_R_TL="+"; GLYPH_R_TR="+"; GLYPH_R_BL="+"; GLYPH_R_BR="+"

  # Status icons stay Unicode — tests pin these and they're harmless in pipes.
  GLYPH_PROGRESS="▸"
  GLYPH_OK="✓"
  GLYPH_INFO="·"
  GLYPH_WARN="⚠"
  GLYPH_ERROR="✗"

  GLYPH_BULLET="*"
  GLYPH_ARROW_UP="^"
  GLYPH_ARROW_DOWN="v"
  GLYPH_ARROW_RIGHT="->"
  GLYPH_DOT="."
fi
