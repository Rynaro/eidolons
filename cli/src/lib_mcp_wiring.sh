#!/usr/bin/env bash
# cli/src/lib_mcp_wiring.sh — catalogue-driven MCP-to-Eidolon tool-surface wiring.
#
# SOURCE this file; do NOT execute it directly.
# Requires lib.sh and lib_mcp.sh to have been sourced first.
#
# Public API:
#   mcp_wiring_patch_agent_file   HOST AGENT_FILE MCP_NAME EXPOSES_GLOB
#   mcp_wiring_unpatch_agent_file HOST AGENT_FILE MCP_NAME EXPOSES_GLOB
#   mcp_wiring_grant_targets      MCP_NAME → echoes "host\tfile_path" per line (stdout)
#   mcp_wiring_apply_for_mcp      MCP_NAME → patches every (host, file) pair
#   mcp_wiring_unapply_for_mcp    MCP_NAME → reverses wiring for one MCP
#   mcp_wiring_reapply_all        → idempotent re-application of every locked MCP
#
# Spec:  .spectra/plans/2026-05-25-mcp-eidolon-wiring-spec.md
# Scout: .spectra/plans/2026-05-25-mcp-eidolon-wiring-observations.md
#
# Patching strategies per host:
#   (a) claude-code CSV append   — existing `tools: A, B` → append `, mcp__X__*`
#   (b) claude-code none-replace — `tools: none` → `tools: mcp__X__*`
#   (c) claude-code insert       — no `tools:` line → insert before closing `---`
#   (d) codex block-seq append   — `tools:\n  - A` → append `  - mcp__X__*` item
#
# Idempotency anchor: `x-eidolons-mcp-wired: [<sorted mcp names>]` in frontmatter.
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

# Guard against double-source.
if [ -n "${_LIB_MCP_WIRING_LOADED:-}" ]; then
  return 0
fi
_LIB_MCP_WIRING_LOADED=1

# ─── Internal helpers ─────────────────────────────────────────────────────────

# _mcp_wiring_read_sentinel FILE → echo sorted CSV of already-wired MCP names;
# empty string when the sentinel is absent.
# Reads the `x-eidolons-mcp-wired:` inline-list from the YAML frontmatter.
# Uses awk only (no pipeline loops) to avoid pipefail+EOF issues in bash 3.2.
_mcp_wiring_read_sentinel() {
  local file="$1"
  grep '^x-eidolons-mcp-wired:' "$file" 2>/dev/null | head -1 | awk '
  {
    # Strip the key prefix
    sub(/^x-eidolons-mcp-wired:[[:space:]]*/, "")
    # Strip surrounding brackets
    gsub(/^\[|\]$/, "")
    # Split on comma
    n = split($0, arr, ",")
    for (i = 1; i <= n; i++) {
      # Trim whitespace
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", arr[i])
      if (arr[i] != "") items[arr[i]] = 1
    }
    # Sort keys and output
    cnt = 0
    for (k in items) { keys[cnt++] = k }
    # Bubble sort (awk has no sort in POSIX)
    for (i = 0; i < cnt - 1; i++) {
      for (j = i + 1; j < cnt; j++) {
        if (keys[i] > keys[j]) { tmp = keys[i]; keys[i] = keys[j]; keys[j] = tmp }
      }
    }
    out = ""
    for (i = 0; i < cnt; i++) {
      if (i > 0) out = out ", "
      out = out keys[i]
    }
    printf "%s", out
  }
  ' || true
}

# _mcp_wiring_sentinel_has FILE MCP_NAME → return 0 if MCP_NAME is in sentinel.
_mcp_wiring_sentinel_has() {
  local file="$1"
  local mcp_name="$2"
  local existing
  existing="$(_mcp_wiring_read_sentinel "$file")"
  if [ -z "$existing" ]; then
    return 1
  fi
  # Check each element.
  local item
  printf '%s' "$existing" | tr ',' '\n' | while IFS= read -r item; do
    item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
    if [ "$item" = "$mcp_name" ]; then
      exit 0
    fi
  done && return 0 || return 1
}

