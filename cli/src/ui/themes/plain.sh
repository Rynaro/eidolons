#!/usr/bin/env bash
# cli/src/ui/themes/plain.sh — explicit no-color theme.
#
# Selected via EIDOLONS_THEME=plain when fancy mode is otherwise on
# (e.g. user wants Unicode box drawing but no colors). All role aliases
# resolve to empty strings; named color vars stay at whatever theme.sh
# set. Practical use: piping into a colorblind-friendly viewer.
# ═══════════════════════════════════════════════════════════════════════════

AMBER=""
MUTED=""

UI_PRIMARY=""
UI_SUCCESS=""
UI_INFO=""
UI_WARN=""
UI_ERROR=""
UI_ACCENT=""
UI_MUTED=""
