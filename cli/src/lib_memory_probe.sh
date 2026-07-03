#!/usr/bin/env bash
# cli/src/lib_memory_probe.sh — shared crystalium-memory gate + docker-invocation
# transform.
#
# Sourced by:
#   - memory.sh   (eidolons memory preflight [--explain])
#   - doctor.sh   (D13 deep_check_memory_recallability, --deep only)
#   - canary.sh   (eidolons canary --memory)
#
# Extracted here (NOT lib.sh) because this is crystalium/memory-specific
# plumbing, not a general nexus helper — lib.sh stays reserved for cross-
# cutting CLI infrastructure. Deliberately dependency-light: only jq is
# required (already a hard runtime dependency of the nexus CLI).
#
# Convention: every function here is silent (return code / stdout value
# only) — no info/warn/pass/err calls. Each call site owns its own
# messaging so wording stays under that call site's tests, not this file's.
#
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.

# ─── Gate ───────────────────────────────────────────────────────────────────
# The gate every crystalium-memory surface shares: crystalium must be present
# in BOTH .mcp.json (mcpServers.crystalium) AND eidolons.mcp.lock (a
# "name: crystalium" entry). Mirrors memory.sh's original Step 2 gate.

# memory_probe_mcp_gate [PROJECT_ROOT] → 0 iff .mcp.json exists and declares
# mcpServers.crystalium.
memory_probe_mcp_gate() {
  local project_root="${1:-.}"
  [ -f "$project_root/.mcp.json" ] || return 1
  jq -e '.mcpServers.crystalium' "$project_root/.mcp.json" >/dev/null 2>&1
}

# memory_probe_lock_gate [PROJECT_ROOT] → 0 iff eidolons.mcp.lock exists and
# has a "name: crystalium" entry.
memory_probe_lock_gate() {
  local project_root="${1:-.}"
  [ -f "$project_root/eidolons.mcp.lock" ] || return 1
  grep -q "name: crystalium" "$project_root/eidolons.mcp.lock" 2>/dev/null
}

# memory_probe_gated_in [PROJECT_ROOT] → 0 iff BOTH gates pass. The single
# boolean consumed by doctor D13 and canary --memory for their SKIP decision.
memory_probe_gated_in() {
  local project_root="${1:-.}"
  memory_probe_mcp_gate "$project_root" && memory_probe_lock_gate "$project_root"
}

# ─── Docker invocation transform ───────────────────────────────────────────

# memory_probe_docker_cmd [PROJECT_ROOT] → echoes .mcp.json's
# mcpServers.crystalium.command (defaults to "docker" when absent/empty).
memory_probe_docker_cmd() {
  local project_root="${1:-.}"
  local cmd
  cmd="$(jq -r '.mcpServers.crystalium.command // "docker"' "$project_root/.mcp.json" 2>/dev/null)"
  printf '%s' "${cmd:-docker}"
}

# memory_probe_quote STR → %q-quote STR for safe embedding in a generated
# shell script (falls back to a naive single-quote wrap when %q is
# unavailable, matching memory.sh's original fallback).
memory_probe_quote() {
  printf '%q' "$1" 2>/dev/null || printf "'%s'" "$1"
}

# memory_probe_build_docker_script PROJECT_ROOT REPLACEMENT OUT_SCRIPT
#
# Transforms .mcp.json's crystalium `serve` invocation into a one-shot
# invocation of the crystalium CLI, exactly as eidolons memory preflight
# does:
#   - drop bare "-i"            (interactive stdin — one-shot needs none)
#   - drop "--name <value>"     (avoid colliding with the running serve
#                                 container's name)
#   - replace the trailing "serve" token with REPLACEMENT (caller-quoted —
#     use memory_probe_quote on any dynamic parts, e.g. a --query value)
#
# Writes an executable wrapper script to OUT_SCRIPT that execs the resolved
# docker command with the transformed args.
#
# Returns 1 when "serve" was not found in .mcp.json's crystalium args (the
# script header is still written but nothing was appended) — callers should
# treat this as "cannot build invocation" and WARN/SKIP/FAIL per their own
# convention rather than executing the incomplete script.
memory_probe_build_docker_script() {
  local project_root="$1" replacement="$2" out_script="$3"

  local docker_cmd
  docker_cmd="$(memory_probe_docker_cmd "$project_root")"
  printf '#!/usr/bin/env bash\nexec %s' "$docker_cmd" > "$out_script"

  local _skip_next=0 _appended=0 _arg _q_arg
  while IFS= read -r _arg; do
    if [ "$_skip_next" -eq 1 ]; then
      _skip_next=0
      continue
    fi
    if [ "$_arg" = "-i" ]; then
      continue
    fi
    if [ "$_arg" = "--name" ]; then
      _skip_next=1
      continue
    fi
    if [ "$_arg" = "serve" ] && [ "$_appended" -eq 0 ]; then
      _appended=1
      printf ' %s' "$replacement" >> "$out_script"
      continue
    fi
    _q_arg="$(printf '%q' "$_arg" 2>/dev/null || printf "'%s'" "$_arg")"
    printf ' %s' "$_q_arg" >> "$out_script"
  done < <(jq -r '.mcpServers.crystalium.args[]' "$project_root/.mcp.json" 2>/dev/null)

  printf '\n' >> "$out_script"
  chmod +x "$out_script"

  [ "$_appended" -eq 1 ] || return 1
  return 0
}

# memory_probe_project_slug [PROJECT_ROOT] → the deterministic project slug
# used as --scope-project (lowercased basename, non-alnum runs collapsed to
# '-', leading/trailing '-' trimmed). Mirrors memory.sh Step 4.
memory_probe_project_slug() {
  local project_root="${1:-.}"
  local base
  base="$(basename "$project_root")"
  printf '%s' "$base" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9' '-' \
    | sed -e 's|^-||' -e 's|-$||'
}