# _mcp_wiring_sentinel_has_inline FILE MCP_NAME
# Returns 0 if MCP_NAME is in the inline sentinel list.
# Bash 3.2 safe version using awk to avoid subshell-in-loop issues.
_mcp_wiring_sentinel_has_inline() {
  local file="$1"
  local mcp_name="$2"
  local existing
  existing="$(_mcp_wiring_read_sentinel "$file")"
  if [ -z "$existing" ]; then
    return 1
  fi
  # Use awk to check for the word in a comma-separated list.
  printf '%s' "$existing" | awk -v name="$mcp_name" '
  BEGIN { found=0 }
  {
    n = split($0, arr, ",")
    for (i=1; i<=n; i++) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", arr[i])
      if (arr[i] == name) { found=1; exit }
    }
  }
  END { exit (found ? 0 : 1) }
  '
}

# _mcp_wiring_build_sentinel EXISTING_CSV NEW_MCP_NAME → sorted CSV including NEW_MCP_NAME.
# Uses awk only to avoid pipefail+EOF issues with bash 3.2.
_mcp_wiring_build_sentinel() {
  local existing_csv="$1"
  local new_name="$2"
  local combined
  if [ -z "$existing_csv" ]; then
    combined="$new_name"
  else
    combined="${existing_csv}, ${new_name}"
  fi
  # Sort unique entries using awk (no pipelines that fail on EOF).
  printf '%s' "$combined" | awk '
  {
    n = split($0, arr, ",")
    for (i = 1; i <= n; i++) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", arr[i])
      if (arr[i] != "") items[arr[i]] = 1
    }
  }
  END {
    cnt = 0
    for (k in items) { keys[cnt++] = k }
    for (i = 0; i < cnt - 1; i++) {
      for (j = i + 1; j < cnt; j++) {
        if (keys[i] > keys[j]) { tmp = keys[i]; keys[i] = keys[j]; keys[j] = tmp }
      }
    }
    out = ""
    for (i = 0; i < cnt; i++) {
      if (i > 0) out = out ", "
      out = out keys[i]
    }
    printf "%s", out
  }
  '
}

# _mcp_wiring_remove_from_sentinel EXISTING_CSV MCP_NAME → CSV without MCP_NAME.
# Uses awk only to avoid pipefail+EOF issues with bash 3.2.
_mcp_wiring_remove_from_sentinel() {
  local existing_csv="$1"
  local rm_name="$2"
  printf '%s' "$existing_csv" | awk -v rm="$rm_name" '
  {
    n = split($0, arr, ",")
    for (i = 1; i <= n; i++) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", arr[i])
      if (arr[i] != "" && arr[i] != rm) items[arr[i]] = 1
    }
  }
  END {
    cnt = 0
    for (k in items) { keys[cnt++] = k }
    for (i = 0; i < cnt - 1; i++) {
      for (j = i + 1; j < cnt; j++) {
        if (keys[i] > keys[j]) { tmp = keys[i]; keys[i] = keys[j]; keys[j] = tmp }
      }
    }
    out = ""
    for (i = 0; i < cnt; i++) {
      if (i > 0) out = out ", "
      out = out keys[i]
    }
    printf "%s", out
  }
  '
}

# _mcp_wiring_patch_claude_code FILE MCP_GLOB MCP_NAME → patch claude-code agent file.
# Handles strategies (a), (b), (c), and sentinel upsert.
# Atomic: writes to tmpfile then mv.
_mcp_wiring_patch_claude_code() {
  local file="$1"
  local glob="$2"
  local mcp_name="$3"

  # Idempotency: already wired?
  if _mcp_wiring_sentinel_has_inline "$file" "$mcp_name"; then
    info "$(basename "$file"): ${mcp_name} already wired (sentinel present) — skipping"
    return 0
  fi

  local existing_csv
  existing_csv="$(_mcp_wiring_read_sentinel "$file")"
  local new_sentinel
  new_sentinel="$(_mcp_wiring_build_sentinel "$existing_csv" "$mcp_name")"

  local tmpfile
  tmpfile="$(mktemp)"

  # Use awk to perform the in-frontmatter edit.
  # Strategy: scan the frontmatter (between first and second ---), apply edit,
  # emit rest unchanged.
  awk -v glob="$glob" -v mcp_name="$mcp_name" -v new_sentinel="$new_sentinel" '
  BEGIN {
    fence_count = 0
    in_front = 0
    tools_done = 0
    sentinel_done = 0
    second_fence_line = ""
    # Buffer frontmatter lines so we can insert tools: before closing ---
    buf_count = 0
  }
  /^---$/ {
    fence_count++
    if (fence_count == 1) {
      in_front = 1
      print
      next
    }
    if (fence_count == 2) {
      # Before closing ---, check if we need to insert tools: (strategy c)
      if (!tools_done) {
        print "tools: " glob
        tools_done = 1
      }
      # Upsert sentinel
      if (!sentinel_done) {
        print "x-eidolons-mcp-wired: [" new_sentinel "]"
        sentinel_done = 1
      }
      in_front = 0
      print
      next
    }
  }
  in_front && /^tools:[[:space:]]/ {
    # Read current value
    val = substr($0, index($0, ":") + 1)
    # Trim leading space
    while (substr(val, 1, 1) == " ") val = substr(val, 2)
    if (val == "none") {
      # Strategy (b): replace
      print "tools: " glob
    } else {
      # Strategy (a): append
      print "tools: " val ", " glob
    }
    tools_done = 1
    next
  }
  in_front && /^x-eidolons-mcp-wired:/ {
    # Upsert sentinel line
    print "x-eidolons-mcp-wired: [" new_sentinel "]"
    sentinel_done = 1
    next
  }
  { print }
  ' "$file" > "$tmpfile"

  mv "$tmpfile" "$file"
  info "Wired ${mcp_name} (${glob}) into $(basename "$file")"
}

