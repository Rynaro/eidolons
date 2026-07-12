#!/usr/bin/env bash
# cli/src/statusline.sh — 'eidolons statusline render|demo|doctor'
# ═══════════════════════════════════════════════════════════════════════════
#
# A Claude Code statusline command. Two jobs, one of them load-bearing:
#
#   1. FEED THE METER (load-bearing). Claude Code hands a statusline command a
#      JSON payload on stdin carrying `context_window.used_percentage` — exact
#      context telemetry, no estimation. That is ECM's rung-1 source, and
#      `context status --stdin` was built to eat this exact payload
#      (docs/specs/ecm/spec.md §5, Claude Code = T3). Piping it through promotes
#      the meter from estimate_source=unknown to estimate_source=host. Without
#      this, ECM runs blind on its flagship host and every policy rule resolves
#      to the fail-open `continue` floor.
#
#   2. RENDER THE HUD (cosmetic). A two-row Final-Fantasy battle window:
#        row 1  ╭─⟪ job · class ✦ ⟫─ area · branch*dirty ──── gil · exp ─╮
#        row 2  ╰─ ◈ limit-gauge Δ ZONE · party/agent · ▸ quest ─ MP ─╯
#      The context gauge is the limit gauge (HP); the 5-hour rate limit is MP,
#      draining as you cast. Both come straight from the payload.
#
# ── Effects (v2) ───────────────────────────────────────────────────────────
#
#   Every effect is SELF-DECAYING — no timers, no daemons. The statusline
#   re-renders after each assistant message, so an effect fires on the render
#   where its trigger condition holds and decays naturally on the next.
#   Cross-render memory lives in a session-keyed sidecar state file (plain
#   positional lines, same never-source rule as the cache):
#
#     delta popup       ↑n/↓n beside the context % when it moved since the
#                       previous render — damage numbers off the gauge.
#     zone flash        reverse-video zone label on exactly the render where
#                       the zone changed; normal on the next.
#     critical pulse    at critical the label pulses by second-parity; wire
#                       "refreshInterval": 2 and it blinks like the FF
#                       low-HP alarm even while the session idles.
#     quest fanfare     one render of '✓ <quest> COMPLETE!' when the tracked
#                       ESL quest leaves in_progress, then back to normal.
#
# ── Constraints that shaped this file ─────────────────────────────────────
#
#   Fail-open, ALWAYS exit 0. Claude Code blanks the status line on a non-zero
#   exit or empty stdout. Every failure path degrades to a smaller HUD.
#
#   Never source lib.sh. This runs after every assistant message; ECM's CC3
#   budget is ≤ 300 ms. jq + git only.
#
#   Force colour. ui/theme.sh gates ANSI on `[[ -t 2 ]]`, but Claude Code
#   CAPTURES stdout — a TTY probe reports "not a terminal" and the HUD would be
#   permanently colourless. Emit ANSI unconditionally; honour only NO_COLOR.
#
#   Cache git by session_id, never $$. Per the statusline docs, process ids
#   change on every invocation and defeat the cache; session_id is stable for
#   the session's lifetime.
#
#   Measure width from $COLUMNS. `tput cols` cannot see the terminal from inside
#   a statusline script (stdout is a pipe); Claude Code exports COLUMNS instead.
#
#   Glyphs are all East-Asian-narrow. Emoji and Miscellaneous-Symbols chars
#   (⚔ ⛁ ▶) render double-width in many terminals and would break the border
#   alignment, so the palette is restricted to box-drawing + geometric shapes.
#
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

# NOTE: deliberately NOT `set -e`. A statusline that dies renders a blank bar;
# every step here is individually guarded and the script always reaches exit 0.
set -u

# Numeric formatting only. Under a comma-decimal locale (pt_BR, de_DE, fr_FR…)
# `printf '%.2f' 1.2437` misparses the '.' and renders $1,000.00 instead of $1.24.
# Pinning LC_NUMERIC alone fixes that WITHOUT forcing LC_ALL=C, which would make
# ${#var} count bytes instead of characters and wreck the border width maths on
# every multi-byte glyph in the frame.
LC_NUMERIC=C
export LC_NUMERIC

SELF="${BASH_SOURCE[0]}"
SUB="${1:-render}"

case "$SUB" in
  -h|--help)
    cat <<'EOF'
eidolons statusline — Claude Code statusline: FF HUD + ECM rung-1 feed

Usage:
  eidolons statusline render    Read the statusline JSON payload on stdin,
                                feed the ECM meter, print the 2-row HUD.
  eidolons statusline demo      Render a canned five-frame session arc
                                (green → amber flash → dispatch → red →
                                critical pulse) and print the wiring snippet.
  eidolons statusline doctor    Read-only environment check: jq/git presence,
                                settings.json wiring, meter freshness, and one
                                timed render against the 300 ms budget.

Wire it in .claude/settings.json:

  { "statusLine": { "type": "command",
                    "command": "eidolons statusline render",
                    "padding": 0,
                    "refreshInterval": 2 } }

  refreshInterval is optional — it re-runs the render every 2 s so the
  critical-zone pulse animates even while the session idles.

