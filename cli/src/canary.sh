#!/usr/bin/env bash
# eidolons canary — Layer 3 methodology integrity (behavioral smoke)
# ═══════════════════════════════════════════════════════════════════════════════════
#
# Prints an Eidolon's canary mission prompt, or validates a saved LLM response
# against the mission's structured criteria.  Human-in-the-loop: the CLI never
# invokes an LLM itself; it bridges prompt-print → manual-run → validate-from-file.
#
# Modes:
#   eidolons canary <name>                     → prompt mode  (print prompt + criteria)
#   eidolons canary <name> --validate <file>   → validate mode
#   eidolons canary --list                     → list mode    (cache scan)
#   eidolons canary --memory                   → memory mode  (crystalium liveness probe)
#
# Bash 3.2 compatible: no associative arrays, no mapfile/readarray,
# no ${var,,}, no &>>, no process-substitution with exit-code dependence.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_memory_probe.sh"

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
eidolons canary — Layer 3 integrity: print canary prompt or validate LLM output
against an Eidolon's per-version canary mission.

Usage:
  eidolons canary <name>                       Print canary prompt + criteria
  eidolons canary <name> --validate <file>     Validate saved LLM output
  eidolons canary --list                       List Eidolons with/without missions
  eidolons canary --memory                     Crystalium memory liveness probe
  eidolons canary --host <h>                   Harness lock⇄reality PASS/FAIL/SKIP for host h
  eidolons canary --all-hosts                  Same, iterated over all known hosts

Options:
  --validate <file>    Validate LLM response from file against mission criteria
  --list               Scan cache; report mission availability per Eidolon
  --mission <id>       Select non-default mission by ID
  --memory             Recall-only crystalium liveness check (SKIP when
                        crystalium is not gated in .mcp.json + eidolons.mcp.lock)
  --host <h>           Harness canary for one host (claude-code, codex, copilot,
                        cursor, opencode) — see 'What --host/--all-hosts check' below
  --all-hosts          Harness canary for every known host
  --json               Emit machine-readable JSON on stdout
  -h, --help           Show this help

Exit codes:
  0   Prompt printed / validation PASS (or INCONCLUSIVE only) / list printed /
      --memory SKIP or PASS or INCONCLUSIVE / --host,--all-hosts all PASS or SKIP
  1   Validation had ≥1 FAIL criterion / --memory FAIL / --host,--all-hosts any FAIL
  2   Misuse: unknown name, missing file, unknown flag, unknown host

What it does:
  1. 'eidolons canary <name>' reads <cache>/evals/canary-missions.md and prints
     the mission prompt + expected output shape + validation criteria.
  2. User runs the prompt in their LLM environment of choice and saves the response.
  3. 'eidolons canary <name> --validate <file>' checks the saved output against
     the structured criteria (MUST/SHOULD × 4 verbs).
  4. '--list' scans the per-version cache for every lock member and reports
     which have canary missions authored.
  5. '--memory' probes the live crystalium store via the same docker transform
     as 'eidolons memory preflight' / doctor D13. This is a RECALL-ONLY
     liveness check, not a write->recall round trip: crystalium's own
     `canary` CLI subcommand runs a 10-mission A/B eval against a fresh
     EPHEMERAL store (not the live project store), so it is not surfaced
     here; and the write (`commit`) path is MCP-only, unreachable from bash.

What --host/--all-hosts check:
  Compares the EFFECTIVE harness state on disk against eidolons.lock's
  harness.{hosts_wired,strict,strict_modes,shim_paths} claim, mirroring the
  probes doctor's D12 (deep_check_harness_consistency in cli/src/lib.sh)
  derives — shims present+executable, host settings/hooks file present+valid
  (+wired entries for claude-code/codex), strict recorded backed by a
  PreToolUse shim (+ opencode's advisory strict_modes). Unlike D12 (which
  aggregates every host into one pass/fail count), this emits one PASS/FAIL/
  SKIP verdict per host:
    PASS — lock claims host is wired AND every probe for it is backed by reality.
    FAIL — lock claims host is wired but reality does not back the claim.
    SKIP — lock does not claim host is wired (or no harness: key at all).

Validation DSL verbs:
  MUST|SHOULD contain heading: <pattern>
  MUST|SHOULD contain phrase: <regex>
  MUST|SHOULD mention paths: <path1>, <path2>, ...
  MUST|SHOULD have token count between X and Y

MUST criteria: FAIL on mismatch → exit 1
SHOULD criteria: downgraded to INCONCLUSIVE on mismatch (never FAIL)
Unrecognized criteria: INCONCLUSIVE ("unrecognized criterion")
EOF
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
NAME=""
VALIDATE_FILE=""
LIST_MODE=false
MEMORY_MODE=false
HOST_NAME=""
ALL_HOSTS_MODE=false
MISSION_ID=""
JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      LIST_MODE=true
      shift
      ;;
    --memory)
      MEMORY_MODE=true
      shift
      ;;
    --host)
      [[ $# -gt 1 ]] || { printf 'canary: --host requires a host argument\n' >&2; exit 2; }
      HOST_NAME="$2"
      shift 2
      ;;
    --all-hosts)
      ALL_HOSTS_MODE=true
      shift
      ;;
    --validate)
      [[ $# -gt 1 ]] || { printf 'canary: --validate requires a file argument\n' >&2; exit 2; }
      VALIDATE_FILE="$2"
      shift 2
      ;;
    --mission)
      [[ $# -gt 1 ]] || { printf 'canary: --mission requires an ID argument\n' >&2; exit 2; }
      MISSION_ID="$2"
      shift 2
      ;;
    --json)
      JSON=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      printf 'canary: unknown flag: %s\n' "$1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$NAME" ]]; then
        NAME="$1"
      fi
      shift
      ;;
  esac