# _mcp_wiring_unpatch_claude_code FILE MCP_GLOB MCP_NAME → remove from claude-code agent file.
# Reverses strategies (a), (b), (c) and sentinel upsert.
_mcp_wiring_unpatch_claude_code() {
  local file="$1"
  local glob="$2"
  local mcp_name="$3"

  # Already not wired?
  if ! _mcp_wiring_sentinel_has_inline "$file" "$mcp_name"; then
    info "$(basename "$file"): ${mcp_name} not in sentinel — nothing to reverse"
    return 0
  fi

  local existing_csv
  existing_csv="$(_mcp_wiring_read_sentinel "$file")"
  local new_sentinel
  new_sentinel="$(_mcp_wiring_remove_from_sentinel "$existing_csv" "$mcp_name")"

  local tmpfile
  tmpfile="$(mktemp)"

  awk -v glob="$glob" -v mcp_name="$mcp_name" -v new_sentinel="$new_sentinel" '
  BEGIN {
    fence_count = 0
    in_front = 0
  }
  /^---$/ {
    fence_count++
    if (fence_count == 1) { in_front = 1; print; next }
    if (fence_count == 2) { in_front = 0; print; next }
  }
  in_front && /^tools:[[:space:]]/ {
    val = substr($0, index($0, ":") + 1)
    while (substr(val, 1, 1) == " ") val = substr(val, 2)
    # Remove the glob from the CSV
    # Split on ", " and rebuild without the glob entry
    n = split(val, parts, ", ")
    result = ""
    for (i=1; i<=n; i++) {
      if (parts[i] != glob) {
        if (result == "") result = parts[i]
        else result = result ", " parts[i]
      }
    }
    if (result == "") {
      # Was only the glob — restore to "none"
      print "tools: none"
    } else {
      print "tools: " result
    }
    next
  }
  in_front && /^x-eidolons-mcp-wired:/ {
    if (new_sentinel != "") {
      print "x-eidolons-mcp-wired: [" new_sentinel "]"
    }
    # When new_sentinel is empty, omit the line entirely (clean removal)
    next
  }
  { print }
  ' "$file" > "$tmpfile"

  mv "$tmpfile" "$file"
  info "Unwired ${mcp_name} from $(basename "$file")"
}