What render does:
  1. Pipes the payload into 'eidolons context status --stdin', promoting the ECM
     meter to estimate_source=host — exact context telemetry, no estimation
     (docs/specs/ecm/spec.md §5, Claude Code = T3). Without a statusline, ECM
     falls back to the bytes/4 transcript heuristic or to zone=unknown.
  2. Renders the HUD: context gauge coloured by ECM zone (green <50 / amber <75
     / red <90 / critical), delta popup since the last render, active ESL quest
     with a one-render COMPLETE fanfare, dispatched Eidolon in its class colour,
     model job title, gil, EXP, and the 5-hour rate limit as a draining MP bar.

Environment:
  NO_COLOR=1                       Emit no ANSI escapes (also disables effects
                                   that are pure SGR, like the zone flash).
  COLUMNS=<n>                      Frame width (Claude Code exports this).
  EIDOLONS_STATUSLINE_NO_METER=1   Render only; do not write the ECM meter.

Exit: render always exits 0 (fail-open — a non-zero exit blanks the Claude Code
status line). demo and doctor also exit 0; doctor never writes anything.
EOF
    exit 0
    ;;
esac

# ─── Glyphs (all single-width) ────────────────────────────────────────────
G_TL="╭"; G_TR="╮"; G_BL="╰"; G_BR="╯"; G_H="─"
G_LB="⟪"; G_RB="⟫"          # job brackets
G_GAUGE="◈"                 # context (limit) gauge sigil
G_FULL="▰"; G_EMPTY="▱"     # bar cells
G_QUEST="▸"                 # active ESL quest
G_DONE="✓"                  # quest-complete fanfare
G_TRANCE="✦"                # deep-reasoning / TRANCE marker
G_UP="↑"; G_DOWN="↓"        # delta popup
G_SEP="·"

BAR_CELLS=10                # HP / limit gauge
MP_CELLS=5                  # MP gauge

# ─── Colour (forced; NO_COLOR honoured) ───────────────────────────────────
if [ -n "${NO_COLOR:-}" ]; then
  C_RESET=""; C_DIM=""; C_BOLD=""; C_FLASH=""
  C_GREEN=""; C_AMBER=""; C_RED=""; C_CRIT=""; C_CYAN=""; C_BLUE=""
  C_FRAME=""; C_GOLD=""; C_WHITE=""; C_PINK=""; C_BGREEN=""
else
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_FLASH=$'\033[7m'
  C_GREEN=$'\033[32m'; C_AMBER=$'\033[33m'; C_RED=$'\033[31m'
  C_CRIT=$'\033[1;35m'; C_CYAN=$'\033[36m'; C_BLUE=$'\033[34m'
  C_FRAME=$'\033[34m'; C_GOLD=$'\033[33m'; C_WHITE=$'\033[1;37m'
  C_PINK=$'\033[1;35m'; C_BGREEN=$'\033[1;32m'
fi

_repeat() {
  # _repeat <n> <char> — bash 3.2 has no ${var:0:n} padding trick for multibyte.
  _rp_n="$1"; _rp_c="$2"; _rp_out=""
  while [ "$_rp_n" -gt 0 ]; do _rp_out="$_rp_out$_rp_c"; _rp_n=$((_rp_n - 1)); done
  printf '%s' "$_rp_out"
}

# ═══ demo ═══════════════════════════════════════════════════════════════
# A canned five-frame session arc, chained through ONE session id so the
# cross-render effects (delta popup, zone flash, MP drain) fire for real —
# the demo exercises the same state machinery as a live session. The meter
# is NOT written (EIDOLONS_STATUSLINE_NO_METER=1): previewing must never
# poison real ECM telemetry.
if [ "$SUB" = "demo" ]; then
  _sid="demo-$$"
  _frame() {
    # _frame <caption> <pct> <cost> <add> <del> <rl5> <extra-json>
    printf '%s── %s ──%s\n' "$C_DIM" "$1" "$C_RESET"
    printf '{"session_id":"%s","cwd":"%s","workspace":{"project_dir":"%s"},"model":{"id":"claude-fable-5","display_name":"Fable 5"},"cost":{"total_cost_usd":%s,"total_lines_added":%s,"total_lines_removed":%s},"context_window":{"used_percentage":%s,"context_window_size":200000},"effort":{"level":"high"},"thinking":{"enabled":true},"rate_limits":{"five_hour":{"used_percentage":%s}}%s}' \
      "$_sid" "$PWD" "$PWD" "$3" "$4" "$5" "$2" "$6" "$7" \
      | EIDOLONS_STATUSLINE_NO_METER=1 bash "$SELF" render
    printf '\n'
  }
  _frame "early session — full headroom, MP fresh"                 18 0.31 42  3   8 ""
  _frame "amber crossing — zone FLASHES once, delta pops the jump" 63 1.24 156 23 21 ""
  _frame "kupo dispatched — the party member takes the row"        71 2.08 210 41 26 ',"agent":{"name":"kupo"}'
  _frame "red zone — externalize is no longer optional"            84 3.77 402 96 38 ""
  _frame "critical — the label pulses; handoff-fresh is imminent"  93 4.51 511 133 47 ',"exceeds_200k_tokens":true'
  printf '%s── wire it ──%s\n' "$C_DIM" "$C_RESET"
  cat <<'EOF'
  Add to .claude/settings.json:

    { "statusLine": { "type": "command",
                      "command": "eidolons statusline render",
                      "padding": 0,
                      "refreshInterval": 2 } }

  refreshInterval: 2 makes the critical pulse blink while the session idles.
