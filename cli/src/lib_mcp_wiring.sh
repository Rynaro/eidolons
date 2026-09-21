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
#   (c) claude-code skip+warn    — no `tools:` line → leave file unchanged (inherit-all),
#                                  update sentinel, emit warning to stderr
#   (d) codex advisory           — Codex TOML agent descriptors inherit project
#                                  MCP servers. Its current descriptor schema has
#                                  no per-agent tool allowlist, so catalogue grants
#                                  cannot be enforced there. We report that fact
#                                  instead of writing legacy YAML/Markdown files.
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
_LIB_MCP_WIRING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# _mcp_wiring_tools_json FILE
# Emit the Claude frontmatter `tools` value as a JSON array.  Both scalar CSV
# and YAML sequence forms are accepted; callers must reject a missing or
# malformed field rather than silently changing inheritance semantics.
_mcp_wiring_tools_json() {
  local file="$1" frontmatter parsed tools tmp
  frontmatter="$(awk '
    /^---$/ { fences++; if (fences == 1) { next }; if (fences == 2) { exit } }
    fences == 1 { print }
  ' "$file")"
  [ -n "$frontmatter" ] || return 1
  tmp="$(mktemp)"
  printf '%s\n' "$frontmatter" > "$tmp"
  parsed="$(yaml_to_json "$tmp" 2>/dev/null || true)"
  rm -f "$tmp"
  [ -n "$parsed" ] || return 1
  tools="$(printf '%s' "$parsed" | jq -c '
    if (.tools | type) == "array" and all(.tools[]; type == "string") then .tools
    elif (.tools | type) == "string" and .tools == "none" then []
    elif (.tools | type) == "string" then .tools | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))
    else empty end
  ' 2>/dev/null || true)"
  [ -n "$tools" ] || return 1
  printf '%s\n' "$tools"
}

# _mcp_wiring_validate_tools_field FILE
# Require exactly one tools field within exactly one YAML frontmatter block.
_mcp_wiring_validate_tools_field() {
  local file="$1" result
  result="$(awk '
    /^---$/ { fences++; next }
    fences == 1 && /^tools:[[:space:]]*($|[^:])/ { tools++ }
    END { if (fences == 2 && tools == 1) print "ok" }
  ' "$file")"
  [ "$result" = "ok" ]
}

# _mcp_wiring_tools_render JSON_ARRAY
# Render the supported, canonical flow-sequence form. MCP and built-in tool
# identifiers are plain YAML scalars; anything else was rejected by jq above.
_mcp_wiring_tools_render() {
  local tools_json="$1"
  printf '%s' "$tools_json" | jq -r 'join(", ")' 2>/dev/null
}

# _mcp_wiring_replace_claude_tools FILE TOOLS_JSON SENTINEL_CSV
# Atomically replace a scalar or block tools field with one canonical flow
# sequence and upsert the ownership marker. The caller has already parsed and
# validated the input, so an unsuccessful rewrite leaves the source untouched.
_mcp_wiring_replace_claude_tools() {
  local file="$1" tools_json="$2" sentinel_csv="$3" rendered tmp
  rendered="$(_mcp_wiring_tools_render "$tools_json")" || return 1
  tmp="$(mktemp)"
  awk -v rendered="$rendered" -v sentinel="$sentinel_csv" '
    BEGIN { fences=0; in_front=0; skipping_tools_children=0; sentinel_done=0 }
    /^---$/ {
      fences++
      if (fences == 1) { in_front=1; print; next }
      if (fences == 2) {
        if (!sentinel_done && sentinel != "") print "x-eidolons-mcp-wired: [" sentinel "]"
        in_front=0; print; next
      }
    }
    in_front && /^tools:[[:space:]]*($|[^:])/ {
      print "tools: [" rendered "]"
      skipping_tools_children=1
      next
    }
    in_front && skipping_tools_children && /^[[:space:]]+- / { next }
    in_front && skipping_tools_children { skipping_tools_children=0 }
    in_front && /^x-eidolons-mcp-wired:/ {
      if (sentinel != "") print "x-eidolons-mcp-wired: [" sentinel "]"
      sentinel_done=1
      next
    }
    { print }
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  # Verify the rewritten frontmatter parses and keeps exactly the requested set.
  local observed
  observed="$(_mcp_wiring_tools_json "$tmp" 2>/dev/null || true)"
  if [ -z "$observed" ] || [ "$(printf '%s' "$observed" | jq -cS . 2>/dev/null)" != "$(printf '%s' "$tools_json" | jq -cS . 2>/dev/null)" ]; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$file"
}