# _mcp_wiring_patch_codex FILE MCP_GLOB MCP_NAME → patch codex agent file (strategy d).
_mcp_wiring_patch_codex() {
  local file="$1"
  local glob="$2"
  local mcp_name="$3"

  if _mcp_wiring_sentinel_has_inline "$file" "$mcp_name"; then
    info "$(basename "$file"): ${mcp_name} already wired (sentinel present) — skipping"
    return 0
  fi

  local existing_csv
  existing_csv="$(_mcp_wiring_read_sentinel "$file")"
  local new_sentinel
  new_sentinel="$(_mcp_wiring_build_sentinel "$existing_csv" "$mcp_name")"

  local tmpfile
  tmpfile="$(mktemp)"

  # For codex, tools: is a YAML block sequence. We append a new item after the
  # last `  - ` entry in the tools block. If no tools: block, we insert one before ---.
  awk -v glob="$glob" -v mcp_name="$mcp_name" -v new_sentinel="$new_sentinel" '
  BEGIN {
    fence_count = 0
    in_front = 0
    in_tools_block = 0
    tools_done = 0
    sentinel_done = 0
    last_tools_line = 0
    # Buffer all lines for two-pass approach
    line_count = 0
  }
  {
    lines[line_count++] = $0
  }
  END {
    # Find the second --- fence position
    fc = 0
    second_fence = -1
    for (i=0; i<line_count; i++) {
      if (lines[i] == "---") {
        fc++
        if (fc == 2) { second_fence = i; break }
      }
    }

    # Find tools: block boundaries in frontmatter
    tools_start = -1
    tools_last_item = -1
    in_tools = 0
    for (i=0; i<line_count; i++) {
      if (lines[i] == "---") {
        fc2++
        if (fc2 == 1) { in_fm = 1; continue }
        if (fc2 == 2) { break }
      }
      if (in_fm && lines[i] ~ /^tools:$/) {
        tools_start = i
        in_tools = 1
        continue
      }
      if (in_tools) {
        if (lines[i] ~ /^  - /) {
          tools_last_item = i
        } else if (lines[i] !~ /^[[:space:]]/ || lines[i] == "") {
          in_tools = 0
        }
      }
    }

    # Find sentinel line
    sentinel_line = -1
    for (i=0; i<line_count; i++) {
      if (lines[i] ~ /^x-eidolons-mcp-wired:/) {
        sentinel_line = i; break
      }
    }

    # Now emit with modifications
    for (i=0; i<line_count; i++) {
      if (i == second_fence && !tools_done) {
        # Need to insert tools block before closing ---
        print "tools:"
        print "  - " glob
        tools_done = 1
      }
      if (i == second_fence && !sentinel_done) {
        print "x-eidolons-mcp-wired: [" new_sentinel "]"
        sentinel_done = 1
      }
      if (tools_last_item >= 0 && i == tools_last_item && !tools_done) {
        print lines[i]
        print "  - " glob
        tools_done = 1
        continue
      }
      if (sentinel_line >= 0 && i == sentinel_line && !sentinel_done) {
        print "x-eidolons-mcp-wired: [" new_sentinel "]"
        sentinel_done = 1
        continue
      }
      print lines[i]
    }
    # If we never found a closing fence (malformed file), still emit sentinel/tools
    if (!tools_done) {
      print "tools:"
      print "  - " glob
    }
    if (!sentinel_done) {
      print "x-eidolons-mcp-wired: [" new_sentinel "]"
    }
  }
  ' "$file" > "$tmpfile"

  mv "$tmpfile" "$file"
  info "Wired ${mcp_name} (${glob}) into codex $(basename "$file")"
}

# _mcp_wiring_unpatch_codex FILE MCP_GLOB MCP_NAME → remove from codex agent file.
_mcp_wiring_unpatch_codex() {
  local file="$1"
  local glob="$2"
  local mcp_name="$3"

  if ! _mcp_wiring_sentinel_has_inline "$file" "$mcp_name"; then
    info "$(basename "$file"): ${mcp_name} not in sentinel — nothing to reverse"
    return 0
  fi

  local existing_csv
  existing_csv="$(_mcp_wiring_read_sentinel "$file")"
  local new_sentinel
  new_sentinel="$(_mcp_wiring_remove_from_sentinel "$existing_csv" "$mcp_name")"

  local tmpfile
  tmpfile="$(mktemp)"

  awk -v glob="$glob" -v mcp_name="$mcp_name" -v new_sentinel="$new_sentinel" '
  BEGIN { fence_count = 0; in_front = 0; skip_next_item = 0 }
  /^---$/ {
    fence_count++
    if (fence_count == 1) { in_front = 1; print; next }
    if (fence_count == 2) { in_front = 0; print; next }
  }
  in_front && /^x-eidolons-mcp-wired:/ {
    if (new_sentinel == "") {
      print "x-eidolons-mcp-wired: []"
    } else {
      print "x-eidolons-mcp-wired: [" new_sentinel "]"
    }
    next
  }
  in_front && /^  - / {
    # Check if this is the glob entry to remove
    val = substr($0, 5)
    while (substr(val, 1, 1) == " ") val = substr(val, 2)
    if (val == glob) next  # skip this line
    print; next
  }
  { print }
  ' "$file" > "$tmpfile"

  mv "$tmpfile" "$file"
  info "Unwired ${mcp_name} from codex $(basename "$file")"
}

