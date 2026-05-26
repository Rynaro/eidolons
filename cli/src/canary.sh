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
#
# Bash 3.2 compatible: no associative arrays, no mapfile/readarray,
# no ${var,,}, no &>>, no process-substitution with exit-code dependence.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
eidolons canary — Layer 3 integrity: print canary prompt or validate LLM output
against an Eidolon's per-version canary mission.

Usage:
  eidolons canary <name>                       Print canary prompt + criteria
  eidolons canary <name> --validate <file>     Validate saved LLM output
  eidolons canary --list                       List Eidolons with/without missions

Options:
  --validate <file>    Validate LLM response from file against mission criteria
  --list               Scan cache; report mission availability per Eidolon
  --mission <id>       Select non-default mission by ID
  --json               Emit machine-readable JSON on stdout
  -h, --help           Show this help

Exit codes:
  0   Prompt printed / validation PASS (or INCONCLUSIVE only) / list printed
  1   Validation had ≥1 FAIL criterion
  2   Misuse: unknown name, missing file, unknown flag

What it does:
  1. 'eidolons canary <name>' reads <cache>/evals/canary-missions.md and prints
     the mission prompt + expected output shape + validation criteria.
  2. User runs the prompt in their LLM environment of choice and saves the response.
  3. 'eidolons canary <name> --validate <file>' checks the saved output against
     the structured criteria (MUST/SHOULD × 4 verbs).
  4. '--list' scans the per-version cache for every lock member and reports
     which have canary missions authored.

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
MISSION_ID=""
JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      LIST_MODE=true
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

  local have_count=0
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

    local line
    if [[ -f "$missions_file" ]]; then
      local ids
      ids="$(list_mission_ids "$missions_file" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      local count
      # Use awk for counting to avoid grep exit-code 1 on empty input under pipefail
      count="$(list_mission_ids "$missions_file" | awk 'NF{n++} END{print n+0}')"
      line="  checkmark $name@$version  ($count mission(s): $ids)"
      list_lines="${list_lines}HAVE|${name}|${version}|${count}|${ids}"$'\n'
      have_count=$((have_count + 1))
    else
      if [[ ! -d "$cache_dir/.git" ]]; then
        line="  dot $name@$version  (cache not populated; run 'eidolons sync')"
        list_lines="${list_lines}MISS|${name}|${version}|0|"$'\n'
      else
        line="  dot $name@$version  (no canary missions authored)"
        list_lines="${list_lines}MISS|${name}|${version}|0|"$'\n'
      fi
      miss_count=$((miss_count + 1))
    fi
  done <<< "$members"

  if [[ "$JSON" == "true" ]]; then
    # Build JSON output
    local json_entries=""
    local first=true
    while IFS='|' read -r status jname jver jcount jids; do
      [[ -z "$status" ]] && continue
      local has_missions="false"
      [[ "$status" == "HAVE" ]] && has_missions="true"
      local entry
      entry="$(printf '{"name":%s,"version":%s,"has_missions":%s,"mission_count":%s,"mission_ids":%s}' \
        "$(_json_string "$jname")" \
        "$(_json_string "$jver")" \
        "$has_missions" \
        "$jcount" \
        "$(_json_string "$jids")")"
      if [[ "$first" == "true" ]]; then
        json_entries="$entry"
        first=false
      else
        json_entries="$json_entries,$entry"
      fi
    done <<< "$list_lines"
    printf '{"schema_version":"1.0","mode":"list","summary":{"with_missions":%d,"without_missions":%d},"members":[%s]}\n' \
      "$have_count" "$miss_count" "$json_entries"
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
      printf '  \xe2\x9c\x93 %s@%s  (%d mission(s): %s)\n' "$name" "$version" "$count" "$ids"
    else
      if [[ ! -d "$cache_dir/.git" ]]; then
        printf '  \xc2\xb7 %s@%s  (cache not populated; run '"'"'eidolons sync'"'"')\n' "$name" "$version"
      else
        printf '  \xc2\xb7 %s@%s  (no canary missions authored)\n' "$name" "$version"
      fi
    fi
  done <<< "$members"

  printf '\n%d with missions, %d without\n' "$have_count" "$miss_count"
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

if [[ -z "$NAME" ]]; then
  usage >&2
  exit 2
fi

if [[ -n "$VALIDATE_FILE" ]]; then
  run_validate_mode "$NAME" "$VALIDATE_FILE"
else
  run_prompt_mode "$NAME"
fi