EOF
  exit 0
fi

# ═══ doctor ═════════════════════════════════════════════════════════════
# Read-only diagnostics. Never writes anything — not settings.json, not the
# meter, not even its own cache. Always exits 0: doctor reports, humans decide.
if [ "$SUB" = "doctor" ]; then
  printf '%seidolons statusline doctor%s\n' "$C_BOLD" "$C_RESET"

  if command -v jq >/dev/null 2>&1; then
    printf '  %s✓%s jq          %s\n' "$C_GREEN" "$C_RESET" "$(command -v jq)"
  else
    printf '  %s✗%s jq          missing — payload parsing and the meter feed are disabled\n' "$C_RED" "$C_RESET"
  fi

  if command -v git >/dev/null 2>&1; then
    printf '  %s✓%s git         %s\n' "$C_GREEN" "$C_RESET" "$(command -v git)"
  else
    printf '  %s%s%s git         missing — branch/dirty segment will be absent\n' "$C_AMBER" "$G_SEP" "$C_RESET"
  fi

  _settings=".claude/settings.json"
  if [ -f "$_settings" ] && command -v jq >/dev/null 2>&1 \
     && jq -e '.statusLine.command' "$_settings" >/dev/null 2>&1; then
    printf '  %s✓%s statusLine  wired: %s\n' "$C_GREEN" "$C_RESET" "$(jq -r '.statusLine.command' "$_settings" 2>/dev/null)"
    if jq -e '.statusLine.refreshInterval' "$_settings" >/dev/null 2>&1; then
      printf '  %s✓%s refresh     every %ss — critical pulse animates while idle\n' "$C_GREEN" "$C_RESET" "$(jq -r '.statusLine.refreshInterval' "$_settings" 2>/dev/null)"
    else
      printf '  %s%s%s refresh     not set — pulse only alternates per message (add "refreshInterval": 2)\n' "$C_AMBER" "$G_SEP" "$C_RESET"
    fi
  else
    printf '  %s✗%s statusLine  not wired in %s — run: eidolons statusline demo\n' "$C_RED" "$C_RESET" "$_settings"
  fi

  _meter=".eidolons/.context/meter.json"
  if [ -f "$_meter" ] && command -v jq >/dev/null 2>&1; then
    _src="$(jq -r '.estimate_source // "unknown"' "$_meter" 2>/dev/null)"
    _zn="$(jq -r '.zone // "unknown"' "$_meter" 2>/dev/null)"
    _at="$(jq -r '.updated_at // "?"' "$_meter" 2>/dev/null)"
    if [ "$_src" = "host" ]; then
      printf '  %s✓%s ECM meter   estimate_source=host zone=%s (%s) — rung-1, exact telemetry\n' "$C_GREEN" "$C_RESET" "$_zn" "$_at"
    else
      printf '  %s%s%s ECM meter   estimate_source=%s zone=%s — statusline has not fed it yet this session\n' "$C_AMBER" "$G_SEP" "$C_RESET" "$_src" "$_zn"
    fi
  else
    printf '  %s%s%s ECM meter   %s absent — first render this session will create it\n' "$C_AMBER" "$G_SEP" "$C_RESET" "$_meter"
  fi

  # One timed render against the ECM CC3 300 ms budget. date +%%N is GNU-only;
  # on BSD/macOS date it comes back as a literal 'N' — skip the timing rather
  # than report garbage (bash 3.2 target includes macOS system shell).
  _t0="$(date +%s%N 2>/dev/null || printf '')"
  case "$_t0" in
    *N|'')
      printf '  %s%s%s latency     (date +%%N unsupported here — timing skipped)\n' "$C_AMBER" "$G_SEP" "$C_RESET"
      ;;
    *)
      printf '{"session_id":"doctor-probe","context_window":{"used_percentage":42}}' \
        | EIDOLONS_STATUSLINE_NO_METER=1 bash "$SELF" render >/dev/null 2>&1
      _t1="$(date +%s%N)"
      _ms=$(( (_t1 - _t0) / 1000000 ))
      if [ "$_ms" -le 300 ]; then
        printf '  %s✓%s latency     %sms render (ECM CC3 budget 300ms)\n' "$C_GREEN" "$C_RESET" "$_ms"
      else
        printf '  %s✗%s latency     %sms render — over the 300ms CC3 budget\n' "$C_RED" "$C_RESET" "$_ms"
      fi
      ;;
  esac
  exit 0
fi

# ═══ render ═════════════════════════════════════════════════════════════

# ─── Read the payload ─────────────────────────────────────────────────────
PAYLOAD=""
if [ ! -t 0 ]; then PAYLOAD="$(cat 2>/dev/null || printf '')"; fi

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# Defaults — every one of these survives a totally absent/garbage payload.
MODEL="Claude"; MODEL_ID=""; SESSION=""; PROJECT_DIR=""; USED_PCT=""; COST=""
LINES_ADD=""; LINES_DEL=""; AGENT=""; EFFORT=""; THINKING=""; RL5=""; EXCEEDS=""