# ─── Public API ───────────────────────────────────────────────────────────────

# mcp_wiring_patch_agent_file HOST AGENT_FILE MCP_NAME EXPOSES_GLOB
# Patch one agent file for one MCP. Soft-fail on errors (warn + return).
mcp_wiring_patch_agent_file() {
  local host="$1"
  local agent_file="$2"
  local mcp_name="$3"
  local exposes_glob="$4"

  if [ ! -f "$agent_file" ]; then
    info "Wiring: ${agent_file} not found — skipping"
    return 0
  fi

  if [ ! -w "$agent_file" ]; then
    warn "Wiring: ${agent_file} is read-only — skipping (re-run with write permissions)"
    return 0
  fi

  case "$host" in
    claude-code)
      _mcp_wiring_patch_claude_code "$agent_file" "$exposes_glob" "$mcp_name" || {
        warn "Wiring: patch failed for ${agent_file} (${mcp_name}) — continuing"
        return 0
      }
      ;;
    codex)
      _mcp_wiring_patch_codex "$agent_file" "$exposes_glob" "$mcp_name" || {
        warn "Wiring: patch failed for ${agent_file} (${mcp_name}) — continuing"
        return 0
      }
      ;;
    cursor)
      info "cursor uses workspace-global MCP permissions; enable ${exposes_glob} in Cursor → Settings → MCP."
      return 0
      ;;
    opencode)
      info "opencode auto-grant for MCP tools is deferred (FU1). See .opencode/opencode.json for manual configuration."
      return 0
      ;;
    *)
      info "Wiring: unknown host '${host}' — skipping"
      return 0
      ;;
  esac
}

# mcp_wiring_unpatch_agent_file HOST AGENT_FILE MCP_NAME EXPOSES_GLOB
# Remove wiring from one agent file. Soft-fail on errors.
mcp_wiring_unpatch_agent_file() {
  local host="$1"
  local agent_file="$2"
  local mcp_name="$3"
  local exposes_glob="$4"

  if [ ! -f "$agent_file" ]; then
    info "Unwiring: ${agent_file} not found — skipping"
    return 0
  fi

  if [ ! -w "$agent_file" ]; then
    warn "Unwiring: ${agent_file} is read-only — skipping"
    return 0
  fi

  case "$host" in
    claude-code)
      _mcp_wiring_unpatch_claude_code "$agent_file" "$exposes_glob" "$mcp_name" || {
        warn "Unwiring: patch failed for ${agent_file} (${mcp_name}) — continuing"
        return 0
      }
      ;;
    codex)
      _mcp_wiring_unpatch_codex "$agent_file" "$exposes_glob" "$mcp_name" || {
        warn "Unwiring: patch failed for ${agent_file} (${mcp_name}) — continuing"
        return 0
      }
      ;;
    *)
      return 0
      ;;
  esac
}

# mcp_wiring_get_hosts → echo active hosts that support wiring (from eidolons.yaml)
# Outputs one host name per line (claude-code, codex, cursor, opencode).
_mcp_wiring_get_active_hosts() {
  if [ ! -f "$PROJECT_MANIFEST" ]; then
    echo ""
    return 0
  fi
  yaml_to_json "$PROJECT_MANIFEST" \
    | jq -r '(.hosts.wire // [])[]' 2>/dev/null || true
}

# mcp_wiring_get_exclude MCP_NAME → echo Eidolon names excluded for this MCP (one per line)
_mcp_wiring_get_exclude() {
  local mcp_name="$1"
  if [ ! -f "$PROJECT_MANIFEST" ]; then
    return 0
  fi
  yaml_to_json "$PROJECT_MANIFEST" \
    | jq -r --arg n "$mcp_name" '(.mcp_wiring.exclude[$n] // [])[]' 2>/dev/null || true
}

