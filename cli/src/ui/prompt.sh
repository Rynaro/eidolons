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
#   ui_confirm    <question> [default-y|default-n]   → returns 0 (yes) / 1 (no)
#   ui_input      <prompt>   [default-value]          → echoes reply on stdout
#   ui_pick_hosts <default-csv>                       → echoes chosen host CSV
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

# ─── Letter-shortcut host picker ────────────────────────────────────────
# ui_pick_hosts <default-csv> → echoes chosen CSV on stdout, menu on stderr.
#
# Mirrors ui_confirm's [Y/n] style for vendor selection. Each host has a
# unique mnemonic letter; pressing Enter accepts the (auto-detected)
# default. Multi-letter input picks multiple hosts at once.
#
#   c → claude-code   x → codex      o → copilot
#   u → cursor        p → opencode   a → all
#
# Input parsing:
#   empty                     → default-csv (caller decides whether empty
#                               is fatal — matches today's "abort on blank")
#   contains ',' or '-'       → comma-separated full names
#   otherwise                 → letter sequence, deduped in order
#
# Unknown letter or unknown name → die with a one-line hint. Single-shot
# (no reprompt loop) — keeps the function pure and matches the rest of
# the CLI's "fail fast and re-run" style.
ui_pick_hosts() {
  local default_csv="${1:-}"
  local default_letters=""
  local hint reply

  default_letters="$(_ui_hosts_csv_to_letters "$default_csv")"
  if [[ -n "$default_letters" ]]; then
    hint="[$(printf '%s' "$default_letters" | tr '[:lower:]' '[:upper:]')]"
  else
    hint=""
  fi

  {
    printf '\n'
    printf '  %s   %s   %s   %s   %s   %s\n' \
      "$(_ui_host_label c claude-code "$default_csv")" \
      "$(_ui_host_label x codex       "$default_csv")" \
      "$(_ui_host_label o copilot     "$default_csv")" \
      "$(_ui_host_label u cursor      "$default_csv")" \
      "$(_ui_host_label p opencode    "$default_csv")" \
      "$(_ui_host_label a all         "")"
    printf '\n'
  } >&2

  local prefix; prefix="$(_ui_prompt_prefix)"
  if [[ -n "$hint" ]]; then
    printf '%sHosts %s: ' "$prefix" "$hint" >&2
  else
    printf '%sHosts: ' "$prefix" >&2
  fi
  read -r reply || reply=""
  reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

  if [[ -z "$reply" ]]; then
    printf '%s\n' "$default_csv"
    return 0
  fi

  case "$reply" in
    *,*|*-*)
      local token out=""
      local IFS=','
      # shellcheck disable=SC2086
      set -- $reply
      for token in "$@"; do
        token="$(printf '%s' "$token" | tr -d '[:space:]')"
        [[ -z "$token" ]] && continue
        case "$token" in
          claude-code|codex|copilot|cursor|opencode|all) ;;
          *) die "Unknown host '$token'. Valid: claude-code, codex, copilot, cursor, opencode, all (or letters c x o u p a)." ;;
        esac
        if [[ -z "$out" ]]; then out="$token"; else out="$out,$token"; fi
      done
      printf '%s\n' "$out"
      return 0
      ;;
  esac

  local i ch host out=""
  for (( i=0; i<${#reply}; i++ )); do
    ch="${reply:$i:1}"
    case "$ch" in
      c) host="claude-code" ;;
      x) host="codex" ;;
      o) host="copilot" ;;
      u) host="cursor" ;;
      p) host="opencode" ;;
      a)
        printf '%s\n' "all"
        return 0
        ;;
      *) die "Unknown host letter '$ch'. Valid letters: c (claude-code), x (codex), o (copilot), u (cursor), p (opencode), a (all)." ;;
    esac
    case ",$out," in
      *",$host,"*) : ;;  # already picked
      *) if [[ -z "$out" ]]; then out="$host"; else out="$out,$host"; fi ;;
    esac
  done
  printf '%s\n' "$out"
}

# Render one host menu entry, e.g. "(C)laude Code". When the host is in
# the default set, the letter is uppercased; otherwise lowercased. Bash
# 3.2 safe (no ${var^^}).
_ui_host_label() {
  local letter="$1" host="$2" default_csv="${3:-}"
  local upper lower L
  upper="$(printf '%s' "$letter" | tr '[:lower:]' '[:upper:]')"
  lower="$(printf '%s' "$letter" | tr '[:upper:]' '[:lower:]')"
  L="$lower"
  case ",$default_csv," in
    *",$host,"*) L="$upper" ;;
  esac
  case "$host" in
    claude-code) printf '(%s)laude Code' "$L" ;;
    codex)       printf 'Code(%s)'       "$L" ;;
    copilot)     printf 'c(%s)pilot'     "$L" ;;
    cursor)      printf 'c(%s)rsor'      "$L" ;;
    opencode)    printf 'o(%s)encode'    "$L" ;;
    all)         printf '(%s)ll'         "$upper" ;;
  esac
}

# Map a CSV of host names to a string of letters, in a stable order
# (c x o u p). Unknown tokens are skipped silently — caller validates.
_ui_hosts_csv_to_letters() {
  local csv="${1:-}"
  [[ -z "$csv" ]] && { printf ''; return 0; }
  local letters=""
  case ",$csv," in *",claude-code,"*) letters="${letters}c" ;; esac
  case ",$csv," in *",codex,"*)       letters="${letters}x" ;; esac
  case ",$csv," in *",copilot,"*)     letters="${letters}o" ;; esac
  case ",$csv," in *",cursor,"*)      letters="${letters}u" ;; esac
  case ",$csv," in *",opencode,"*)    letters="${letters}p" ;; esac
  printf '%s' "$letters"
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