done

# ─── canary-missions.md parser helpers ────────────────────────────────────────

# first_mission_id FILE → echo the ID of the first "## Mission: <id>" heading.
# Uses awk to avoid grep exit-code propagation under set -euo pipefail.
# Returns empty string when no matching heading found (non-conforming format).
first_mission_id() {
  local file="$1"
  awk '/^## Mission:/{sub(/^## Mission:[[:space:]]*/,""); gsub(/[[:space:]]/, ""); print; exit}' "$file" 2>/dev/null || true
}

# list_mission_ids FILE → echo each mission ID on its own line.
# Uses awk to avoid grep exit-code propagation under set -euo pipefail.
list_mission_ids() {
  local file="$1"
  awk '/^## Mission:/{sub(/^## Mission:[[:space:]]*/,""); print}' "$file" 2>/dev/null || true
}

# extract_mission FILE MISSION_ID → echo the block from "## Mission: ID" to next
# "## " heading or EOF.  Outputs the header line too.
extract_mission() {
  local file="$1" target="$2"
  awk -v target="## Mission: $target" '
    /^## / {
      if (in_block) { exit }
      if ($0 == target) { in_block=1 }
    }
    in_block { print }
  ' "$file"
}

# extract_subsection BLOCK_FILE SUBSECTION_NAME → echo lines between
# "### <name>" and next "### " or EOF.  Trims leading/trailing blank lines.
# Uses awk exclusively for trimming (BSD sed compat — no multi-command labels).

extract_subsection_from_file() {
  local file="$1" section="$2"
  # Extract section body, then trim leading/trailing blank lines via awk.
  awk -v target="### $section" '
    /^### / {
      if (in_section) { exit }
      if ($0 == target) { in_section=1; next }
    }
    in_section { lines[n++]=$0 }
    END {
      # Find first non-blank line
      start=0
      while (start < n && lines[start] ~ /^[[:space:]]*$/) start++
      # Find last non-blank line
      end=n-1
      while (end >= start && lines[end] ~ /^[[:space:]]*$/) end--
      for (i=start; i<=end; i++) print lines[i]
    }
  ' "$file"
}

# extract_subsection_from_block_str: given a mission block already extracted to
# a tmpfile, extract a named subsection.
extract_subsection_block() {
  local tmpfile="$1" section="$2"
  extract_subsection_from_file "$tmpfile" "$section"
}

# ─── Criterion evaluator ──────────────────────────────────────────────────────

# evaluate_criterion VERB ARG OUTPUT_FILE → echos PASS or FAIL
# VERB: "contain heading" | "contain phrase" | "mention paths" | "have token count"
evaluate_criterion() {
  local verb="$1" arg="$2" output_file="$3"
  case "$verb" in
    "contain heading")
      # grep -Fxq against lines stripped of leading whitespace
      if sed 's/^[[:space:]]*//' "$output_file" | grep -Fxq "$arg" 2>/dev/null; then
        echo "PASS"
      else
        echo "FAIL"
      fi
      ;;
    "contain phrase")
      if grep -Eq "$arg" "$output_file" 2>/dev/null; then
        echo "PASS"
      else
        echo "FAIL"
      fi
      ;;
    "mention paths")
      # ALL comma-separated tokens must match
      local result="PASS"
      local token
      local IFS_orig="$IFS"
      IFS=','
      set -f
      # shellcheck disable=SC2086
      for token in $arg; do
        IFS="$IFS_orig"
        set +f
        token="$(printf '%s' "$token" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
        if [[ -n "$token" ]]; then
          if ! grep -Fq "$token" "$output_file" 2>/dev/null; then
            result="FAIL"
            break
          fi
        fi
        IFS=','
      done
      IFS="$IFS_orig"
      set +f
      echo "$result"
      ;;
    "have token count")
      # Argument: "between X and Y"
      local low high
      low="$(printf '%s' "$arg" | sed 's/between[[:space:]]*//' | awk '{print $1}')"
      high="$(printf '%s' "$arg" | awk '{print $NF}')"
      # word count × 4/3 ≈ token count
      local word_count
      word_count="$(wc -w < "$output_file" | tr -d '[:space:]')"
      local token_count
      # Use awk for arithmetic (bash 3.2 has no float; scale by 4/3 with integer math)
      token_count="$(awk -v w="$word_count" 'BEGIN{ print int(w * 4 / 3) }')"
      if [[ -n "$low" && -n "$high" ]] && \
         [ "$token_count" -ge "$low" ] 2>/dev/null && \
         [ "$token_count" -le "$high" ] 2>/dev/null; then
        echo "PASS"
      else
        echo "FAIL"
      fi
      ;;
    *)
      echo "UNKNOWN"
      ;;
  esac
}

# parse_criterion LINE → sets _crit_severity, _crit_verb, _crit_arg
# Returns 1 if line doesn't match any known pattern.
parse_criterion() {
  local line="$1"
  _crit_severity=""
  _crit_verb=""
  _crit_arg=""

  # Strip leading "- " and optional whitespace
  local body
  body="$(printf '%s' "$line" | sed 's/^-[[:space:]]*//')"

  # Extract severity
  case "$body" in
    MUST\ *)
      _crit_severity="MUST"
      body="${body#MUST }"
      ;;
    SHOULD\ *)
      _crit_severity="SHOULD"
      body="${body#SHOULD }"
      ;;
    *)
      return 1
      ;;
  esac

  # Extract verb + arg
  case "$body" in
    "contain heading: "*)
      _crit_verb="contain heading"
      _crit_arg="${body#contain heading: }"
      ;;
    "contain phrase: "*)
      _crit_verb="contain phrase"
      _crit_arg="${body#contain phrase: }"
      ;;
    "mention paths: "*)
      _crit_verb="mention paths"
      _crit_arg="${body#mention paths: }"
      ;;
    "have token count between "*)
      _crit_verb="have token count"
      _crit_arg="${body#have token count }"
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