# _mcp_wiring_patch_claude_code FILE MCP_GLOB MCP_NAME → patch claude-code agent file.
# A receipt is only written after this function has verified that the requested
# glob is present. Missing or malformed `tools` metadata is deliberately a
# failed grant: a marker alone must never claim an MCP was exposed.
_mcp_wiring_patch_claude_code() {
  local file="$1"
  local glob="$2"
  local mcp_name="$3"

  if ! _mcp_wiring_validate_tools_field "$file"; then
    warn "Wiring: ${file} has missing or ambiguous tools metadata; refusing to claim ${mcp_name} was granted"
    return 2
  fi

  local tools_json
  tools_json="$(_mcp_wiring_tools_json "$file" 2>/dev/null || true)"
  if [ -z "$tools_json" ]; then
    warn "Wiring: ${file} has malformed tools metadata; refusing to change it"
    return 2
  fi

  local existing_csv
  existing_csv="$(_mcp_wiring_read_sentinel "$file")"
  local has_glob has_sentinel new_tools new_sentinel
  has_glob="$(printf '%s' "$tools_json" | jq --arg g "$glob" 'index($g) != null' 2>/dev/null || true)"
  has_sentinel="$(printf '%s' "$existing_csv" | tr ',' '\n' | awk -v n="$mcp_name" '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 == n) print "1"}')"

  # A pre-existing user grant is sufficient exposure but remains unmanaged: do
  # not adopt it, and therefore never remove it during uninstall.
  if [ "$has_glob" = "true" ] && [ -z "$has_sentinel" ]; then
    info "$(basename "$file"): ${glob} already present without an Eidolons receipt — leaving user grant unmanaged"
    return 0
  fi
  if [ "$has_glob" = "true" ] && [ -n "$has_sentinel" ]; then
    info "$(basename "$file"): ${mcp_name} grant already verified"
    return 0
  fi

  new_tools="$(printf '%s' "$tools_json" | jq -c --arg g "$glob" '. + [$g]')" || return 1
  new_sentinel="$(_mcp_wiring_build_sentinel "$existing_csv" "$mcp_name")"
  _mcp_wiring_replace_claude_tools "$file" "$new_tools" "$new_sentinel" || return 1
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

  if ! _mcp_wiring_validate_tools_field "$file"; then
    warn "Unwiring: ${file} has missing or ambiguous tools metadata; preserving it"
    return 2
  fi
  local tools_json new_tools
  tools_json="$(_mcp_wiring_tools_json "$file" 2>/dev/null || true)"
  [ -n "$tools_json" ] || return 2
  new_tools="$(printf '%s' "$tools_json" | jq -c --arg g "$glob" 'map(select(. != $g))')" || return 1
  _mcp_wiring_replace_claude_tools "$file" "$new_tools" "$new_sentinel" || return 1
  info "Unwired ${mcp_name} from $(basename "$file")"
}