if [ "$HAVE_JQ" = "1" ] && [ -n "$PAYLOAD" ]; then
  # ONE jq call — a process per field would blow the latency budget. Fields come
  # back one-per-line and are read positionally: never `eval`, never `set --` on
  # payload-derived text. The payload is untrusted input (model names, agent
  # names, cwd all flow from it) and this repo forbids dynamic evaluation of
  # config-shaped data (CLAUDE.md, "No code execution").
  _i=0
  while IFS= read -r _line; do
    _i=$((_i + 1))
    case "$_i" in
      1)  [ -n "$_line" ] && MODEL="$_line" ;;
      2)  SESSION="$_line" ;;
      3)  PROJECT_DIR="$_line" ;;
      4)  USED_PCT="$_line" ;;
      5)  COST="$_line" ;;
      6)  LINES_ADD="$_line" ;;
      7)  LINES_DEL="$_line" ;;
      8)  AGENT="$_line" ;;
      9)  EFFORT="$_line" ;;
      10) THINKING="$_line" ;;
      11) RL5="$_line" ;;
      12) MODEL_ID="$_line" ;;
      13) EXCEEDS="$_line" ;;
    esac
  done <<EOF
$(printf '%s' "$PAYLOAD" | jq -r '
  ( .model.display_name // "Claude" ),
  ( .session_id // "" ),
  ( .workspace.project_dir // .cwd // "" ),
  ( .context_window.used_percentage // "" | tostring ),
  ( .cost.total_cost_usd // "" | tostring ),
  ( .cost.total_lines_added // "" | tostring ),
  ( .cost.total_lines_removed // "" | tostring ),
  ( .agent.name // "" ),
  ( .effort.level // "" ),
  ( .thinking.enabled // "" | tostring ),
  ( .rate_limits.five_hour.used_percentage // "" | tostring ),
  ( .model.id // "" ),
  ( .exceeds_200k_tokens // "" | tostring )
  | gsub("[\n\r\t]"; " ")' 2>/dev/null || printf '')
EOF
fi

[ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] && cd "$PROJECT_DIR" 2>/dev/null

# ─── 1. Feed the ECM meter (rung-1 promotion) ─────────────────────────────
# Resolve the CLI the same way the harness shims do.
_eidolons_bin() {
  if [ -n "${EIDOLONS_NEXUS:-}" ] && [ -x "${EIDOLONS_NEXUS}/cli/eidolons" ]; then
    printf '%s' "${EIDOLONS_NEXUS}/cli/eidolons"
  elif command -v eidolons >/dev/null 2>&1; then
    printf 'eidolons'
  elif [ -x "${EIDOLONS_HOME:-$HOME/.eidolons}/nexus/cli/eidolons" ]; then
    printf '%s' "${EIDOLONS_HOME:-$HOME/.eidolons}/nexus/cli/eidolons"
  else
    return 1
  fi
}

ZONE="unknown"
if [ -n "$PAYLOAD" ] && [ "${EIDOLONS_STATUSLINE_NO_METER:-0}" != "1" ]; then
  _bin="$(_eidolons_bin 2>/dev/null || printf '')"
  if [ -n "$_bin" ]; then
    # Writes .eidolons/.context/meter.json AND echoes it back — one call, both jobs.
    _meter="$(printf '%s' "$PAYLOAD" | "$_bin" context status --stdin --json 2>/dev/null || printf '')"
    if [ -n "$_meter" ] && [ "$HAVE_JQ" = "1" ]; then
      _z="$(printf '%s' "$_meter" | jq -r '.zone // "unknown"' 2>/dev/null || printf 'unknown')"
      [ -n "$_z" ] && ZONE="$_z"
    fi
  fi
fi

# Local fallback: if the kernel was unreachable, derive the zone ourselves from
# the same ladder (spec §3.1: green <0.50 ≤ amber <0.75 ≤ red <0.90 ≤ critical).
# The HUD must never show `unknown` just because the CLI is missing.
_pct_int=""
case "$USED_PCT" in
  ''|*[!0-9.]*) _pct_int="" ;;
  *) _pct_int="${USED_PCT%%.*}" ;;
esac
if [ "$ZONE" = "unknown" ] && [ -n "$_pct_int" ]; then
  if   [ "$_pct_int" -ge 90 ]; then ZONE="critical"
  elif [ "$_pct_int" -ge 75 ]; then ZONE="red"
  elif [ "$_pct_int" -ge 50 ]; then ZONE="amber"
  else                              ZONE="green"
  fi
fi

case "$ZONE" in
  green)    C_ZONE="$C_GREEN" ;;
  amber)    C_ZONE="$C_AMBER" ;;
  red)      C_ZONE="$C_RED" ;;
  critical) C_ZONE="$C_CRIT" ;;
  *)        C_ZONE="$C_DIM" ;;
esac

# ─── 2. Session-keyed sidecars ────────────────────────────────────────────
# Two files, two lifetimes:
#   .cache — the slow reads (git, ESL quest, roster), 5 s TTL.
#   .state — last render's pct/zone/quest, read EVERY render, written EVERY
#            render. This is what makes the effects self-decaying: the trigger
#            is always "current differs from previous", and writing the current
#            values is itself what disarms the effect for the next render.
# Docs: cache git; key on session_id because $$ changes every invocation.
_cache_dir="${TMPDIR:-/tmp}"
_cache_key="$(printf '%s' "${SESSION:-nosession}" | tr -cd 'A-Za-z0-9_-')"
[ -n "$_cache_key" ] || _cache_key="nosession"
CACHE="$_cache_dir/eidolons-statusline-$_cache_key.cache"
STATE="$_cache_dir/eidolons-statusline-$_cache_key.state"
CACHE_TTL=5

_cache_fresh() {
  [ -f "$CACHE" ] || return 1
  _now="$(date +%s 2>/dev/null || printf '0')"
  _mt="$(stat -c %Y "$CACHE" 2>/dev/null || stat -f %m "$CACHE" 2>/dev/null || printf '0')"
  [ "$_now" -gt 0 ] && [ "$_mt" -gt 0 ] || return 1
  [ $((_now - _mt)) -lt "$CACHE_TTL" ]
}

BRANCH=""; DIRTY="0"; QUEST=""; QUEST_STATE=""; PARTY=""

if _cache_fresh; then
  # Read positionally — NEVER source. A branch name is attacker-shaped input
  # (`git checkout -b '$(rm -rf ~)'` is legal) and sourcing it would execute it.
  _i=0
  while IFS= read -r _line; do
    _i=$((_i + 1))
    case "$_i" in
      1) BRANCH="$_line" ;;
      2) DIRTY="$_line" ;;
      3) QUEST="$_line" ;;
      4) QUEST_STATE="$_line" ;;
      5) PARTY="$_line" ;;
    esac
  done < "$CACHE"
else
  BRANCH="$(git branch --show-current 2>/dev/null || printf '')"
  if [ -n "$BRANCH" ]; then
    # NOT `grep -c .`: it prints "0" AND exits 1 on no match, so a `|| printf 0`
    # fallback fires too and concatenates into "00" — which is != "0" and paints
    # a dirty marker on a clean tree. wc -l has no such exit-code trap.
    DIRTY="$(git status --porcelain 2>/dev/null | wc -l 2>/dev/null | tr -cd '0-9')"
  fi
  [ -n "$DIRTY" ] || DIRTY="0"
  # Strip leading zeros so "007" never reads as a different number than 7.
  DIRTY="$(printf '%s' "$DIRTY" | sed 's/^0*\([0-9]\)$/\1/; s/^0*\([1-9]\)/\1/')"

  # Active ESL quest — first in_progress change, else proposed, else verified.
  if [ "$HAVE_JQ" = "1" ] && [ -d ".spectra/changes" ]; then
    for _st in in_progress proposed verified; do
      [ -n "$QUEST" ] && break
      for _cj in .spectra/changes/*/change.json; do
        [ -f "$_cj" ] || continue
        _s="$(jq -r '.status // ""' "$_cj" 2>/dev/null || printf '')"
        if [ "$_s" = "$_st" ]; then
          QUEST="$(jq -r '.change_id // ""' "$_cj" 2>/dev/null || printf '')"
          QUEST_STATE="$_s"
          break
        fi
      done
    done
  fi

  # Party size — members locked into this project.
  if [ -f "eidolons.lock" ]; then
    PARTY="$(grep -c '^  - name:' eidolons.lock 2>/dev/null || printf '')"
    PARTY="$(printf '%s' "$PARTY" | tr -cd '0-9')"
  fi

  # Plain positional lines, in the same order the reader above expects. No shell
  # syntax in the cache means nothing in it can ever be executed.
  # 2>/dev/null comes FIRST: redirects apply left-to-right, so with the order
  # reversed a failing `>` (unwritable TMPDIR) prints its error BEFORE stderr is
  # silenced — and that leak lands in the captured statusline output.
  {
    printf '%s\n' "$BRANCH" "$DIRTY" "$QUEST" "$QUEST_STATE" "$PARTY"
  } 2>/dev/null > "$CACHE" || true
fi

# ─── 3. Effects — read previous render, compute triggers, persist current ──
PREV_PCT=""; PREV_ZONE=""; PREV_QUEST=""; PREV_QSTATE=""
if [ -f "$STATE" ]; then
  _i=0
  while IFS= read -r _line; do
    _i=$((_i + 1))
    case "$_i" in
      1) PREV_PCT="$_line" ;;
      2) PREV_ZONE="$_line" ;;
      3) PREV_QUEST="$_line" ;;
      4) PREV_QSTATE="$_line" ;;
    esac
  done < "$STATE"
fi

# Delta popup — damage numbers off the gauge. Empty on the first render (no
# previous state) and when the needle didn't move.
DELTA_PLAIN=""; DELTA_COLOR=""
case "$PREV_PCT" in *[!0-9]*|'') PREV_PCT="" ;; esac
if [ -n "$_pct_int" ] && [ -n "$PREV_PCT" ]; then
  _d=$(( _pct_int - PREV_PCT ))
  if [ "$_d" -gt 0 ]; then
    DELTA_PLAIN=" ${G_UP}${_d}"
    DELTA_COLOR=" ${C_DIM}${C_AMBER}${G_UP}${_d}${C_RESET}"
  elif [ "$_d" -lt 0 ]; then
    DELTA_PLAIN=" ${G_DOWN}$(( -_d ))"
    DELTA_COLOR=" ${C_DIM}${C_GREEN}${G_DOWN}$(( -_d ))${C_RESET}"
  fi
fi

# Zone flash — one render of reverse video when the zone CHANGED (both ends
# must be real zones; unknown never flashes). Critical additionally pulses by
# second-parity: with "refreshInterval": 2 wired, that's a real blink; without
# it, it alternates per assistant message. Pure SGR, so NO_COLOR kills it and
# the emitted TEXT is identical either way (width maths untouched).
ZONE_FX=""
case "$PREV_ZONE:$ZONE" in
  *:unknown|unknown:*) : ;;
  "$ZONE:$ZONE") : ;;
  ?*:?*) ZONE_FX="$C_FLASH" ;;
esac
if [ "$ZONE" = "critical" ]; then
  _sec="$(date +%s 2>/dev/null || printf '0')"
  [ $(( _sec % 2 )) -eq 0 ] && ZONE_FX="$C_FLASH"
fi

# Quest fanfare — one render of COMPLETE when the quest we were tracking left
# in_progress (it verified, or the picker moved on because it finished). The
# state write below is what decays it: next render PREV_QSTATE is no longer
# in_progress, so the condition can't re-fire.
FANFARE=""
if [ "$PREV_QSTATE" = "in_progress" ]; then
  if [ "$PREV_QUEST" = "$QUEST" ] && [ "$QUEST_STATE" = "verified" ]; then
    FANFARE="$QUEST"
  elif [ -n "$PREV_QUEST" ] && [ "$PREV_QUEST" != "$QUEST" ]; then
    FANFARE="$PREV_QUEST"
  fi
fi

# Persist THIS render for the next one. This write is also the effect-decay
# mechanism — never skip it, even when nothing fired. (2>/dev/null first — see
# the cache write above for why the order is load-bearing.)
{
  printf '%s\n' "$_pct_int" "$ZONE" "$QUEST" "$QUEST_STATE"
} 2>/dev/null > "$STATE" || true

# ─── 4. Identity — job titles and party colours ───────────────────────────
# model.id → FF job. The mapping is flavour, but it's *legible* flavour: the
# job names track what the tiers are actually for.
JOB=""
case "$MODEL_ID" in
  *fable*)  JOB="Sage" ;;
  *opus*)   JOB="Summoner" ;;
  *sonnet*) JOB="Bard" ;;
  *haiku*)  JOB="Ninja" ;;
esac

# agent.name → capability-class colour, the sigil identity system carried into
# one line. Unknown agents get the v1 bold-cyan. (bash 3.2: case, not declare -A.)
C_AGENT="${C_BOLD}${C_CYAN}"
case "$AGENT" in
  atlas)          C_AGENT="$C_CYAN" ;;                 # scout — sky
  ramza|spectra)  C_AGENT="$C_WHITE" ;;                # planner — tactician white
  vivi|apivr*)    C_AGENT="${C_BOLD}${C_BLUE}" ;;      # coder — black-mage blue
  idg)            C_AGENT="$C_GREEN" ;;                # scriber — ink on vellum
  forge)          C_AGENT="$C_GOLD" ;;                 # reasoner — furnace
  vigil)          C_AGENT="$C_RED" ;;                  # debugger — blood trail
  kupo)           C_AGENT="$C_PINK" ;;                 # executor — moogle pom
  gilgamesh)      C_AGENT="$C_BGREEN" ;;               # generalist — wanderer
esac

# MP — the 5-hour rate limit, shown as REMAINING so it drains as you cast.
MP_PLAIN=""; MP_COLOR=""
_rl5_int=""
case "$RL5" in
  ''|*[!0-9.]*) _rl5_int="" ;;
  *) _rl5_int="${RL5%%.*}" ;;
esac
if [ -n "$_rl5_int" ]; then
  _mp_rem=$(( 100 - _rl5_int ))
  [ "$_mp_rem" -lt 0 ] && _mp_rem=0
  _mp_filled=$(( (_mp_rem * MP_CELLS + 50) / 100 ))
  [ "$_mp_filled" -gt "$MP_CELLS" ] && _mp_filled="$MP_CELLS"
  [ "$_mp_filled" -lt 0 ] && _mp_filled=0
  _mp_bar="$(_repeat "$_mp_filled" "$G_FULL")$(_repeat $(( MP_CELLS - _mp_filled )) "$G_EMPTY")"
  C_MP="$C_CYAN"
  if   [ "$_mp_rem" -lt 25 ]; then C_MP="$C_RED"
  elif [ "$_mp_rem" -lt 50 ]; then C_MP="$C_AMBER"
  fi
  MP_PLAIN="MP ${_mp_bar} ${_mp_rem}%"
  MP_COLOR="${C_MP}MP ${_mp_bar} ${_mp_rem}%${C_RESET}"
fi

# ─── 5. Compose the HUD, degrading by priority ────────────────────────────
WIDTH="${COLUMNS:-100}"
case "$WIDTH" in ''|*[!0-9]*) WIDTH=100 ;; esac
[ "$WIDTH" -lt 40 ] && WIDTH=40
[ "$WIDTH" -gt 120 ] && WIDTH=120

# The limit gauge.
if [ -n "$_pct_int" ]; then
  _filled=$(( (_pct_int * BAR_CELLS + 50) / 100 ))
  [ "$_filled" -lt 0 ] && _filled=0
  [ "$_filled" -gt "$BAR_CELLS" ] && _filled="$BAR_CELLS"
  BAR="$(_repeat "$_filled" "$G_FULL")$(_repeat $((BAR_CELLS - _filled)) "$G_EMPTY")"
  PCT="${_pct_int}%"
else
  BAR="$(_repeat "$BAR_CELLS" "$G_EMPTY")"
  PCT="--%"
fi

# Uppercase the zone WITHOUT ${var^^} (bash 3.2).
ZONE_UC="$(printf '%s' "$ZONE" | tr 'a-z' 'A-Z')"

PROJECT="$(basename "${PROJECT_DIR:-$PWD}" 2>/dev/null || printf 'project')"

# TRANCE marker — deep reasoning engaged.
TRANCE=""
if [ "$THINKING" = "true" ] || [ "$EFFORT" = "high" ] || [ "$EFFORT" = "xhigh" ] || [ "$EFFORT" = "max" ]; then
  TRANCE=" ${G_TRANCE}"
fi

# The frame must never wrap: a wrapped status line corrupts every row below it.
# So instead of hard-trimming mid-word, segments are dropped in reverse order of
# value. Two things always survive, because they are the entire point of the
# feature: the job/project header, and the ECM context gauge (delta included —
# it is 4 chars of exactly the signal ECM exists to surface).
#
#   level 5  everything
#   level 4  drop EXP (+lines/-lines) and the job title
#   level 3  drop the party count (a dispatched agent and MP stay)
#   level 2  drop gil and MP
#   level 1  drop branch and the agent; truncate the quest
#   level 0  header + gauge only
#
_trunc() {
  # _trunc <string> <max> — ellipsis is single-width, so the maths still holds.
  if [ "${#1}" -le "$2" ]; then printf '%s' "$1"; return 0; fi
  printf '%s…' "$(printf '%s' "$1" | cut -c1-$(( $2 - 1 )))"
}

_compose() {
  _lvl="$1"
  _q_max=64
  [ "$_lvl" -le 1 ] && _q_max=18

  # ── Row 1: job[ · title] · project [· branch]        [gil · exp] ──
  _hdr="${MODEL}"
  _hdr_c="${MODEL}"
  if [ "$_lvl" -ge 5 ] && [ -n "$JOB" ]; then
    _hdr="${_hdr} ${G_SEP} ${JOB}"
    _hdr_c="${_hdr_c}${C_RESET}${C_DIM} ${G_SEP} ${JOB}${C_RESET}${C_BOLD}${C_CYAN}"
  fi
  L1_PLAIN="${G_TL}${G_H}${G_LB} ${_hdr}${TRANCE} ${G_RB}${G_H} ${PROJECT}"
  L1_COLOR="${C_FRAME}${G_TL}${G_H}${C_RESET}${C_BOLD}${C_CYAN}${G_LB} ${_hdr_c}${TRANCE} ${G_RB}${C_RESET}${C_FRAME}${G_H}${C_RESET} ${C_BOLD}${PROJECT}${C_RESET}"

  if [ "$_lvl" -ge 2 ] && [ -n "$BRANCH" ]; then
    L1_PLAIN="${L1_PLAIN} ${G_SEP} ${BRANCH}"
    L1_COLOR="${L1_COLOR} ${C_DIM}${G_SEP}${C_RESET} ${C_GREEN}${BRANCH}${C_RESET}"
    if [ "$DIRTY" != "0" ]; then
      L1_PLAIN="${L1_PLAIN}*${DIRTY}"
      L1_COLOR="${L1_COLOR}${C_AMBER}*${DIRTY}${C_RESET}"
    fi
  fi

  R1_PLAIN=""; R1_COLOR=""
  if [ "$_lvl" -ge 3 ] && [ -n "$COST" ]; then
    _gil="$(printf '%.2f' "$COST" 2>/dev/null || printf '0.00')"
    R1_PLAIN="${R1_PLAIN} \$${_gil}"
    R1_COLOR="${R1_COLOR} ${C_GOLD}\$${_gil}${C_RESET}"
  fi
  if [ "$_lvl" -ge 5 ] && [ -n "$LINES_ADD" ] && [ -n "$LINES_DEL" ] \
     && { [ "$LINES_ADD" != "0" ] || [ "$LINES_DEL" != "0" ]; }; then
    R1_PLAIN="${R1_PLAIN} ${G_SEP} +${LINES_ADD}/-${LINES_DEL}"
    R1_COLOR="${R1_COLOR} ${C_DIM}${G_SEP}${C_RESET} ${C_GREEN}+${LINES_ADD}${C_RESET}${C_DIM}/${C_RESET}${C_RED}-${LINES_DEL}${C_RESET}"
  fi
  R1_PLAIN="${R1_PLAIN} ${G_H}${G_TR}"
  R1_COLOR="${R1_COLOR} ${C_FRAME}${G_H}${G_TR}${C_RESET}"

  # ── Row 2: gauge+delta ZONE [OVERFLOW] [· who] [· quest]     [MP] ──
  L2_PLAIN="${G_BL}${G_H} ${G_GAUGE} ${BAR} ${PCT}${DELTA_PLAIN} ${ZONE_UC}"
  L2_COLOR="${C_FRAME}${G_BL}${G_H}${C_RESET} ${C_ZONE}${G_GAUGE} ${BAR} ${PCT}${C_RESET}${DELTA_COLOR} ${ZONE_FX}${C_ZONE}${ZONE_UC}${C_RESET}"

  if [ "$EXCEEDS" = "true" ] && [ "$_lvl" -ge 1 ]; then
    L2_PLAIN="${L2_PLAIN} OVERFLOW"
    L2_COLOR="${L2_COLOR} ${C_FLASH}${C_RED}OVERFLOW${C_RESET}"
  fi

  # A dispatched subagent outranks the party count — show who is actually
  # acting, in its class colour. The agent survives one level deeper than
  # the party (an active dispatch is live state; the roster size is decor).
  if [ -n "$AGENT" ] && [ "$_lvl" -ge 2 ]; then
    L2_PLAIN="${L2_PLAIN} ${G_SEP} ${AGENT}"
    L2_COLOR="${L2_COLOR} ${C_DIM}${G_SEP}${C_RESET} ${C_AGENT}${AGENT}${C_RESET}"
  elif [ -z "$AGENT" ] && [ -n "$PARTY" ] && [ "$_lvl" -ge 4 ]; then
    L2_PLAIN="${L2_PLAIN} ${G_SEP} party ${PARTY}"
    L2_COLOR="${L2_COLOR} ${C_DIM}${G_SEP} party ${PARTY}${C_RESET}"
  fi

  if [ -n "$FANFARE" ] && [ "$_lvl" -ge 1 ]; then
    _q="$(_trunc "$FANFARE" "$_q_max")"
    L2_PLAIN="${L2_PLAIN} ${G_SEP} ${G_DONE} ${_q} COMPLETE!"
    L2_COLOR="${L2_COLOR} ${C_DIM}${G_SEP}${C_RESET} ${C_BOLD}${C_GREEN}${G_DONE} ${_q} COMPLETE!${C_RESET}"
  elif [ -n "$QUEST" ] && [ "$_lvl" -ge 1 ]; then
    _q="$(_trunc "$QUEST" "$_q_max")"
    L2_PLAIN="${L2_PLAIN} ${G_SEP} ${G_QUEST} ${_q}"
    L2_COLOR="${L2_COLOR} ${C_DIM}${G_SEP}${C_RESET} ${C_AMBER}${G_QUEST} ${_q}${C_RESET}"
  fi

  R2_PLAIN=""; R2_COLOR=""
  if [ "$_lvl" -ge 3 ] && [ -n "$MP_PLAIN" ]; then
    R2_PLAIN=" ${MP_PLAIN}"
    R2_COLOR=" ${MP_COLOR}"
  fi
  R2_PLAIN="${R2_PLAIN} ${G_H}${G_BR}"
  R2_COLOR="${R2_COLOR} ${C_FRAME}${G_H}${G_BR}${C_RESET}"
}

# Pick the richest level whose BOTH rows still fit inside the frame. The +1
# accounts for the single space between content and the filler rule.
LEVEL=5
while [ "$LEVEL" -gt 0 ]; do
  _compose "$LEVEL"
  _f1=$(( WIDTH - ${#L1_PLAIN} - ${#R1_PLAIN} - 1 ))
  _f2=$(( WIDTH - ${#L2_PLAIN} - ${#R2_PLAIN} - 1 ))
  if [ "$_f1" -ge 1 ] && [ "$_f2" -ge 1 ]; then break; fi
  LEVEL=$(( LEVEL - 1 ))
done
[ "$LEVEL" -eq 0 ] && _compose 0

# ─── 6. Pad to the frame and emit ─────────────────────────────────────────
_emit_row() {
  # _emit_row <left_plain> <left_color> <right_plain> <right_color>
  _lp="$1"; _lc="$2"; _rp="$3"; _rc="$4"
  _fill=$(( WIDTH - ${#_lp} - ${#_rp} ))
  if [ "$_fill" -lt 1 ]; then
    # Even level 0 can overrun on a pathologically long model/project name. The
    # never-wrap invariant beats aesthetics here: emit the plain text hard-cut
    # to the frame width (no colour — SGR offsets would corrupt the cut maths).
    _avail=$(( WIDTH - 1 ))
    [ "$_avail" -lt 1 ] && _avail=1
    printf '%s\n' "$(printf '%s' "$_lp" | cut -c1-"$_avail")"
    return 0
  fi
  printf '%s%s%s%s%s\n' "$_lc" "$C_FRAME" "$(_repeat "$_fill" "$G_H")" "$C_RESET" "$_rc"
}

# The trailing space keeps the rule from reading as a strikethrough on the last word.
_emit_row "$L1_PLAIN " "$L1_COLOR " "$R1_PLAIN" "$R1_COLOR"
_emit_row "$L2_PLAIN " "$L2_COLOR " "$R2_PLAIN" "$R2_COLOR"

exit 0