# ─── Resolve name → lock version → cache path ─────────────────────────────────

resolve_member_cache() {
  local name="$1"
  local version
  version="$(lock_member_version "$name")"

  if [[ -z "$version" ]]; then
    printf 'canary: %s is not in eidolons.lock. Run '"'"'eidolons add %s'"'"'.\n' "$name" "$name" >&2
    exit 2
  fi

  local cache_dir="$CACHE_DIR/$name@$version"
  # If cache is missing, try to fetch (prompt+validate modes only; list mode skips)
  if [[ ! -d "$cache_dir/.git" ]]; then
    warn "Cache for $name@$version not found. Run 'eidolons sync' to populate."
    printf 'canary: cache for %s@%s missing. Run '"'"'eidolons sync'"'"' first.\n' "$name" "$version" >&2
    exit 2
  fi

  echo "$cache_dir"
}

# ─── JSON emitters ────────────────────────────────────────────────────────────

_json_string() {
  # Minimal JSON string escaping via python3 (always available) or sed fallback.
  local s="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$s"
  else
    # Fallback: escape backslash, double-quote, newline
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    printf '"%s"' "$s"
  fi
}

# ─── MODE: list ───────────────────────────────────────────────────────────────

run_list_mode() {
  # Gather member list: prefer lock, fall back to roster
  local members=""
  local using_lock=true
  if [[ -f "$PROJECT_LOCK" ]]; then
    members="$(yaml_to_json "$PROJECT_LOCK" | jq -r '(.members // []) | map(.name) | .[]')"
  else
    warn "No eidolons.lock found; listing roster members instead."
    members="$(roster_list_names)"
    using_lock=false
  fi

  if [[ -z "$members" ]]; then
    warn "No members found in lock or roster."
    exit 0
  fi

  local parsed_count=0
  local legacy_count=0
  local miss_count=0
  local list_lines=""

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue

    local version=""
    if [[ "$using_lock" == "true" ]]; then
      version="$(lock_member_version "$name")"
    fi
    if [[ -z "$version" ]]; then
      # Fall back to roster latest
      version="$(roster_get "$name" 2>/dev/null | jq -r '.versions.latest // "unknown"' 2>/dev/null || echo "unknown")"
    fi

    local cache_dir="$CACHE_DIR/$name@$version"
    local missions_file="$cache_dir/evals/canary-missions.md"

    if [[ -f "$missions_file" ]]; then
      local ids
      ids="$(list_mission_ids "$missions_file" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      local count
      # Use awk for counting to avoid grep exit-code 1 on empty input under pipefail
      count="$(list_mission_ids "$missions_file" | awk 'NF{n++} END{print n+0}')"
      if [[ "$count" -gt 0 ]]; then
        list_lines="${list_lines}PARSED|${name}|${version}|${count}|${ids}"$'\n'
        parsed_count=$((parsed_count + 1))
      else
        list_lines="${list_lines}LEGACY|${name}|${version}|0|"$'\n'
        legacy_count=$((legacy_count + 1))
      fi
    else
      if [[ ! -d "$cache_dir/.git" ]]; then
        list_lines="${list_lines}NOCACHE|${name}|${version}|0|"$'\n'
      else
        list_lines="${list_lines}MISS|${name}|${version}|0|"$'\n'
      fi
      miss_count=$((miss_count + 1))
    fi
  done <<< "$members"

  if [[ "$JSON" == "true" ]]; then
    # Build JSON output
    local json_entries=""
    local first=true
    while IFS='|' read -r jstate jname jver jcount jids; do
      [[ -z "$jstate" ]] && continue
      local jstatus
      case "$jstate" in
        PARSED)  jstatus="parsed" ;;
        LEGACY)  jstatus="legacy" ;;
        *)       jstatus="missing" ;;
      esac
      local entry
      entry="$(printf '{"name":%s,"version":%s,"status":%s,"mission_count":%s,"mission_ids":%s}' \
        "$(_json_string "$jname")" \
        "$(_json_string "$jver")" \
        "$(_json_string "$jstatus")" \
        "$jcount" \
        "$(_json_string "$jids")")"
      if [[ "$first" == "true" ]]; then
        json_entries="$entry"
        first=false
      else
        json_entries="$json_entries,$entry"
      fi
    done <<< "$list_lines"
    printf '{"schema_version":"1.1","mode":"list","summary":{"parsed":%d,"legacy":%d,"missing":%d},"members":[%s]}\n' \
      "$parsed_count" "$legacy_count" "$miss_count" "$json_entries"
    return 0
  fi

  # Human output — reprint with real symbols
  printf 'Canary mission status:\n'
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local version=""
    if [[ "$using_lock" == "true" ]]; then
      version="$(lock_member_version "$name")"
    fi
    if [[ -z "$version" ]]; then
      version="$(roster_get "$name" 2>/dev/null | jq -r '.versions.latest // "unknown"' 2>/dev/null || echo "unknown")"
    fi
    local cache_dir="$CACHE_DIR/$name@$version"
    local missions_file="$cache_dir/evals/canary-missions.md"
    if [[ -f "$missions_file" ]]; then
      local ids
      ids="$(list_mission_ids "$missions_file" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      local count
      count="$(list_mission_ids "$missions_file" | awk 'NF{n++} END{print n+0}')"
      if [[ "$count" -gt 0 ]]; then
        # ✓ U+2713 = \xe2\x9c\x93
        printf '  \xe2\x9c\x93 %s@%s  (%d mission(s): %s)\n' "$name" "$version" "$count" "$ids"
      else
        # ⚠ U+26A0 = \xe2\x9a\xa0
        printf '  \xe2\x9a\xa0 %s@%s  (file present, 0 missions in v1.13.0 DSL format)\n' "$name" "$version"
      fi
    else
      if [[ ! -d "$cache_dir/.git" ]]; then
        # · U+00B7 = \xc2\xb7
        printf '  \xc2\xb7 %s@%s  (cache not populated; run '"'"'eidolons sync'"'"')\n' "$name" "$version"
      else
        # · U+00B7 = \xc2\xb7
        printf '  \xc2\xb7 %s@%s  (no canary missions authored)\n' "$name" "$version"
      fi
    fi
  done <<< "$members"

  printf '\n%d with parseable missions, %d with file-only (legacy format), %d with no file\n' \
    "$parsed_count" "$legacy_count" "$miss_count"
}

