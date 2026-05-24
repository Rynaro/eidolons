#!/usr/bin/env bash
#
# cli/src/lib_host_prune.sh — defensive prune of per-Eidolon vendor leakage.
# Sourced from sync.sh after each per-Eidolon installer runs.
# ═══════════════════════════════════════════════════════════════════════════
#
# Why this exists (FINDING-003 in the scout report):
#   The nexus already forwards `--hosts $HOSTS_CSV` to each per-Eidolon
#   install.sh, but several Eidolons today (vigil, forge, atlas, …)
#   ignore the flag and write vendor-specific files unconditionally
#   inside `.eidolons/<name>/`. The leakage is confined to that tree, but
#   it bloats the working set and produces files no host will ever read.
#
# Two prune paths, both safe to invoke per-member every sync:
#   1. host_prune_manifest_pass — walks the installer's install.manifest.json
#      `files[]` entries; deletes any file whose `host` annotation isn't
#      in the selected set. Cooperative path; requires the installer to
#      annotate. No-op for unannotated entries.
#   2. host_prune_path_patterns — a defensive fallback. Deletes well-known
#      vendor-specific paths under `.eidolons/<name>/` when their host
#      isn't in the selection. Always-on regardless of manifest support.
#
# Strict mode (host_prune_strict_check) is opt-in via the --strict-hosts
# CLI flag on init/sync. It scans the path-pattern set and emits a
# violation line for every match that the manifest didn't already
# annotate. The caller decides whether to abort the run.
#
# All log output goes to stderr (via info / warn). Stdout from
# host_prune_strict_check is reserved for machine-readable violation
# lines (one per line) — the caller pipes that into warn messaging.
#
# Bash 3.2 safe — no associative arrays, no ${var,,}, no mapfile.
#
# Public API:
#   host_prune_path_patterns      TARGET HOSTS_CSV
#   host_prune_manifest_pass      TARGET HOSTS_CSV
#   host_prune_strict_check       TARGET HOSTS_CSV
# ═══════════════════════════════════════════════════════════════════════════

[[ "${EIDOLONS_LIB_HOST_PRUNE_LOADED:-0}" == "1" ]] && return 0
EIDOLONS_LIB_HOST_PRUNE_LOADED=1

# Space-separated "path|host" pairs describing single-host vendor files
# that a per-Eidolon installer may have dropped under .eidolons/<name>/.
# AGENTS.md is intentionally excluded here — it serves codex AND opencode
# (multi-host rule) and is handled separately in the path-prune loop.
_HOST_PRUNE_SINGLE_HOST_PATTERNS=" \
  hosts/cursor.md|cursor \
  hosts/copilot.md|copilot \
  hosts/codex.md|codex \
  hosts/opencode.md|opencode \
  .github/copilot-instructions.md|copilot \
  CLAUDE.md|claude-code \
"

# Same set without the host annotation, for the strict-check scan.
_HOST_PRUNE_PATH_SET=" \
  hosts/cursor.md \
  hosts/copilot.md \
  hosts/codex.md \
  hosts/opencode.md \
  .github/copilot-instructions.md \
  CLAUDE.md \
  AGENTS.md \
"