# mcp_wiring_grant_targets MCP_NAME
# Echoes "host<TAB>agent_file_path" for every (host, eidolon) pair that should
# be wired. Stdout only (all log to stderr).
# Implements the resolution logic from spec §6.5.
# Uses temp files for iteration to avoid pipefail+EOF issues under set -euo pipefail.
mcp_wiring_grant_targets() {
  local mcp_name="$1"

  # Get catalogue entry.
  local cat_entry
  cat_entry="$(mcp_catalogue_get "$mcp_name" 2>/dev/null || true)"
  if [ -z "$cat_entry" ]; then
    warn "mcp_wiring_grant_targets: ${mcp_name} not found in catalogue"
    return 0
  fi

  # Transport-only MCPs (e.g. junction, a project-level bus) are registered in
  # .mcp.json but never injected into any agent's tools: allowlist. Their grant
  # is transport-eligibility, not allowlist-injection.
  local wiring_mode
  wiring_mode="$(printf '%s' "$cat_entry" | jq -r '.wiring_mode // "allowlist"' 2>/dev/null || echo allowlist)"
  if [ "$wiring_mode" = "transport" ]; then
    return 0   # zero agent-file targets — bus registration handled by the driver
  fi

  # Get grants_to_eidolons field.
  local grants
  grants="$(printf '%s' "$cat_entry" | jq -r '.grants_to_eidolons // empty' 2>/dev/null || true)"
  if [ -z "$grants" ]; then
    # No grants_to_eidolons field → no fanout.
    return 0
  fi

  # Get the exposes_tools.glob.
  local exposes_glob
  exposes_glob="$(printf '%s' "$cat_entry" | jq -r '.exposes_tools.glob // empty' 2>/dev/null || true)"
  if [ -z "$exposes_glob" ]; then
    # No glob → cannot wire.
    warn "mcp_wiring_grant_targets: ${mcp_name} has no exposes_tools.glob — skipping wiring"
    return 0
  fi

  # Resolve target Eidolon list into a temp file (avoids pipeline/pipefail issues).
  local tmp_eidolons tmp_hosts
  tmp_eidolons="$(mktemp)"
  tmp_hosts="$(mktemp)"

  if [ "$grants" = "all" ]; then
    manifest_members 2>/dev/null > "$tmp_eidolons" || true
  else
    printf '%s' "$cat_entry" | jq -r '.grants_to_eidolons[]' 2>/dev/null > "$tmp_eidolons" || true
  fi

  _mcp_wiring_get_active_hosts 2>/dev/null > "$tmp_hosts" || true

  # Get user-specified exclusions for this MCP (into a temp file too).
  local tmp_excludes
  tmp_excludes="$(mktemp)"
  _mcp_wiring_get_exclude "$mcp_name" > "$tmp_excludes" 2>/dev/null || true

  # For each eidolon in the list, emit (host, file) pairs.
  local eidolon
  while IFS= read -r eidolon; do
    [ -z "$eidolon" ] && continue

    # Check exclusion list using awk (no pipeline).
    local excluded
    excluded="$(awk -v e="$eidolon" '$0 == e { print "1"; exit }' "$tmp_excludes")"
    [ "${excluded:-0}" = "1" ] && continue

    # For each active host, emit the target file.
    local host
    while IFS= read -r host; do
      [ -z "$host" ] && continue
      case "$host" in
        claude-code)
          local cf=".claude/agents/${eidolon}.md"
          [ -f "$cf" ] && printf '%s\t%s\n' "$host" "$cf"
          ;;
        codex)
          local xf=".codex/agents/${eidolon}.md"
          [ -f "$xf" ] && printf '%s\t%s\n' "$host" "$xf"
          ;;
        cursor)
          printf '%s\t%s\n' "cursor" "__cursor_info__"
          ;;
        opencode)
          printf '%s\t%s\n' "opencode" "__opencode_info__"
          ;;
      esac
    done < "$tmp_hosts"
  done < "$tmp_eidolons"

  rm -f "$tmp_eidolons" "$tmp_hosts" "$tmp_excludes"
}