# ─── MODE: memory ─────────────────────────────────────────────────────────────
#
# Recall-only crystalium liveness probe, reusing the same gate + docker-args
# transform as 'eidolons memory preflight' and doctor D13
# (deep_check_memory_recallability), via lib_memory_probe.sh.
#
# NOT a write->recall round trip. Investigated crystalium's own `canary` CLI
# subcommand first (python -m crystalium canary): it dispatches to
# evals.ab_memory_onoff.run_all, which runs a 10-mission memory-on/off A/B
# ablation eval against a FRESH EPHEMERAL data_dir it creates per run — not
# the live, mounted project store this command is meant to check. Surfacing
# its result here would silently answer a different question than the one
# asked ("is THIS project's live memory reachable and non-empty?"), so it is
# deliberately not invoked. crystalium's write path (`commit`) is MCP-only
# (server.py handlers) and not reachable from a one-shot CLI invocation, so a
# true write->recall round trip isn't buildable from bash either. This mode
# therefore degrades to a recall-only liveness check and says so explicitly.
#
# PASS/FAIL/SKIP/INCONCLUSIVE, consistent with the vocabulary used by the
# --validate mode's criteria evaluator:
#   crystalium not gated in       -> SKIP  (exit 0)
#   docker not on PATH            -> SKIP  (exit 0)
#   invocation cannot be built /
#   docker unreachable / timeout /
#   malformed output              -> FAIL  (exit 1)
#   probe recall returns 0 records -> INCONCLUSIVE (exit 0)
#   probe recall returns >0 records -> PASS (exit 0)
run_memory_mode() {
  local project_root; project_root="$(pwd)"

  printf '═══════════════════════════════════════════════════════════════\n'
  printf 'canary --memory — crystalium recall-only liveness probe\n'
  printf '═══════════════════════════════════════════════════════════════\n'
  printf '\n'
  printf 'What this checks:\n'
  printf '  - crystalium CLI reachability via the docker transform (same path as\n'
  printf '    eidolons memory preflight / doctor --deep D13).\n'
  printf '  - a probe recall (--k 3) against the live, mounted project store.\n'
  printf '\n'
  printf 'What this does NOT check:\n'
  printf '  - a true write -> recall round trip. crystalium'"'"'s own `canary` CLI\n'
  printf '    subcommand runs a 10-mission A/B eval against a fresh EPHEMERAL\n'
  printf '    store (not the live project store), so it is not surfaced here.\n'
  printf '  - the write (`commit`) path, which is MCP-only and unreachable from bash.\n'
  printf '\n'

  if ! memory_probe_gated_in "$project_root"; then
    printf 'SKIP — crystalium not gated in (.mcp.json + eidolons.mcp.lock)\n'
    exit 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    printf 'SKIP — docker not on PATH\n'
    exit 0
  fi

  local slug q_query q_slug recall_args script
  slug="$(memory_probe_project_slug "$project_root")"
  q_query="$(memory_probe_quote "project")"
  q_slug="$(memory_probe_quote "$slug")"
  recall_args="recall --query $q_query --scope-project $q_slug --k 3 --format json"

  script="$(mktemp)"
  if ! memory_probe_build_docker_script "$project_root" "$recall_args" "$script"; then
    printf "FAIL — could not resolve a recall invocation ('serve' not found in .mcp.json crystalium args)\n"
    rm -f "$script"
    exit 1
  fi

  local out exit_code=0
  out="$(with_timeout 10 bash "$script" 2>/dev/null)" || exit_code=$?
  rm -f "$script"

  if [[ "$exit_code" -ne 0 ]]; then
    printf 'FAIL — crystalium unreachable for probe (exit %s)\n' "$exit_code"
    exit 1
  fi

  if ! printf '%s' "$out" | jq empty >/dev/null 2>&1; then
    printf 'FAIL — crystalium unreachable for probe (malformed output)\n'
    exit 1
  fi

  local count
  count="$(printf '%s' "$out" | jq -r '(.records // []) | length' 2>/dev/null || echo "0")"
  if [[ "$count" -eq 0 ]]; then
    printf 'INCONCLUSIVE — crystalium reachable; 0 records returned by probe recall (store may be empty/mis-scoped)\n'
    exit 0
  fi

  printf 'PASS — crystalium reachable; probe recall returned %s record(s)\n' "$count"
  exit 0
}

