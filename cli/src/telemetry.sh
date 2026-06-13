#!/usr/bin/env bash
# cli/src/telemetry.sh — eidolons telemetry kernel
# ═══════════════════════════════════════════════════════════════════════════
# Implements the D1 capture path (§4.1) and the D2 store layout (§4.2).
# Dispatched by `cli/eidolons` via: exec bash "$CLI_SRC/telemetry.sh" "$@"
#
# Subcommands (Phase C — only `capture` is functional):
#   capture --hook STOP_<HOST> --stdin   Read Stop hook stdin, project turns
#   rollup  [opts]                       (Phase D stub)
#   report  [opts]                       (Phase D stub)
#   enable                               (Phase F stub)
#   disable                              (Phase F stub)
#
# Honesty contract (C6): every row carries source:audited|estimated.
# Fail-open contract (C5/hook safety): errors NEVER propagate; exit 0 always.
# All log output → stderr. stdout reserved for JSON/data output.
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

# ─── Usage ────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
eidolons telemetry — opt-in token telemetry subsystem (MLP)

Usage:
  eidolons telemetry capture --hook STOP_<HOST> --stdin
  eidolons telemetry rollup  [--by repo|branch|model|eidolon|tier|day] [--since DATE] [--project <slug>] [--json]
  eidolons telemetry report  [--project <slug>] [--since DATE] [--json]
  eidolons telemetry enable
  eidolons telemetry disable

capture   Read a Stop/SessionEnd hook event from stdin, project each assistant
          turn's real API token usage into a turn.v1 row, and append to the
          day-partitioned D2 store. Source 'audited' for claude-code; 'estimated'
          stub for other hosts. ALWAYS exits 0 (fail-open; hook path never errors).

rollup    (Phase D — not yet implemented) Pure-jq M1/M2/M3 aggregation over the store.

report    (Phase D — not yet implemented) Human dashboard: M1 spend by
          repo/branch/model/eidolon/tier, always source-split (audited vs estimated).

enable    (Phase F — not yet implemented) Write the zero-logic Stop shim +
          register the hook in .claude/settings.json.

disable   (Phase F — not yet implemented) Remove the Stop shim + hook entry.

Store layout:
  $EIDOLONS_HOME/telemetry/<project-slug>/<YYYY-MM-DD>.jsonl

Honesty contract: source:audited rows derive from the real session transcript
(ground-truth token counts). source:estimated rows are proxy/heuristic
approximations. Reports ALWAYS split these two — never blend them.

For per-thread ECL token estimates, see: eidolons trace cost
EOF
}

# ─── Subcommand dispatch ─────────────────────────────────────────────────
sub="${1:-}"
[[ $# -gt 0 ]] && shift

case "$sub" in
  capture) ;;  # handled below
  rollup|report)  ;;  # handled below — Phase D implementations
  enable|disable)
    die "telemetry $sub: not yet implemented (Phase F)"
    ;;
  --help|-h|help)
    usage
    exit 0
    ;;
  "")
    usage
    exit 0
    ;;
  *)
    printf '%s\n' "eidolons telemetry: unknown subcommand '$sub'" >&2
    printf '%s\n' "Run 'eidolons telemetry --help' for usage." >&2
    exit 1
    ;;
esac

# ══════════════════════════════════════════════════════════════════════════
# Phase D — rollup and report (pure-jq M1/M2/M3)
# ══════════════════════════════════════════════════════════════════════════