# _mcp_wiring_patch_codex FILE MCP_GLOB MCP_NAME → patch codex agent file (strategy d).
#
# Strategy (d) — no tools: block:
#   Codex tools: block semantics when absent are unverified. Applying the same
#   conservative rule as strategy (c): if no tools: block exists, do NOT insert
#   one (could starve the agent of all tools). Instead update only the sentinel
#   and emit a warning to stderr.
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

  # Detect whether a tools: block-sequence header exists in the frontmatter.
  local has_tools_block
  has_tools_block="$(awk '
    /^---$/ { fc++; if (fc==1) { in_fm=1; next } if (fc==2) { exit } }
    in_fm && /^tools:$/ { print "1"; exit }
  ' "$file" || true)"

  # No tools: block — skip injection, warn, update sentinel only.
  if [ "${has_tools_block:-}" != "1" ]; then
    if command -v warn >/dev/null 2>&1; then
      warn "agent file has no tools: line — inherits all tools; skipping allowlist injection (${file})"
    else
      printf 'WARNING: agent file has no tools: line — inherits all tools; skipping allowlist injection (%s)\n' "$file" >&2
    fi
    local tmpfile
    tmpfile="$(mktemp)"
    awk -v new_sentinel="$new_sentinel" '
    BEGIN { fence_count=0; in_front=0; sentinel_done=0 }
    /^---$/ {
      fence_count++
      if (fence_count == 1) { in_front=1; print; next }
      if (fence_count == 2) {
        if (!sentinel_done) {
          print "x-eidolons-mcp-wired: [" new_sentinel "]"
          sentinel_done=1
        }
        in_front=0; print; next
      }
    }
    in_front && /^x-eidolons-mcp-wired:/ {
      print "x-eidolons-mcp-wired: [" new_sentinel "]"
      sentinel_done=1
      next
    }
    { print }
    ' "$file" > "$tmpfile"
    mv "$tmpfile" "$file"
    return 0
  fi

  local tmpfile
  tmpfile="$(mktemp)"

  # For codex, tools: is a YAML block sequence. We append a new item after the
  # last `  - ` entry in the tools block.
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
    # If we never found a closing fence (malformed file), still emit sentinel
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
# Patch one agent file for one MCP. A non-zero result means no managed grant was
# verified, so callers must not record the file in hosts_wired[].
mcp_wiring_patch_agent_file() {
  local host="$1"
  local agent_file="$2"
  local mcp_name="$3"
  local exposes_glob="$4"

  if [ ! -f "$agent_file" ]; then
    info "Wiring: ${agent_file} not found — skipping"
    return 2
  fi

  if [ ! -w "$agent_file" ]; then
    warn "Wiring: ${agent_file} is read-only — skipping (re-run with write permissions)"
    return 2
  fi

  case "$host" in
    claude-code)
      _mcp_wiring_patch_claude_code "$agent_file" "$exposes_glob" "$mcp_name" || return $?
      ;;
    codex)
      _mcp_wiring_patch_codex "$agent_file" "$exposes_glob" "$mcp_name" || return $?
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
# Remove wiring from one agent file. A non-zero result retains the receipt for
# retry because the managed mutation could not be confirmed.
mcp_wiring_unpatch_agent_file() {
  local host="$1"
  local agent_file="$2"
  local mcp_name="$3"
  local exposes_glob="$4"

  if [ ! -f "$agent_file" ]; then
    info "Unwiring: ${agent_file} not found — skipping"
    return 2
  fi

  if [ ! -w "$agent_file" ]; then
    warn "Unwiring: ${agent_file} is read-only — skipping"
    return 2
  fi

  case "$host" in
    claude-code)
      _mcp_wiring_unpatch_claude_code "$agent_file" "$exposes_glob" "$mcp_name" || {
        warn "Unwiring: patch failed for ${agent_file} (${mcp_name}) — continuing"
        return 1
      }
      ;;
    codex)
      _mcp_wiring_unpatch_codex "$agent_file" "$exposes_glob" "$mcp_name" || {
        warn "Unwiring: patch failed for ${agent_file} (${mcp_name}) — continuing"
        return 1
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
          local xf=".codex/agents/${eidolon}.toml"
          [ -f "$xf" ] && printf '%s\t%s\n' "$host" "__codex_advisory__"
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
  local codex_info_emitted=0
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
      codex)
        if [ "$codex_info_emitted" = "0" ]; then
          warn "${mcp_name}: Codex agent descriptors inherit project MCP servers; grants/exclusions are advisory until Codex exposes per-agent MCP allowlists."
          codex_info_emitted=1
        fi
        continue
        ;;
    esac

    # Skip the special info markers.
    case "$agent_file" in
      __cursor_info__|__opencode_info__|__codex_advisory__) continue ;;
    esac

    if mcp_wiring_patch_agent_file "$host" "$agent_file" "$mcp_name" "$exposes_glob"; then
      # Receipt only a verified managed mutation. A pre-existing user grant is
      # intentionally unmanaged and is not included in hosts_wired[].
      if _mcp_wiring_sentinel_has_inline "$agent_file" "$mcp_name"; then
        _mcp_wiring_update_lockfile_add "$mcp_name" "$agent_file" 2>/dev/null || true
      fi
    else
      warn "Wiring: ${mcp_name} was not granted to ${agent_file}; no lock receipt recorded"
    fi
  done < "$tmp_targets"

  # Desired-state reconciliation: exclusions and narrowed grant rosters must
  # revoke prior Eidolons-managed allowances. User-owned grants have no marker
  # or receipt and are never selected here. Keep a receipt when the descriptor
  # is unavailable so a later reconciliation can retry rather than claiming a
  # successful revoke.
  local tmp_previous previous_file previous_host still_desired
  tmp_previous="$(mktemp)"
  mcp_lock_entry "$mcp_name" | jq -r '(.hosts_wired // [])[]' 2>/dev/null > "$tmp_previous" || true
  while IFS= read -r previous_file; do
    case "$previous_file" in
      .claude/agents/*.md) previous_host="claude-code" ;;
      .codex/agents/*.md|.codex/agents/*.toml) previous_host="codex" ;;
      *) continue ;;
    esac
    still_desired="$(awk -F '\t' -v p="$previous_file" '$2 == p { print "1"; exit }' "$tmp_targets")"
    [ -n "$still_desired" ] && continue
    if mcp_wiring_unpatch_agent_file "$previous_host" "$previous_file" "$mcp_name" "$exposes_glob"; then
      _mcp_wiring_update_lockfile_remove "$mcp_name" "$previous_file" 2>/dev/null || true
      info "Unwired ${mcp_name} from ${previous_file} because it is no longer granted"
    else
      warn "Wiring: ${mcp_name} remains recorded for ${previous_file}; managed revoke did not complete"
    fi
  done < "$tmp_previous"

  rm -f "$tmp_targets" "$tmp_previous"
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
      .codex/agents/*.toml) host="codex" ;;
      *)                    continue ;;  # skip non-agent-file entries (e.g. harness manifest)
    esac
    if mcp_wiring_unpatch_agent_file "$host" "$agent_file" "$mcp_name" "$exposes_glob"; then
      # Remove the agent file from the lockfile's hosts_wired[] only after the
      # managed allowance was actually removed.
      _mcp_wiring_update_lockfile_remove "$mcp_name" "$agent_file" 2>/dev/null || true
    else
      warn "Unwiring: ${mcp_name} remains recorded for ${agent_file}; managed revoke did not complete"
    fi
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

# Read-only preview or explicit, offline repair of installed generated wiring.
# Never install/upgrade an artifact or adopt user grants. Update only the runtime
# receipt after successful repair; retain selected artifact and enforcement evidence.
mcp_wiring_reconcile() {
  local mode="$1" names name version kind expected target temp host file glob legacy tools desired sentinel receipt entry
  names="$(mcp_lock_read | jq -r '(.mcps // [])[].name')"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    version="$(mcp_lock_entry "$name" | jq -r '.version')"
    kind="$(mcp_catalogue_get_field "$name" '.kind')"
    if [ "$kind" = "oci-image" ] && ! _mcp_oci_config_is_current "$name" "$version" "$(pwd)"; then
      info "$name: runtime wiring drift (.mcp.json); preview: eidolons mcp sync --dry-run; repair: eidolons mcp sync --repair-wiring"
      if [ "$mode" = repair ]; then
        expected="$(_mcp_oci_expected_config "$name" "$version" "$(pwd)")" || return 1
        target=.mcp.json
        # Refuse malformed user data; no silent replacement even with repair.
        [ -f "$target" ] || printf '{}\n' > "$target"
        temp="$(mktemp)"
        if ! jq --arg n "$name" --argjson expected "$expected" '
          .mcpServers[$n] = ((.mcpServers[$n] // {}) * $expected)
        ' "$target" > "$temp"; then
          rm -f "$temp"; return 1
        fi
        mv "$temp" "$target"
      fi
    fi
    if [ "$kind" = "oci-image" ]; then
      expected="$(_mcp_oci_expected_config "$name" "$version" "$(pwd)")" || return 1
      _mcp_wiring_secondary "$mode" "$name" "$expected" || return 1
      if ! _mcp_runtime_is_current "$name" "$(pwd)"; then
        info "$name: runtime receipt drift"
        if [ "$mode" = repair ]; then
          receipt="$(_mcp_runtime_resolve "$name" "$(pwd)")" || return 1
          entry="$(mcp_lock_entry "$name" | jq --argjson r "$receipt" '.runtime = $r')"
          mcp_lock_upsert "$name" "$entry" || return 1
        fi
      fi
    fi
    glob="$(mcp_catalogue_get_field "$name" '.exposes_tools.glob')"
    [ -n "$glob" ] || continue
    legacy="$(printf '%s' "$name" | tr '-' '_')"
    legacy="mcp__${legacy}__*"
    # grant_targets respects active hosts and explicit user exclusions.
    target="$(mktemp)"
    mcp_wiring_grant_targets "$name" > "$target"
    while IFS="$(printf '\t')" read -r host file; do
      [ "$host" = claude-code ] && [ -f "$file" ] || continue
      tools="$(_mcp_wiring_tools_json "$file")" || { warn "$file: unreadable grant metadata; preserving"; continue; }
      if ! _mcp_wiring_sentinel_has_inline "$file" "$name"; then
        if ! printf '%s' "$tools" | jq -e --arg g "$glob" 'index($g) != null' >/dev/null; then
          warn "$name: grant wiring drift in $file (unmanaged; preserving user settings)"
        fi
        continue
      fi
      desired="$(printf '%s' "$tools" | jq -c --arg g "$glob" --arg old "$legacy" '
        map(if . == $old then $g else . end) |
        if index($g) == null then . + [$g] else . end |
        reduce .[] as $v ([]; if $v == $g and index($g) != null then . else . + [$v] end)
      ')"
      if [ "$(printf '%s' "$tools" | jq -c 'sort')" != "$(printf '%s' "$desired" | jq -c 'sort')" ]; then
        info "$name: grant wiring drift in $file (expected $glob)"
        if [ "$mode" = repair ]; then
          # Keep original order and remove only a duplicate managed glob.
          desired="$(printf '%s' "$tools" | jq -c --arg g "$glob" --arg old "$legacy" '
            map(if . == $old then $g else . end) |
            if index($g) == null then . + [$g] else . end |
            reduce .[] as $v ([]; if $v == $g and index($g) != null then . else . + [$v] end)
          ')"
          sentinel="$(_mcp_wiring_read_sentinel "$file")"
          _mcp_wiring_replace_claude_tools "$file" "$desired" "$sentinel" || { rm -f "$target"; return 1; }
        fi
      fi
    done < "$target"
    rm -f "$target"
  done <<< "$names"
}

# Preview/repair host projections using their existing ownership boundaries.
# JSON extras survive recursive merge; Codex owns only its marked MCP region.
_mcp_wiring_secondary() {
  local mode="$1" name="$2" expected="$3" host target temp wanted
  local drift=0
  for host in cursor opencode codex; do
    _mcp_host_is_wired "$host" "$(pwd)" || continue
    case "$host" in
      cursor) target=.cursor/mcp.json ;;
      opencode) target=opencode.json ;;
      codex) target=.codex/config.toml ;;
    esac
    temp="$(mktemp)"
    if [ "$host" = codex ]; then
      if ! printf '%s' "$expected" | python3 "$_LIB_MCP_WIRING_DIR/mcp_codex_wiring.py" "$target" "$name" > "$temp"; then
        rm -f "$temp"
        warn "$name: cannot compare $target managed region; preserving it"
        return 1
      fi
    else
      wanted="$expected"
      if [ "$host" = opencode ]; then
        wanted="$(printf '%s' "$expected" | jq '{type:"local",command:([.command]+.args)}')"
      fi
      if [ -f "$target" ]; then
        if ! jq --arg n "$name" --arg h "$host" --argjson e "$wanted" '
          if $h == "cursor" then .mcpServers[$n] = ((.mcpServers[$n] // {}) * $e)
          else .mcp[$n] = ({enabled:true} * (.mcp[$n] // {}) * $e) end
        ' "$target" > "$temp"; then
          rm -f "$temp"; warn "$target: invalid JSON; preserving user settings"; return 1
        fi
      else
        jq -n --arg n "$name" --arg h "$host" --argjson e "$wanted" '
          if $h == "cursor" then {mcpServers:{($n):$e}} else {mcp:{($n):({enabled:true} * $e)}} end
        ' > "$temp"
      fi
    fi
    if [ -f "$target" ] && { cmp -s "$target" "$temp" || { [ "$host" != codex ] && [ "$(jq -cS . "$target")" = "$(jq -cS . "$temp")" ]; }; }; then
      rm -f "$temp"
    else
      drift=1
      info "$name: runtime wiring drift ($target)"
      if [ "$mode" = repair ]; then
        mkdir -p "$(dirname "$target")"
        mv "$temp" "$target"
      else
        rm -f "$temp"
      fi
    fi
  done
  [ "$mode" != check ] || return "$drift"
  return 0
}