# ─── MODE: host / all-hosts ───────────────────────────────────────────────────
#
# Compares the EFFECTIVE on-disk harness state against eidolons.lock's
# harness.{hosts_wired,strict,strict_modes,shim_paths} claim, mirroring the
# probes doctor's D12 (deep_check_harness_consistency, cli/src/lib.sh) derives
# — shims present+executable, host settings/hooks file present+valid (+wired
# entries for claude-code), strict recorded backed by a PreToolUse shim (+
# opencode's advisory-only strict_modes rule; cursor strict is unsound/out of
# scope, mirroring D12's err there). Unlike D12 (one aggregate pass/fail
# count across every host), this emits ONE PASS/FAIL/SKIP verdict per host:
#   SKIP — lock does not claim the host is wired (or no harness: key at all).
#   FAIL — lock claims the host is wired but reality does not back the claim.
#   PASS — lock claims the host is wired and every probe for it is backed.

_CANARY_KNOWN_HOSTS="claude-code codex copilot cursor opencode"

_canary_known_host() {
  local h="$1" k
  for k in $_CANARY_KNOWN_HOSTS; do
    [[ "$h" == "$k" ]] && return 0
  done
  return 1
}

# _canary_host_probe HOST LOCK_JSON → sets _HOST_VERDICT (PASS|FAIL|SKIP) and
# _HOST_REASONS (semicolon-joined) as PLAIN GLOBALS. Call as a bare statement
# — NEVER via $(...) — command substitution runs the function body in a
# subshell, and its variable assignments would never reach the caller.
_canary_host_probe() {
  local host="$1" lock_json="$2"
  _HOST_VERDICT=""
  _HOST_REASONS=""

  local schema
  schema="$(printf '%s' "$lock_json" | jq -r '.harness.schema_version // "absent"' 2>/dev/null || echo "absent")"
  if [[ "$schema" == "absent" ]]; then
    _HOST_REASONS="harness not installed (no harness: key in eidolons.lock)"
    _HOST_VERDICT="SKIP"
    return 0
  fi

  local hosts_wired
  hosts_wired="$(printf '%s' "$lock_json" | jq -r '(.harness.hosts_wired // []) | join(",")' 2>/dev/null || echo "")"
  if ! printf '%s' ",$hosts_wired," | grep -q ",$host,"; then
    _HOST_REASONS="lock does not claim $host is wired (not in harness.hosts_wired)"
    _HOST_VERDICT="SKIP"
    return 0
  fi

  local strict_wired is_strict
  strict_wired="$(printf '%s' "$lock_json" | jq -r '(.harness.strict // []) | join(",")' 2>/dev/null || echo "")"
  is_strict=false
  printf '%s' ",$strict_wired," | grep -q ",$host," && is_strict=true

  local fail_count=0

  if [[ "$host" == "cursor" && "$is_strict" == true ]]; then
    _HOST_REASONS="${_HOST_REASONS}cursor in strict[] is unsound (out of P3 scope); "
    fail_count=$((fail_count + 1))
  fi

  # Shim checks: every shim_path in the lock whose basename is prefixed
  # "<host>-" must exist and be executable.
  local sp
  while IFS= read -r sp; do
    [[ -z "$sp" ]] && continue
    case "$(basename "$sp")" in
      "${host}-"*) : ;;
      *) continue ;;
    esac
    if [[ ! -f "$sp" ]]; then
      _HOST_REASONS="${_HOST_REASONS}shim missing: $sp; "
      fail_count=$((fail_count + 1))
    elif [[ ! -x "$sp" ]]; then
      _HOST_REASONS="${_HOST_REASONS}shim not executable: $sp; "
      fail_count=$((fail_count + 1))
    fi
  done < <(printf '%s' "$lock_json" | jq -r '(.harness.shim_paths // [])[]' 2>/dev/null)

  case "$host" in
    claude-code)
      if [[ ! -f .claude/settings.json ]]; then
        _HOST_REASONS="${_HOST_REASONS}.claude/settings.json missing; "
        fail_count=$((fail_count + 1))
      elif ! jq empty .claude/settings.json 2>/dev/null; then
        _HOST_REASONS="${_HOST_REASONS}.claude/settings.json is not valid JSON; "
        fail_count=$((fail_count + 1))
      else
        local ups_n
        ups_n="$(jq -r '(.hooks.UserPromptSubmit // []) | map(.hooks[]?.command? // "") | map(select(startswith(".eidolons/harness/"))) | length' .claude/settings.json 2>/dev/null || echo "0")"
        if [[ "$ups_n" == "0" ]]; then
          _HOST_REASONS="${_HOST_REASONS}.claude/settings.json missing eidolons UserPromptSubmit entry; "
          fail_count=$((fail_count + 1))
        fi
      fi
      if [[ "$is_strict" == true ]] && [[ ! -x .eidolons/harness/hooks/claude-code-PreToolUse.sh ]]; then
        _HOST_REASONS="${_HOST_REASONS}strict recorded but claude-code-PreToolUse.sh missing/not-executable; "
        fail_count=$((fail_count + 1))
      fi
      ;;
    codex)
      if [[ ! -f .codex/hooks.json ]]; then
        _HOST_REASONS="${_HOST_REASONS}.codex/hooks.json missing; "
        fail_count=$((fail_count + 1))
      elif ! jq empty .codex/hooks.json 2>/dev/null; then
        _HOST_REASONS="${_HOST_REASONS}.codex/hooks.json is not valid JSON; "
        fail_count=$((fail_count + 1))
      fi
      if [[ "$is_strict" == true ]] && [[ ! -x .eidolons/harness/hooks/codex-PreToolUse.sh ]]; then
        _HOST_REASONS="${_HOST_REASONS}strict recorded but codex-PreToolUse.sh missing/not-executable; "
        fail_count=$((fail_count + 1))
      fi
      ;;
    copilot)
      if [[ ! -x .eidolons/harness/hooks/copilot-SessionStart.sh ]]; then
        _HOST_REASONS="${_HOST_REASONS}copilot-SessionStart.sh missing/not-executable; "
        fail_count=$((fail_count + 1))
      fi
      ;;
    opencode)
      if [[ "$is_strict" == true ]]; then
        local oc_mode
        oc_mode="$(printf '%s' "$lock_json" | jq -r '.harness.strict_modes.opencode // "absent"' 2>/dev/null || echo "absent")"
        if [[ "$oc_mode" != "advisory" ]]; then
          _HOST_REASONS="${_HOST_REASONS}strict_modes.opencode != advisory (got: $oc_mode); "
          fail_count=$((fail_count + 1))
        fi
        if [[ ! -f .opencode/plugins/eidolons.js ]]; then
          _HOST_REASONS="${_HOST_REASONS}strict recorded but .opencode/plugins/eidolons.js missing; "
          fail_count=$((fail_count + 1))
        fi
      fi
      ;;
    cursor)
      : # base tier has no dedicated on-disk surface (no shims, no settings
        # file) — hosts_wired membership + the strict[] check above are all
        # D12 checks for cursor.
      ;;
  esac

  if [[ "$fail_count" -eq 0 ]]; then
    _HOST_VERDICT="PASS"
  else
    _HOST_VERDICT="FAIL"
  fi
  return 0
}