if [[ "$sub" == "rollup" || "$sub" == "report" ]]; then

  # ── Shared arg parsing for rollup + report ──────────────────────────────
  _trd_by="model"
  _trd_since=""
  _trd_project=""
  _trd_json=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --by)
        _trd_by="${2:-model}"
        shift 2
        ;;
      --since)
        _trd_since="${2:-}"
        shift 2
        ;;
      --project)
        _trd_project="${2:-}"
        shift 2
        ;;
      --json)
        _trd_json=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        printf '%s\n' "telemetry $sub: unknown option '$1'" >&2
        exit 1
        ;;
    esac
  done

  # Resolve project slug: --project wins; fallback to cwd-derived.
  if [[ -z "$_trd_project" ]]; then
    _trd_project="$(project_slug)"
  fi

  # D2 store directory for this project.
  _trd_store_dir="${EIDOLONS_HOME}/telemetry/${_trd_project}"

  # ── Empty / absent store — honest exit 0 ─────────────────────────────
  _trd_has_data=0
  if [[ -d "$_trd_store_dir" ]]; then
    for _trd_f in "${_trd_store_dir}"/*.jsonl; do
      [[ -f "$_trd_f" ]] && { _trd_has_data=1; break; }
    done
  fi

  if [[ "$_trd_has_data" -eq 0 ]]; then
    if [[ "$_trd_json" -eq 1 ]]; then
      printf '%s\n' '{"status":"empty","message":"no telemetry captured yet for '"$_trd_project"'"}'
    else
      printf 'no telemetry captured yet for %s\n' "$_trd_project"
    fi
    exit 0
  fi

  # ── Collect JSONL files (optionally filtered by --since date) ──────────
  # Build an array of matching day files. Use word-level loop (bash 3.2 safe).
  _trd_files=""
  for _trd_f in "${_trd_store_dir}"/*.jsonl; do
    [[ -f "$_trd_f" ]] || continue
    if [[ -n "$_trd_since" ]]; then
      _trd_day="$(basename "$_trd_f" .jsonl)"
      # Skip files whose date is before --since.
      if [[ "$_trd_day" < "$_trd_since" ]]; then
        continue
      fi
    fi
    _trd_files="${_trd_files} ${_trd_f}"
  done

  if [[ -z "$_trd_files" ]]; then
    if [[ "$_trd_json" -eq 1 ]]; then
      printf '%s\n' '{"status":"empty","message":"no telemetry captured yet for '"$_trd_project"'"}'
    else
      printf 'no telemetry captured yet for %s\n' "$_trd_project"
    fi
    exit 0
  fi

  # ── STORE = deduplicated rows (jq -s unique_by(.event_id) per §4.2) ───
  # shellcheck disable=SC2086
  # We can't use an array-quoting trick in bash 3.2 with variable-length
  # lists, so pass _trd_files as word-split (intentional, files have no spaces).
  # shellcheck disable=SC2086
  STORE="$(jq -s 'unique_by(.event_id)' ${_trd_files} 2>/dev/null || echo '[]')"

  _trd_total="$(printf '%s' "$STORE" | jq 'length')"
  if [[ "$_trd_total" -eq 0 ]]; then
    if [[ "$_trd_json" -eq 1 ]]; then
      printf '%s\n' '{"status":"empty","message":"no telemetry captured yet for '"$_trd_project"'"}'
    else
      printf 'no telemetry captured yet for %s\n' "$_trd_project"
    fi
    exit 0
  fi

  # ══════════════════════════════════════════════════════════════════════
  # rollup subcommand
  # ══════════════════════════════════════════════════════════════════════
  if [[ "$sub" == "rollup" ]]; then

    # Validate --by value.
    case "$_trd_by" in
      repo|branch|model|eidolon|tier|day) ;;
      *) die "telemetry rollup: --by must be one of repo|branch|model|eidolon|tier|day" ;;
    esac

    # For --by day, group on the date portion of .ts; otherwise on attribution key.
    if [[ "$_trd_by" == "model" ]]; then
      _trd_key_expr='.model'
    elif [[ "$_trd_by" == "day" ]]; then
      _trd_key_expr='(.ts // "" | split("T") | .[0])'
    else
      _trd_key_expr=".attribution.${_trd_by}"
    fi

    # M1-style rollup per §7, always source-split.
    # The spec formula groups by source first, then by the key.
    _trd_rollup="$(printf '%s' "$STORE" | jq --arg by "$_trd_by" --arg key_expr "$_trd_key_expr" '
      group_by(.source)
      | map({
          source: .[0].source,
          by: (
            . as $grp |
            if $by == "model" then
              ($grp | group_by(.model))
              | map({
                  key: (.[0].model // "?"),
                  turns: length,
                  input:          (map(.usage.input_tokens)                  | add // 0),
                  output:         (map(.usage.output_tokens)                 | add // 0),
                  cache_creation: (map(.usage.cache_creation_input_tokens)   | add // 0),
                  cache_read:     (map(.usage.cache_read_input_tokens)       | add // 0),
                  total: (map(.usage.input_tokens + .usage.output_tokens
                              + .usage.cache_creation_input_tokens
                              + .usage.cache_read_input_tokens) | add // 0)
                })
              | sort_by(-.total)
            elif $by == "repo" then
              ($grp | group_by(.attribution.repo))
              | map({
                  key: (.[0].attribution.repo // "?"),
                  turns: length,
                  input:          (map(.usage.input_tokens)                  | add // 0),
                  output:         (map(.usage.output_tokens)                 | add // 0),
                  cache_creation: (map(.usage.cache_creation_input_tokens)   | add // 0),
                  cache_read:     (map(.usage.cache_read_input_tokens)       | add // 0),
                  total: (map(.usage.input_tokens + .usage.output_tokens
                              + .usage.cache_creation_input_tokens
                              + .usage.cache_read_input_tokens) | add // 0)
                })
              | sort_by(-.total)
            elif $by == "branch" then
              ($grp | group_by(.attribution.branch))
              | map({
                  key: (.[0].attribution.branch // "?"),
                  turns: length,
                  input:          (map(.usage.input_tokens)                  | add // 0),
                  output:         (map(.usage.output_tokens)                 | add // 0),
                  cache_creation: (map(.usage.cache_creation_input_tokens)   | add // 0),
                  cache_read:     (map(.usage.cache_read_input_tokens)       | add // 0),
                  total: (map(.usage.input_tokens + .usage.output_tokens
                              + .usage.cache_creation_input_tokens
                              + .usage.cache_read_input_tokens) | add // 0)
                })
              | sort_by(-.total)
            elif $by == "eidolon" then
              ($grp | group_by(.attribution.eidolon))
              | map({
                  key: (.[0].attribution.eidolon // "?"),
                  turns: length,
                  input:          (map(.usage.input_tokens)                  | add // 0),
                  output:         (map(.usage.output_tokens)                 | add // 0),
                  cache_creation: (map(.usage.cache_creation_input_tokens)   | add // 0),
                  cache_read:     (map(.usage.cache_read_input_tokens)       | add // 0),
                  total: (map(.usage.input_tokens + .usage.output_tokens
                              + .usage.cache_creation_input_tokens
                              + .usage.cache_read_input_tokens) | add // 0)
                })
              | sort_by(-.total)
            elif $by == "tier" then
              ($grp | group_by(.attribution.tier))
              | map({
                  key: (.[0].attribution.tier // "?"),
                  turns: length,
                  input:          (map(.usage.input_tokens)                  | add // 0),
                  output:         (map(.usage.output_tokens)                 | add // 0),
                  cache_creation: (map(.usage.cache_creation_input_tokens)   | add // 0),
                  cache_read:     (map(.usage.cache_read_input_tokens)       | add // 0),
                  total: (map(.usage.input_tokens + .usage.output_tokens
                              + .usage.cache_creation_input_tokens
                              + .usage.cache_read_input_tokens) | add // 0)
                })
              | sort_by(-.total)
            else
              ($grp | group_by(.ts[0:10]))
              | map({
                  key: (.[0].ts[0:10] // "?"),
                  turns: length,
                  input:          (map(.usage.input_tokens)                  | add // 0),
                  output:         (map(.usage.output_tokens)                 | add // 0),
                  cache_creation: (map(.usage.cache_creation_input_tokens)   | add // 0),
                  cache_read:     (map(.usage.cache_read_input_tokens)       | add // 0),
                  total: (map(.usage.input_tokens + .usage.output_tokens
                              + .usage.cache_creation_input_tokens
                              + .usage.cache_read_input_tokens) | add // 0)
                })
              | sort_by(.key)
            end
          )
        })')"

    if [[ "$_trd_json" -eq 1 ]]; then
      printf '%s\n' "$_trd_rollup"
    else
      printf '%stellemetry rollup%s  (by %s, project: %s)\n' \
        "${BOLD:-}" "${RESET:-}" "$_trd_by" "$_trd_project"
      printf '%s' "$_trd_rollup" | jq -r '.[] | "  [source: \(.source)]", (.by[] | "  \(.key // "?")\t\(.turns) turns\t\(.total) tokens")'
    fi
    exit 0
  fi

  # ══════════════════════════════════════════════════════════════════════
  # report subcommand — M1 / M2 / M3, honesty-gated (C6)
  # ══════════════════════════════════════════════════════════════════════
  if [[ "$sub" == "report" ]]; then

    # ── M1 — real spend attribution (headline, §7) ─────────────────────
    # Group by source, then compute totals + breakdowns.
    # The honesty gate (AC-F4-4): audited and estimated MUST remain
    # as distinct keys. No blended total at the top level.
    _trd_m1="$(printf '%s' "$STORE" | jq '
      # Compute per-source totals (strict separation — honesty gate C6)
      (group_by(.source)
       | map({
           key: .[0].source,
           value: {
             turns: length,
             total_tokens: (map(.usage.input_tokens + .usage.output_tokens
                               + .usage.cache_creation_input_tokens
                               + .usage.cache_read_input_tokens) | add // 0),
             input_tokens:          (map(.usage.input_tokens)                | add // 0),
             output_tokens:         (map(.usage.output_tokens)               | add // 0),
             cache_creation_tokens: (map(.usage.cache_creation_input_tokens) | add // 0),
             cache_read_tokens:     (map(.usage.cache_read_input_tokens)     | add // 0),
             by_model: (
               group_by(.model)
               | map({key: (.[0].model // "?"),
                      value: {turns: length,
                              total: (map(.usage.input_tokens + .usage.output_tokens
                                         + .usage.cache_creation_input_tokens
                                         + .usage.cache_read_input_tokens) | add // 0)}})
               | from_entries),
             by_repo: (
               group_by(.attribution.repo)
               | map({key: (.[0].attribution.repo // "?"),
                      value: {turns: length,
                              total: (map(.usage.input_tokens + .usage.output_tokens
                                         + .usage.cache_creation_input_tokens
                                         + .usage.cache_read_input_tokens) | add // 0)}})
               | from_entries),
             by_eidolon: (
               group_by(.attribution.eidolon)
               | map({key: (.[0].attribution.eidolon // "?"),
                      value: {turns: length,
                              total: (map(.usage.input_tokens + .usage.output_tokens
                                         + .usage.cache_creation_input_tokens
                                         + .usage.cache_read_input_tokens) | add // 0)}})
               | from_entries),
             by_tier: (
               group_by(.attribution.tier)
               | map({key: (.[0].attribution.tier // "null"),
                      value: {turns: length,
                              total: (map(.usage.input_tokens + .usage.output_tokens
                                         + .usage.cache_creation_input_tokens
                                         + .usage.cache_read_input_tokens) | add // 0)}})
               | from_entries)
           }
         })
       | from_entries) as $by_source |
      # Honesty gate: expose as by_source.audited / by_source.estimated
      # NEVER merge them into a single "total_tokens" at the top level.
      {by_source: $by_source}
    ')"

    # ── M2 — reconciliation delta (§7) ─────────────────────────────────
    _trd_m2="$(printf '%s' "$STORE" | jq '
      [.[] | select(.self_reported_tokens != null)]
      | if length == 0 then
          {turns_with_self_report: 0,
           status: "na",
           message: "0 turns with self-reported data — reconciliation N/A until ECL self-report join lands"}
        else
          map(
            . + {
              _audited_total: (.usage.input_tokens + .usage.output_tokens
                               + .usage.cache_creation_input_tokens
                               + .usage.cache_read_input_tokens),
              _delta: ((.usage.input_tokens + .usage.output_tokens
                        + .usage.cache_creation_input_tokens
                        + .usage.cache_read_input_tokens)
                       - .self_reported_tokens)
            }
          ) |
          {
            turns_with_self_report: length,
            mean_abs_delta: ((map(._delta | if . < 0 then -. else . end) | add) / length),
            drift_direction: (if (map(._delta) | add) > 0 then "agents_underreport" else "agents_overreport" end),
            status: "ok"
          }
        end
    ')"

    # ── M3 — cost intent split / TRANCE (§7, C6 source-split) ─────────
    _trd_m3="$(printf '%s' "$STORE" | jq '
      group_by(.source)
      | map({
          source: .[0].source,
          by_tier: (
            group_by(.attribution.tier)
            | map({
                tier: (.[0].attribution.tier // "standard"),
                turns: length,
                total: (map(.usage.input_tokens + .usage.output_tokens
                            + .usage.cache_creation_input_tokens
                            + .usage.cache_read_input_tokens) | add // 0)
              })
          )
        })
    ')"

    # ── JSON output (machine-readable, honesty-gated shape) ────────────
    if [[ "$_trd_json" -eq 1 ]]; then
      printf '%s' "$_trd_m1" | jq \
        --arg project "$_trd_project" \
        --argjson m2 "$_trd_m2" \
        --argjson m3 "$_trd_m3" \
        '. + {project: $project, m2_reconciliation: $m2, m3_tier_split: $m3}'
      exit 0
    fi

    # ── Text output ────────────────────────────────────────────────────
    printf '%seidolons telemetry report%s  (project: %s)\n' \
      "${BOLD:-}" "${RESET:-}" "$_trd_project"
    printf '%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    printf '\n%sM1 — Real Spend Attribution%s (tokens, not dollars — pricing P2)\n' \
      "${BOLD:-}" "${RESET:-}"
    printf '%s\n' "  Honesty contract: audited and estimated are ALWAYS shown separately."

    # Print per-source summaries.
    printf '%s' "$_trd_m1" | jq -r '
      .by_source | to_entries[] |
      "  [source: \(.key)]\n" +
      "    total_tokens:          \(.value.total_tokens)\n" +
      "    turns:                 \(.value.turns)\n" +
      "    input_tokens:          \(.value.input_tokens)\n" +
      "    output_tokens:         \(.value.output_tokens)\n" +
      "    cache_creation_tokens: \(.value.cache_creation_tokens)\n" +
      "    cache_read_tokens:     \(.value.cache_read_tokens)\n" +
      "    by_model:\n" +
      (.value.by_model | to_entries | sort_by(-.value.total) |
       map("      \(.key): \(.value.total) tokens (\(.value.turns) turns)") | join("\n")) +
      "\n    by_repo:\n" +
      (.value.by_repo | to_entries | sort_by(-.value.total) |
       map("      \(.key): \(.value.total) tokens (\(.value.turns) turns)") | join("\n")) +
      "\n    by_eidolon:\n" +
      (.value.by_eidolon | to_entries | sort_by(-.value.total) |
       map("      \(.key): \(.value.total) tokens (\(.value.turns) turns)") | join("\n")) +
      "\n    by_tier:\n" +
      (.value.by_tier | to_entries | sort_by(-.value.total) |
       map("      \(.key): \(.value.total) tokens (\(.value.turns) turns)") | join("\n"))
    '

    printf '\n%sM2 — Reconciliation Delta%s\n' "${BOLD:-}" "${RESET:-}"
    _trd_m2_status="$(printf '%s' "$_trd_m2" | jq -r '.status')"
    if [[ "$_trd_m2_status" == "na" ]]; then
      printf '  %s\n' "$(printf '%s' "$_trd_m2" | jq -r '.message')"
    else
      printf '%s' "$_trd_m2" | jq -r '
        "  turns with self-report: \(.turns_with_self_report)\n" +
        "  mean absolute delta:    \(.mean_abs_delta)\n" +
        "  drift direction:        \(.drift_direction)"
      '
    fi

    printf '\n%sM3 — Cost Intent / TRANCE Tier Split%s\n' "${BOLD:-}" "${RESET:-}"
    printf '%s' "$_trd_m3" | jq -r '
      .[] |
      "  [source: \(.source)]" +
      "\n" +
      (.by_tier | map("    tier \(.tier): \(.total) tokens (\(.turns) turns)") | join("\n"))
    '

    printf '\n%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf 'note: all figures in tokens (dollar pricing → P2)\n'
    printf 'for per-thread ECL estimates, see: eidolons trace cost\n'
    exit 0
  fi

fi

# ══════════════════════════════════════════════════════════════════════════
# telemetry capture
# ══════════════════════════════════════════════════════════════════════════

# ── Parse capture args ────────────────────────────────────────────────────
HOOK_NAME=""
READ_STDIN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hook)
      HOOK_NAME="${2:-}"
      [[ -z "$HOOK_NAME" ]] && { printf '%s\n' "telemetry capture: --hook requires a value" >&2; exit 1; }
      shift 2
      ;;
    --stdin)
      READ_STDIN=1
      shift
      ;;
    --help|-h)
      cat <<'CHELP'
eidolons telemetry capture --hook STOP_<HOST> --stdin

Reads a Stop/SessionEnd hook event JSON from stdin.  --hook names the host
adapter (STOP_claude-code, STOP_codex, STOP_copilot, STOP_cursor, STOP_opencode).
Always exits 0 — a hook path must never propagate errors.
CHELP
      exit 0
      ;;
    *)
      printf '%s\n' "telemetry capture: unknown option '$1'" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$HOOK_NAME" ]]; then
  printf '%s\n' "telemetry capture: --hook STOP_<HOST> is required" >&2
  exit 1
fi

# ── Read stdin (mirror run.sh:96-98) ─────────────────────────────────────
HOOK_STDIN_INPUT=""
if [[ "$READ_STDIN" == "1" ]]; then
  HOOK_STDIN_INPUT="$(cat 2>/dev/null || true)"
fi

# ── Derive host from --hook STOP_<HOST> ──────────────────────────────────
# HOOK_NAME is e.g. STOP_claude-code → host = claude-code
_hook_host=""
case "$HOOK_NAME" in
  STOP_*)  _hook_host="${HOOK_NAME#STOP_}" ;;
  *)       _hook_host="$HOOK_NAME" ;;
esac

# ══════════════════════════════════════════════════════════════════════════
# Helper: sha256 of a string (bash 3.2; shasum/sha256sum fallback)
# Writes hex digest to stdout. Returns 0 on success, 1 on failure.
# ══════════════════════════════════════════════════════════════════════════
_sha256_str() {
  local _s="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$_s" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$_s" | sha256sum | awk '{print $1}'
  else
    # Fallback: deterministic composite without hash (still unique per session+index)
    printf '%s' "$_s" | od -A n -t x1 | tr -d ' \n' | head -c 64
  fi
}

# ══════════════════════════════════════════════════════════════════════════
# Helper: append a row to the D2 store, skipping duplicate event_ids
# Args: $1=row_json  $2=day_file
# ══════════════════════════════════════════════════════════════════════════
_append_row_if_new() {
  local _row="$1"
  local _day_file="$2"
  local _event_id
  _event_id="$(printf '%s' "$_row" | jq -r '.event_id // empty' 2>/dev/null || true)"
  if [[ -z "$_event_id" ]]; then
    info "telemetry: row has no event_id, skipping append"
    return 0
  fi
  # Best-effort skip-on-append: check if event_id already in day file.
  if [[ -f "$_day_file" ]]; then
    if grep -qF "\"$_event_id\"" "$_day_file" 2>/dev/null; then
      info "telemetry: event_id $_event_id already present in $_day_file, skipping"
      return 0
    fi
  fi
  # Atomic single-printf append (rows <4KB, O_APPEND safe).
  printf '%s\n' "$_row" >> "$_day_file"
}

# ══════════════════════════════════════════════════════════════════════════
# Adapter: claude-code (audited path)
# ══════════════════════════════════════════════════════════════════════════
telemetry_capture_claude_code() {
  # Extract transcript_path from hook stdin.
  local _tp=""
  if [[ -n "$HOOK_STDIN_INPUT" ]]; then
    _tp="$(printf '%s' "$HOOK_STDIN_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  fi

  # Fail-open: missing/empty transcript_path → info + exit 0 (AC-F1-5).
  if [[ -z "$_tp" ]]; then
    info "telemetry capture claude-code: no transcript_path in hook event; skipping"
    return 0
  fi
  if [[ ! -f "$_tp" ]]; then
    info "telemetry capture claude-code: transcript not found: $_tp; skipping"
    return 0
  fi
  if [[ ! -r "$_tp" ]]; then
    info "telemetry capture claude-code: transcript not readable: $_tp; skipping"
    return 0
  fi

  # Derive the project-slug for the D2 store.
  # We use the transcript's cwd (first assistant line), falling back to PWD.
  local _cwd_from_transcript
  _cwd_from_transcript="$(jq -r 'select(.type=="assistant") | .cwd // empty' "$_tp" 2>/dev/null | head -1 || true)"
  local _store_slug
  if [[ -n "$_cwd_from_transcript" ]]; then
    local _bn
    _bn="$(basename "$_cwd_from_transcript")"
    _store_slug="$(printf '%s' "$_bn" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -e 's|^-||' -e 's|-$||')"
  else
    _store_slug="$(project_slug)"
  fi

  # Get git commit + dirty status (one call per session, using the transcript cwd).
  local _git_commit="" _git_dirty=""
  local _git_cwd="${_cwd_from_transcript:-$PWD}"
  if git -C "$_git_cwd" rev-parse HEAD >/dev/null 2>&1; then
    _git_commit="$(git -C "$_git_cwd" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "$(git -C "$_git_cwd" status --porcelain 2>/dev/null || true)" ]]; then
      _git_dirty="true"
    else
      _git_dirty="false"
    fi
  fi

  # Get PR info from environment.
  local _pr_ref="null"
  if [[ -n "${GITHUB_REF:-}" ]]; then
    _pr_ref="\"${GITHUB_REF}\""
  elif [[ -n "${PR_NUMBER:-}" ]]; then
    _pr_ref="\"${PR_NUMBER}\""
  fi

  # Single jq pass: filter assistant lines, map to turn.v1 rows.
  # We need per-turn event_ids computed in bash (sha256 requires shell),
  # so we first extract the raw turn data via jq, then loop in bash to
  # hash and assemble each row. The jq slice is the bulk work; the bash
  # loop is O(turns) with one sha call each.
  local _turns_json
  _turns_json="$(jq -c '
    [
      . as $line |
      select(.type == "assistant") |
      {
        session_id: .sessionId,
        ts: .timestamp,
        model: (.message.model // "unknown"),
        input_tokens: (.message.usage.input_tokens // 0),
        output_tokens: (.message.usage.output_tokens // 0),
        cache_creation_input_tokens: (.message.usage.cache_creation_input_tokens // 0),
        cache_read_input_tokens: (.message.usage.cache_read_input_tokens // 0),
        cwd: (.cwd // ""),
        git_branch: (.gitBranch // null),
        is_sidechain: (.isSidechain // false),
        request_id: (.requestId // "")
      }
    ]
  ' "$_tp" 2>/dev/null | jq -c '.[]' 2>/dev/null || true)"

  if [[ -z "$_turns_json" ]]; then
    info "telemetry capture claude-code: no assistant turns found in transcript; skipping"
    return 0
  fi

  local _turn_index=0
  local _today
  _today="$(date -u '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')"

  # Process each turn.
  while IFS= read -r _turn; do
    [[ -z "$_turn" ]] && continue

    local _sess_id _ts _model _in _out _cc _cr _cwd _branch _is_sc _req_id
    _sess_id="$(printf '%s' "$_turn" | jq -r '.session_id // "unknown"')"
    _ts="$(printf '%s' "$_turn" | jq -r '.ts // "1970-01-01T00:00:00Z"')"
    _model="$(printf '%s' "$_turn" | jq -r '.model // "unknown"')"
    _in="$(printf '%s' "$_turn" | jq -r '.input_tokens // 0')"
    _out="$(printf '%s' "$_turn" | jq -r '.output_tokens // 0')"
    _cc="$(printf '%s' "$_turn" | jq -r '.cache_creation_input_tokens // 0')"
    _cr="$(printf '%s' "$_turn" | jq -r '.cache_read_input_tokens // 0')"
    _cwd="$(printf '%s' "$_turn" | jq -r '.cwd // ""')"
    _branch="$(printf '%s' "$_turn" | jq -r '.git_branch // null')"
    _is_sc="$(printf '%s' "$_turn" | jq -r '.is_sidechain // false')"

    # Compute event_id: sha256(session_id|turn_index).
    local _event_id
    _event_id="$(_sha256_str "${_sess_id}|${_turn_index}" 2>/dev/null || printf '%s' "${_sess_id}|${_turn_index}" | od -A n -t x1 | tr -d ' \n' | head -c 64)"

    # Derive ts date for day partitioning (from the turn's timestamp).
    local _day
    _day="$(printf '%s' "$_ts" | sed 's/T.*//' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || echo "$_today")"

    # D2 store path.
    local _store_dir="$EIDOLONS_HOME/telemetry/${_store_slug}"
    local _day_file="${_store_dir}/${_day}.jsonl"
    mkdir -p "$_store_dir"

    # Attribution keys (AC-F3-1/F3-2):
    #   repo = basename of cwd (free from transcript line)
    #   branch = from transcript line (no extra git call)
    #   commit/dirty = from the one-per-session git call above
    #   is_sidechain = from transcript line
    #   eidolon = joined from dispatch record (Phase E); honest fallback when absent
    local _repo
    _repo="$(basename "${_cwd:-$PWD}" 2>/dev/null || echo "unknown")"

    # ── Phase E: dispatch-time join (AC-F3, spec §4.3) ───────────────────────
    # Load .dispatch/<session_id>.jsonl if present. Find the row with the
    # greatest ts <= this turn's ts (time-proximity: the dispatch active when
    # this turn occurred). Apply its eidolon/eidolon_prompt_sha/objective_hash/tier.
    # Honest fallback when no match: eidolon = main/unknown, rest = null.
    local _dispatch_eidolon="" _dispatch_eps="" _dispatch_obj_hash="" _dispatch_tier=""
    local _dispatch_file="${EIDOLONS_HOME}/telemetry/.dispatch/${_sess_id}.jsonl"
    if [[ -f "$_dispatch_file" ]] && command -v jq >/dev/null 2>&1; then
      # Single jq -s pass: slurp JSONL, filter ts <= turn_ts, pick last (greatest ts).
      # Returns compact JSON of the best matching dispatch row, or empty string.
      local _best_row
      _best_row="$(jq -sc --arg turn_ts "$_ts" \
        'map(select(.ts <= $turn_ts)) | sort_by(.ts) | last // empty' \
        "$_dispatch_file" 2>/dev/null || true)"
      if [[ -n "$_best_row" && "$_best_row" != "null" && "$_best_row" != "empty" ]]; then
        local _d_eidolon
        _d_eidolon="$(printf '%s' "$_best_row" | jq -r '.eidolon // empty' 2>/dev/null || true)"
        if [[ -n "$_d_eidolon" && "$_d_eidolon" != "null" ]]; then
          _dispatch_eidolon="$_d_eidolon"
          _dispatch_eps="$(printf '%s' "$_best_row" | jq -r '.eidolon_prompt_sha // empty' 2>/dev/null || true)"
          _dispatch_obj_hash="$(printf '%s' "$_best_row" | jq -r '.objective_hash // empty' 2>/dev/null || true)"
          _dispatch_tier="$(printf '%s' "$_best_row" | jq -r '.tier // empty' 2>/dev/null || true)"
        fi
      fi
    fi

    # Resolve final eidolon / eidolon_prompt_sha / objective_hash / tier values.
    # Dispatch join takes priority; honest fallback when absent (AC-F3-6).
    local _eidolon _eps_val _obj_hash_val _tier_val
    if [[ -n "$_dispatch_eidolon" ]]; then
      _eidolon="$_dispatch_eidolon"
    else
      if [[ "$_is_sc" == "true" ]]; then
        _eidolon="unknown"
      else
        _eidolon="main"
      fi
    fi

    # eidolon_prompt_sha: null when no dispatch match (honest).
    if [[ -n "$_dispatch_eps" && "$_dispatch_eps" != "null" ]]; then
      _eps_val="$_dispatch_eps"
    else
      _eps_val="null"
    fi

    # objective_hash: null when no dispatch match.
    if [[ -n "$_dispatch_obj_hash" && "$_dispatch_obj_hash" != "null" ]]; then
      _obj_hash_val="$_dispatch_obj_hash"
    else
      _obj_hash_val="null"
    fi

    # tier: null when no dispatch match (M3 split requires explicit tier; null = no TRANCE attribution yet).
    if [[ -n "$_dispatch_tier" && "$_dispatch_tier" != "null" ]]; then
      _tier_val="$_dispatch_tier"
    else
      _tier_val="null"
    fi

    # JSON-encode the nullable attribution fields.
    local _eps_json _obj_hash_json _tier_json
    if [[ "$_eps_val" == "null" ]]; then
      _eps_json="null"
    else
      _eps_json="\"${_eps_val}\""
    fi
    if [[ "$_obj_hash_val" == "null" ]]; then
      _obj_hash_json="null"
    else
      _obj_hash_json="\"${_obj_hash_val}\""
    fi
    if [[ "$_tier_val" == "null" ]]; then
      _tier_json="null"
    else
      _tier_json="\"${_tier_val}\""
    fi

    # Build JSON row via jq -nc (no raw prompt/response text — AC-F1-4).
    # Attribution fields enriched by Phase E dispatch-time join.
    local _row
    _row="$(jq -nc \
      --arg schema "eidolons.telemetry.turn.v1" \
      --arg event_id "$_event_id" \
      --arg ts "$_ts" \
      --arg source "audited" \
      --arg host "claude-code" \
      --arg session_id "$_sess_id" \
      --argjson turn_index "$_turn_index" \
      --arg model "$_model" \
      --argjson input_tokens "$_in" \
      --argjson output_tokens "$_out" \
      --argjson cache_creation_input_tokens "$_cc" \
      --argjson cache_read_input_tokens "$_cr" \
      --arg repo "$_repo" \
      --argjson branch "$(printf '%s' "$_branch" | jq -R 'if . == "null" then null else . end')" \
      --argjson commit "$(if [[ -n "$_git_commit" ]]; then printf '"%s"' "$_git_commit"; else printf 'null'; fi)" \
      --argjson dirty "$(if [[ -n "$_git_dirty" ]]; then printf '%s' "$_git_dirty"; else printf 'null'; fi)" \
      --argjson pr "$_pr_ref" \
      --arg cwd "${_cwd:-}" \
      --argjson is_sidechain "$_is_sc" \
      --arg eidolon "$_eidolon" \
      --argjson eidolon_prompt_sha "$_eps_json" \
      --argjson objective_hash "$_obj_hash_json" \
      --argjson tier "$_tier_json" \
      '{
        schema: $schema,
        event_id: $event_id,
        ts: $ts,
        source: $source,
        host: $host,
        session_id: $session_id,
        turn_index: $turn_index,
        model: $model,
        usage: {
          input_tokens: $input_tokens,
          output_tokens: $output_tokens,
          cache_creation_input_tokens: $cache_creation_input_tokens,
          cache_read_input_tokens: $cache_read_input_tokens
        },
        self_reported_tokens: null,
        reconciliation_delta: null,
        attribution: {
          repo: $repo,
          branch: $branch,
          commit: $commit,
          dirty: $dirty,
          pr: $pr,
          cwd: $cwd,
          is_sidechain: $is_sidechain,
          eidolon: $eidolon,
          eidolon_prompt_sha: $eidolon_prompt_sha,
          objective_hash: $objective_hash,
          task_id: null,
          prompt_version: null,
          tier: $tier
        },
        ecl_thread_id: null
      }' 2>/dev/null || true)"

    if [[ -z "$_row" ]]; then
      info "telemetry capture: failed to build row for turn $_turn_index; skipping"
      _turn_index=$((_turn_index + 1))
      continue
    fi

    _append_row_if_new "$_row" "$_day_file"
    _turn_index=$((_turn_index + 1))
  done <<EOF