# _mcp_wiring_update_lockfile_add MCP_NAME AGENT_FILE_PATH
# Append an agent file path to the MCP's hosts_wired[] in the lockfile.
_mcp_wiring_update_lockfile_add() {
  local mcp_name="$1"
  local agent_path="$2"
  local lf
  lf="$(mcp_lockfile)"
  if [ ! -f "$lf" ]; then
    return 0
  fi

  local existing_arr new_arr old_entry
  existing_arr="$(mcp_lock_read | jq '(.mcps // [])')"
  old_entry="$(printf '%s' "$existing_arr" \
    | jq --arg n "$mcp_name" '.[] | select(.name == $n)')"

  if [ -z "$old_entry" ]; then
    return 0
  fi

  # Only add if not already present.
  local already
  already="$(printf '%s' "$old_entry" \
    | jq -r --arg p "$agent_path" '(.hosts_wired // []) | map(select(. == $p)) | length')"
  if [ "${already:-0}" -gt 0 ]; then
    return 0
  fi

  local updated
  updated="$(printf '%s' "$old_entry" \
    | jq --arg p "$agent_path" '.hosts_wired = ((.hosts_wired // []) + [$p]) | .hosts_wired |= sort')"

  new_arr="$(printf '%s' "$existing_arr" \
    | jq --arg n "$mcp_name" 'map(select(.name != $n))')"
  new_arr="$(printf '%s' "$new_arr" \
    | jq --argjson e "$updated" '. + [$e]')"

  mcp_lock_write_from_array "$new_arr"
}

# _mcp_wiring_update_lockfile_remove MCP_NAME AGENT_FILE_PATH
# Remove an agent file path from the MCP's hosts_wired[] in the lockfile.
_mcp_wiring_update_lockfile_remove() {
  local mcp_name="$1"
  local agent_path="$2"
  local lf
  lf="$(mcp_lockfile)"
  if [ ! -f "$lf" ]; then
    return 0
  fi

  local existing_arr new_arr old_entry updated
  existing_arr="$(mcp_lock_read | jq '(.mcps // [])')"
  old_entry="$(printf '%s' "$existing_arr" \
    | jq --arg n "$mcp_name" '.[] | select(.name == $n)')"

  if [ -z "$old_entry" ]; then
    return 0
  fi

  updated="$(printf '%s' "$old_entry" \
    | jq --arg p "$agent_path" '.hosts_wired = ((.hosts_wired // []) | map(select(. != $p)))')"

  new_arr="$(printf '%s' "$existing_arr" \
    | jq --arg n "$mcp_name" 'map(select(.name != $n))')"
  new_arr="$(printf '%s' "$new_arr" \
    | jq --argjson e "$updated" '. + [$e]')"

  mcp_lock_write_from_array "$new_arr"
}

# _mcp_wiring_emit_host_info HOST
# For cursor/opencode: emit the info line once per host (not per-eidolon).
# Tracks already-emitted using temp markers to avoid flooding.
_mcp_wiring_emit_host_info_cursor() {
  info "cursor uses workspace-global MCP permissions; enable MCP tools in Cursor → Settings → MCP."
}

_mcp_wiring_emit_host_info_opencode() {
  info "opencode auto-grant for MCP tools is deferred (FU1). See .opencode/opencode.json for manual configuration."
}

# mcp_wiring_apply_for_mcp MCP_NAME
# Patches every (host, eidolon) pair for the given MCP.
# Callable after mcp install / mcp refresh.
# Uses a temp file to avoid pipefail+EOF issues under set -euo pipefail.
mcp_wiring_apply_for_mcp() {
  local mcp_name="$1"

  local cat_entry exposes_glob
  cat_entry="$(mcp_catalogue_get "$mcp_name" 2>/dev/null || true)"
  exposes_glob="$(printf '%s' "$cat_entry" | jq -r '.exposes_tools.glob // empty' 2>/dev/null || true)"

  if [ -z "$exposes_glob" ]; then
    # No wiring configured.
    return 0
  fi

  # Write targets to a temp file to avoid pipefail issues.
  local tmp_targets
  tmp_targets="$(mktemp)"
  mcp_wiring_grant_targets "$mcp_name" > "$tmp_targets" 2>/dev/null || true

  # Warn when an allowlist MCP that grants to Eidolons produced zero targets.
  # This fires when mcp install is run before any Eidolon members are installed
  # (no agent files on disk yet). Transport MCPs (e.g. junction) are excluded —
  # they legitimately produce zero agent-file targets by design.
  local _wm _grants
  _wm="$(printf '%s' "$cat_entry" | jq -r '.wiring_mode // "allowlist"' 2>/dev/null || echo allowlist)"
  _grants="$(printf '%s' "$cat_entry" | jq -r '.grants_to_eidolons // empty' 2>/dev/null || true)"
  if [ "$_wm" != "transport" ] && [ -n "$_grants" ] && [ ! -s "$tmp_targets" ]; then
    warn "${mcp_name}: wired 0 agent files — no agent files found on disk yet."
    warn "  Install Eidolon members first (eidolons init / sync), then run: eidolons mcp install ${mcp_name} --force"
  fi

  local cursor_info_emitted=0
  local opencode_info_emitted=0
  local line host agent_file

  while IFS= read -r line; do
    host="$(printf '%s' "$line" | cut -f1)"
    agent_file="$(printf '%s' "$line" | cut -f2)"

    case "$host" in
      cursor)
        if [ "$cursor_info_emitted" = "0" ]; then
          _mcp_wiring_emit_host_info_cursor
          cursor_info_emitted=1
        fi
        continue
        ;;
      opencode)
        if [ "$opencode_info_emitted" = "0" ]; then
          _mcp_wiring_emit_host_info_opencode
          opencode_info_emitted=1
        fi
        continue
        ;;
    esac

    # Skip the special info markers.
    case "$agent_file" in
      __cursor_info__|__opencode_info__) continue ;;
    esac

    mcp_wiring_patch_agent_file "$host" "$agent_file" "$mcp_name" "$exposes_glob"

    # Update lockfile to track the patched file.
    _mcp_wiring_update_lockfile_add "$mcp_name" "$agent_file" 2>/dev/null || true
  done < "$tmp_targets"

  rm -f "$tmp_targets"
}