_canary_load_lock_json() {
  if [[ -f "$PROJECT_LOCK" ]]; then
    yaml_to_json "$PROJECT_LOCK" 2>/dev/null || echo '{}'
  else
    echo '{}'
  fi
}

run_host_mode() {
  local host="$1"
  if ! _canary_known_host "$host"; then
    printf 'canary: unknown host: %s (want one of: %s)\n' "$host" "$_CANARY_KNOWN_HOSTS" >&2
    exit 2
  fi

  local lock_json
  lock_json="$(_canary_load_lock_json)"
  _canary_host_probe "$host" "$lock_json"
  local verdict="$_HOST_VERDICT" reasons="$_HOST_REASONS"

  if [[ "$JSON" == "true" ]]; then
    printf '{"schema_version":"1.0","mode":"host","results":[{"host":%s,"verdict":%s,"reason":%s}]}\n' \
      "$(_json_string "$host")" "$(_json_string "$verdict")" "$(_json_string "$reasons")"
  else
    printf 'eidolons canary --host %s\n' "$host"
    printf '  %s — %s\n' "$verdict" "${reasons:-lock claim backed by on-disk reality}"
  fi

  [[ "$verdict" == "FAIL" ]] && exit 1
  exit 0
}

run_all_hosts_mode() {
  local lock_json any_fail=false
  lock_json="$(_canary_load_lock_json)"

  [[ "$JSON" == "true" ]] || printf 'eidolons canary --all-hosts\n'

  local json_entries="" first=true
  local h verdict reasons
  for h in $_CANARY_KNOWN_HOSTS; do
    _canary_host_probe "$h" "$lock_json"
    verdict="$_HOST_VERDICT"
    reasons="$_HOST_REASONS"
    [[ "$verdict" == "FAIL" ]] && any_fail=true
    if [[ "$JSON" == "true" ]]; then
      local entry
      entry="$(printf '{"host":%s,"verdict":%s,"reason":%s}' \
        "$(_json_string "$h")" "$(_json_string "$verdict")" "$(_json_string "$reasons")")"
      if [[ "$first" == "true" ]]; then json_entries="$entry"; first=false; else json_entries="$json_entries,$entry"; fi
    else
      printf '  %-12s %s — %s\n' "$h" "$verdict" "${reasons:-lock claim backed by on-disk reality}"
    fi
  done

  if [[ "$JSON" == "true" ]]; then
    printf '{"schema_version":"1.0","mode":"all-hosts","results":[%s]}\n' "$json_entries"
  fi

  [[ "$any_fail" == "true" ]] && exit 1
  exit 0
}

# ─── MODE: prompt ─────────────────────────────────────────────────────────────