$_turns_json
EOF
}

# ══════════════════════════════════════════════════════════════════════════
# Stubs for non-CC hosts (estimated tier; never tagged audited — AC-F1-6)
# ══════════════════════════════════════════════════════════════════════════
telemetry_capture_codex() {
  info "telemetry capture codex: no audited adapter for codex; estimate tier (P2)"
  # Stub: exits 0, emits nothing audited.
}

telemetry_capture_copilot() {
  info "telemetry capture copilot: no audited adapter for copilot; estimate tier (P2)"
}

telemetry_capture_cursor() {
  info "telemetry capture cursor: no audited adapter for cursor; estimate tier (P2)"
}

telemetry_capture_opencode() {
  info "telemetry capture opencode: no audited adapter for opencode; estimate tier (P2)"
}

# ── Table-driven dispatch by host (one point, no per-host branches in shim)
# Wraps the whole capture in a fail-open guard (AC-F1-5).
# ══════════════════════════════════════════════════════════════════════════

_dispatch_capture() {
  local _host="$1"
  case "$_host" in
    claude-code)
      telemetry_capture_claude_code
      ;;
    codex)
      telemetry_capture_codex
      ;;
    copilot)
      telemetry_capture_copilot
      ;;
    cursor)
      telemetry_capture_cursor
      ;;
    opencode)
      telemetry_capture_opencode
      ;;
    *)
      info "telemetry capture: unknown host '$_host'; no adapter; skipping"
      ;;
  esac
}

# Fail-open wrapper: any unhandled error → info + exit 0.
{
  _dispatch_capture "$_hook_host"
} 2>&1 1>&2 || {
  info "telemetry capture: non-fatal error in adapter for host '$_hook_host'; exiting 0"
}

exit 0