# mcp_wiring_unapply_for_mcp MCP_NAME
# Reverses all wiring for the given MCP (removes glob from tools:, removes sentinel entry).
# Must be called BEFORE the driver removes the lockfile entry.
mcp_wiring_unapply_for_mcp() {
  local mcp_name="$1"

  local cat_entry exposes_glob
  cat_entry="$(mcp_catalogue_get "$mcp_name" 2>/dev/null || true)"
  exposes_glob="$(printf '%s' "$cat_entry" | jq -r '.exposes_tools.glob // empty' 2>/dev/null || true)"

  if [ -z "$exposes_glob" ]; then
    return 0
  fi

  # Get the list of files to reverse from the lockfile's hosts_wired[].
  local lf
  lf="$(mcp_lockfile)"
  if [ ! -f "$lf" ]; then
    return 0
  fi

  # Write hosts_wired list to a temp file to avoid pipefail issues.
  local tmp_wired
  tmp_wired="$(mktemp)"
  mcp_lock_entry "$mcp_name" \
    | jq -r '(.hosts_wired // [])[]' 2>/dev/null > "$tmp_wired" || true

  if [ ! -s "$tmp_wired" ]; then
    rm -f "$tmp_wired"
    return 0
  fi

  local agent_file host
  while IFS= read -r agent_file; do
    [ -z "$agent_file" ] && continue
    # Determine host from path.
    case "$agent_file" in
      .claude/agents/*.md)  host="claude-code" ;;
      .codex/agents/*.md)   host="codex" ;;
      *)                    continue ;;  # skip non-agent-file entries (e.g. harness manifest)
    esac
    mcp_wiring_unpatch_agent_file "$host" "$agent_file" "$mcp_name" "$exposes_glob"
    # Remove the agent file from the lockfile's hosts_wired[].
    _mcp_wiring_update_lockfile_remove "$mcp_name" "$agent_file" 2>/dev/null || true
  done < "$tmp_wired"

  rm -f "$tmp_wired"
}

# mcp_wiring_reapply_all
# Idempotent re-application of every locked MCP's wiring.
# Called by eidolons sync (after per-member loop) and mcp sync (after install loop).
# Uses a temp file to avoid pipefail+EOF issues under set -euo pipefail.
mcp_wiring_reapply_all() {
  local lf
  lf="$(mcp_lockfile)"
  if [ ! -f "$lf" ]; then
    return 0
  fi

  # Write installed MCP names to temp file.
  local tmp_mcps
  tmp_mcps="$(mktemp)"
  mcp_lock_read | jq -r '(.mcps // []) | map(.name) | .[]' 2>/dev/null > "$tmp_mcps" || true

  if [ ! -s "$tmp_mcps" ]; then
    rm -f "$tmp_mcps"
    return 0
  fi

  local mcp_name
  while IFS= read -r mcp_name; do
    [ -z "$mcp_name" ] && continue
    mcp_wiring_apply_for_mcp "$mcp_name"
  done < "$tmp_mcps"

  rm -f "$tmp_mcps"
}