run_prompt_mode() {
  local name="$1"
  # Verify name is in lock (require lock for prompt mode)
  if [[ ! -f "$PROJECT_LOCK" ]]; then
    printf 'canary: no eidolons.lock found. Run '"'"'eidolons add %s'"'"'.\n' "$name" >&2
    exit 2
  fi

  # Check name is in roster (for unknown name detection)
  if ! roster_list_names 2>/dev/null | grep -Fxq "$name"; then
    printf 'canary: %s is not a known Eidolon.\n' "$name" >&2
    exit 2
  fi

  local version
  version="$(lock_member_version "$name")"
  if [[ -z "$version" ]]; then
    printf 'canary: %s is not in eidolons.lock. Run '"'"'eidolons add %s'"'"'.\n' "$name" "$name" >&2
    exit 2
  fi

  local cache_dir="$CACHE_DIR/$name@$version"
  if [[ ! -d "$cache_dir/.git" ]]; then
    printf 'canary: cache for %s@%s missing. Run '"'"'eidolons sync'"'"' first.\n' "$name" "$version" >&2
    exit 2
  fi

  local missions_file="$cache_dir/evals/canary-missions.md"
  if [[ ! -f "$missions_file" ]]; then
    warn "Canary missions not available for $name@$version"
    warn "  This Eidolon has not authored evals/canary-missions.md yet."
    exit 0
  fi

  # Resolve mission ID
  local mission_id="$MISSION_ID"
  if [[ -z "$mission_id" ]]; then
    mission_id="$(first_mission_id "$missions_file")"
  fi

  if [[ -z "$mission_id" ]]; then
    warn "No missions found in $missions_file."
    exit 0
  fi

  # Extract the mission block to a tmpfile
  local mission_tmp
  mission_tmp="$(mktemp /tmp/canary-mission-XXXXXX)"
  extract_mission "$missions_file" "$mission_id" > "$mission_tmp"

  if [[ ! -s "$mission_tmp" ]]; then
    local avail_ids
    avail_ids="$(list_mission_ids "$missions_file" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    rm -f "$mission_tmp"
    printf 'canary: Mission '"'"'%s'"'"' not found in %s. Available: %s\n' \
      "$mission_id" "$missions_file" "$avail_ids" >&2
    exit 2
  fi

  # Extract subsections
  local prompt_body shape_body crit_body
  prompt_body="$(extract_subsection_block "$mission_tmp" "Prompt")"
  shape_body="$(extract_subsection_block "$mission_tmp" "Expected output shape")"
  crit_body="$(extract_subsection_block "$mission_tmp" "Validation criteria")"

  rm -f "$mission_tmp"

  if [[ "$JSON" == "true" ]]; then
    printf '{"schema_version":"1.0","mode":"prompt","eidolon":%s,"version":%s,"mission_id":%s,"prompt":%s,"expected_output_shape":%s,"validation_criteria":%s}\n' \
      "$(_json_string "$name")" \
      "$(_json_string "$version")" \
      "$(_json_string "$mission_id")" \
      "$(_json_string "$prompt_body")" \
      "$(_json_string "$shape_body")" \
      "$(_json_string "$crit_body")"
    return 0
  fi

  printf '═══════════════════════════════════════════════════════════════\n'
  printf 'Eidolon: %s@%s — Mission: %s\n' "$name" "$version" "$mission_id"
  printf '═══════════════════════════════════════════════════════════════\n'
  printf '\n'
  printf '─── Prompt ─────────────────────────────────────────────────────\n'
  printf '%s\n' "$prompt_body"
  printf '\n'
  printf '─── Expected output shape ──────────────────────────────────────\n'
  printf '%s\n' "$shape_body"
  printf '\n'
  printf '─── Validation criteria ────────────────────────────────────────\n'
  printf '%s\n' "$crit_body"
  printf '\n'
  printf '═══════════════════════════════════════════════════════════════\n'
  printf 'Copy the prompt above into your LLM, save the response, then run:\n'
  printf '  eidolons canary %s --validate <file>\n' "$name"
  printf '═══════════════════════════════════════════════════════════════\n'
}

# ─── MODE: validate ───────────────────────────────────────────────────────────