# host_prune_path_patterns TARGET HOSTS_CSV
#
# Walk the single-host pattern table and delete any file whose host isn't
# in HOSTS_CSV. AGENTS.md is handled by a multi-host rule: keep iff codex
# OR opencode is in the selection.
#
# Verbose (EIDOLONS_VERBOSE=1) prints one info line per deletion.
host_prune_path_patterns() {
  local target="$1" hosts_csv="$2"
  local pair file_path host
  for pair in $_HOST_PRUNE_SINGLE_HOST_PATTERNS; do
    file_path="${pair%|*}"
    host="${pair##*|}"
    [[ -f "$target/$file_path" ]] || continue
    if [[ ",$hosts_csv," != *",$host,"* ]]; then
      rm -f "$target/$file_path"
      if [[ "${EIDOLONS_VERBOSE:-0}" == "1" ]]; then
        info "  pruned $target/$file_path (pattern: host=$host not in selection)"
      fi
    fi
  done
  # AGENTS.md multi-host rule.
  if [[ -f "$target/AGENTS.md" ]] \
     && [[ ",$hosts_csv," != *",codex,"* ]] \
     && [[ ",$hosts_csv," != *",opencode,"* ]]; then
    rm -f "$target/AGENTS.md"
    if [[ "${EIDOLONS_VERBOSE:-0}" == "1" ]]; then
      info "  pruned $target/AGENTS.md (pattern: neither codex nor opencode selected)"
    fi
  fi
  # Clean up empty directories left by the path-pattern prune. Common case:
  # .github/ becomes empty after copilot-instructions.md and instructions/
  # are removed. find ... -type d -empty -delete is shell-portable.
  find "$target" -type d -empty -delete 2>/dev/null || true
  # Always return 0 — caller may be running under `set -e`.
  return 0
}

# host_prune_manifest_pass TARGET HOSTS_CSV
#
# Walk the per-Eidolon install.manifest.json `files[]` array; for each
# entry that carries a non-empty `host` field, delete the file if `host`
# is not in HOSTS_CSV. Unannotated entries are left alone (path-pattern
# pass remains the fallback). Cooperative path — depends on the
# installer populating per-file host annotations (EIIS v1.X bump tracked
# as soft dep FU-I2.1).
#
# No-op when the manifest is absent (legacy installer) or the files[]
# array is empty.
host_prune_manifest_pass() {
  local target="$1" hosts_csv="$2"
  local manifest="$target/install.manifest.json"
  [[ -f "$manifest" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local entry file_path host
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    file_path="$(printf '%s' "$entry" | jq -r '.path // empty' 2>/dev/null || echo "")"
    host="$(printf '%s' "$entry" | jq -r '.host // empty' 2>/dev/null || echo "")"
    [[ -z "$file_path" || -z "$host" ]] && continue
    [[ -f "$target/$file_path" ]] || continue
    if [[ ",$hosts_csv," != *",$host,"* ]]; then
      rm -f "$target/$file_path"
      if [[ "${EIDOLONS_VERBOSE:-0}" == "1" ]]; then
        info "  pruned $target/$file_path (manifest: host=$host not in selection)"
      fi
    fi
  done < <(jq -c '(.files // [])[]' "$manifest" 2>/dev/null || true)
  return 0
}

# host_prune_strict_check TARGET HOSTS_CSV
#
# In strict mode, every vendor-specific path under .eidolons/<name>/ must
# either (a) be annotated in install.manifest.json so the manifest pass
# can decide what to do with it, or (b) be claimed by a wired host (and
# therefore intentional). Walks the pattern set, checks manifest
# coverage, and emits one violation line per offending path to stdout.
#
# Exit status:
#   0 — no violations
#   1 — at least one violation (lines printed to stdout)
#
# Output format (one line per violation):
#   <full_path> (host unknown; selected: <hosts_csv>)
#
# Callers should pipe stdout into `warn` for user-facing output.
host_prune_strict_check() {
  local target="$1" hosts_csv="$2"
  local manifest="$target/install.manifest.json"
  local pf annotated violations=0
  for pf in $_HOST_PRUNE_PATH_SET; do
    [[ -f "$target/$pf" ]] || continue
    annotated=""
    if [[ -f "$manifest" ]] && command -v jq >/dev/null 2>&1; then
      annotated="$(jq --arg p "$pf" -r \
        '(.files // [])[] | select(.path == $p) | .host // empty' \
        "$manifest" 2>/dev/null || echo "")"
    fi
    if [[ -z "$annotated" ]]; then
      printf '%s/%s (host unknown; selected: %s)\n' "$target" "$pf" "$hosts_csv"
      violations=$((violations + 1))
    fi
  done
  [[ "$violations" -gt 0 ]] && return 1
  return 0
}