run_validate_mode() {
  local name="$1" validate_file="$2"

  # File must exist and be readable
  if [[ ! -f "$validate_file" ]]; then
    printf 'canary: validation file not found: %s\n' "$validate_file" >&2
    exit 2
  fi
  if [[ ! -r "$validate_file" ]]; then
    printf 'canary: validation file not readable: %s\n' "$validate_file" >&2
    exit 2
  fi

  # Verify name is in lock
  if [[ ! -f "$PROJECT_LOCK" ]]; then
    printf 'canary: no eidolons.lock found. Run '"'"'eidolons add %s'"'"'.\n' "$name" >&2
    exit 2
  fi

  if ! roster_list_names 2>/dev/null | grep -Fxq "$name"; then
    printf 'canary: %s is not a known Eidolon.\n' "$name" >&2
    exit 2
  fi

  local version
  version="$(lock_member_version "$name")"
  if [[ -z "$version" ]]; then
    printf 'canary: %s is not in eidolons.lock. Run '"'"'eidolons add %s'"'"'.\n' "$name" "$name" >&2
    exit 2
  fi

  local cache_dir="$CACHE_DIR/$name@$version"
  if [[ ! -d "$cache_dir/.git" ]]; then
    printf 'canary: cache for %s@%s missing. Run '"'"'eidolons sync'"'"' first.\n' "$name" "$version" >&2
    exit 2
  fi

  local missions_file="$cache_dir/evals/canary-missions.md"
  if [[ ! -f "$missions_file" ]]; then
    warn "Canary missions not available for $name@$version"
    warn "  This Eidolon has not authored evals/canary-missions.md yet."
    exit 0
  fi

  local mission_id="$MISSION_ID"
  if [[ -z "$mission_id" ]]; then
    mission_id="$(first_mission_id "$missions_file")"
  fi

  if [[ -z "$mission_id" ]]; then
    warn "No missions found in $missions_file."
    exit 0
  fi

  local mission_tmp
  mission_tmp="$(mktemp /tmp/canary-mission-XXXXXX)"
  extract_mission "$missions_file" "$mission_id" > "$mission_tmp"

  if [[ ! -s "$mission_tmp" ]]; then
    local avail_ids
    avail_ids="$(list_mission_ids "$missions_file" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    rm -f "$mission_tmp"
    printf 'canary: Mission '"'"'%s'"'"' not found in %s. Available: %s\n' \
      "$mission_id" "$missions_file" "$avail_ids" >&2
    exit 2
  fi

  local crit_body
  crit_body="$(extract_subsection_block "$mission_tmp" "Validation criteria")"
  rm -f "$mission_tmp"

  # Check for empty validate file
  local output_size
  output_size="$(wc -c < "$validate_file" | tr -d '[:space:]')"
  if [[ "$output_size" -eq 0 ]]; then
    warn "Validation file is empty — reporting all criteria as INCONCLUSIVE"
    # Report all criteria as INCONCLUSIVE
    local inc_count=0
    local json_criteria=""
    local first=true
    if [[ -n "$crit_body" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        case "$line" in
          -\ MUST\ *|-\ SHOULD\ *)
            inc_count=$((inc_count + 1))
            printf '  [INCONCLUSIVE] %s (empty file)\n' "$line"
            if [[ "$JSON" == "true" ]]; then
              local entry
              entry="$(printf '{"criterion":%s,"severity":"MUST","result":"INCONCLUSIVE","reason":"empty file"}' \
                "$(_json_string "$line")")"
              if [[ "$first" == "true" ]]; then json_criteria="$entry"; first=false;
              else json_criteria="$json_criteria,$entry"; fi
            fi
            ;;
        esac
      done <<< "$crit_body"
    fi
    printf '\n0 pass, 0 fail, %d inconclusive\n' "$inc_count"
    if [[ "$JSON" == "true" ]]; then
      printf '{"schema_version":"1.0","mode":"validate","eidolon":%s,"version":%s,"mission_id":%s,"summary":{"pass":0,"fail":0,"inconclusive":%d},"criteria":[%s]}\n' \
        "$(_json_string "$name")" "$(_json_string "$version")" "$(_json_string "$mission_id")" \
        "$inc_count" "$json_criteria"
    fi
    exit 0
  fi

  # Run through criteria
  local pass_count=0 fail_count=0 inc_count=0
  local report_lines=""
  local json_criteria=""
  local json_first=true

  if [[ -n "$crit_body" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      # Only process lines that look like criteria
      case "$line" in
        -\ MUST\ *|-\ SHOULD\ *)
          : ;;
        *)
          continue
          ;;
      esac

      local _crit_severity="" _crit_verb="" _crit_arg=""
      local parsed=true
      parse_criterion "$line" || parsed=false

      local result reason
      if [[ "$parsed" == "false" || -z "$_crit_verb" ]]; then
        result="INCONCLUSIVE"
        reason="unrecognized criterion"
      else
        result="$(evaluate_criterion "$_crit_verb" "$_crit_arg" "$validate_file")"
        reason=""
        # Downgrade SHOULD FAIL → INCONCLUSIVE
        if [[ "$_crit_severity" == "SHOULD" && "$result" == "FAIL" ]]; then
          result="INCONCLUSIVE"
          reason="SHOULD criterion failed"
        fi
      fi

      local display_line
      if [[ -n "$reason" ]]; then
        display_line="$(printf '  [%s] %s (%s)' "$result" "$line" "$reason")"
      else
        display_line="$(printf '  [%s] %s' "$result" "$line")"
      fi
      report_lines="${report_lines}${display_line}"$'\n'

      case "$result" in
        PASS)        pass_count=$((pass_count + 1)) ;;
        FAIL)        fail_count=$((fail_count + 1)) ;;
        INCONCLUSIVE) inc_count=$((inc_count + 1)) ;;
      esac

      if [[ "$JSON" == "true" ]]; then
        local sev="${_crit_severity:-UNKNOWN}"
        local entry
        entry="$(printf '{"criterion":%s,"severity":%s,"result":%s,"reason":%s}' \
          "$(_json_string "$line")" \
          "$(_json_string "$sev")" \
          "$(_json_string "$result")" \
          "$(_json_string "$reason")")"
        if [[ "$json_first" == "true" ]]; then
          json_criteria="$entry"; json_first=false
        else
          json_criteria="$json_criteria,$entry"
        fi
      fi
    done <<< "$crit_body"
  fi

  if [[ "$JSON" == "true" ]]; then
    printf '{"schema_version":"1.0","mode":"validate","eidolon":%s,"version":%s,"mission_id":%s,"summary":{"pass":%d,"fail":%d,"inconclusive":%d},"criteria":[%s]}\n' \
      "$(_json_string "$name")" "$(_json_string "$version")" "$(_json_string "$mission_id")" \
      "$pass_count" "$fail_count" "$inc_count" "$json_criteria"
    if [[ "$fail_count" -gt 0 ]]; then exit 1; fi
    exit 0
  fi

  printf '%s' "$report_lines"
  printf '\n%d pass, %d fail, %d inconclusive\n' "$pass_count" "$fail_count" "$inc_count"

  if [[ "$fail_count" -gt 0 ]]; then exit 1; fi
  exit 0
}

# ─── Main dispatch ────────────────────────────────────────────────────────────

nexus_refresh

if [[ "$LIST_MODE" == "true" ]]; then
  run_list_mode
  exit 0
fi

if [[ "$MEMORY_MODE" == "true" ]]; then
  run_memory_mode
fi

if [[ "$ALL_HOSTS_MODE" == "true" ]]; then
  run_all_hosts_mode
fi

if [[ -n "$HOST_NAME" ]]; then
  run_host_mode "$HOST_NAME"
fi

if [[ -z "$NAME" ]]; then
  usage >&2
  exit 2
fi

if [[ -n "$VALIDATE_FILE" ]]; then
  run_validate_mode "$NAME" "$VALIDATE_FILE"
else
  run_prompt_mode "$NAME"
fi
