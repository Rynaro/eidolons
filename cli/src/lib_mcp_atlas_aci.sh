#!/usr/bin/env bash
# cli/src/lib_mcp_atlas_aci.sh — shared Docker / image pre-flight helpers for
# the Atlas-ACI MCP scaffold pipeline.
#
# SOURCE this file; do NOT execute it directly.
# Safe to source from any script that already sourced lib.sh or that has not —
# this library has no top-level side effects and sets no traps.
#
# Exported functions:
#   atlas_aci_check_docker_cli      exit 0 (present) / 2 (absent)
#   atlas_aci_check_docker_daemon   exit 0 (reachable) / 3 (down)
#   atlas_aci_check_image <ref>     exit 0 (loaded) / 4 (missing)
#   atlas_aci_image_status <ref>    stdout: one-line status token + ref;
#                                   exit code mirrors the underlying function
#
# All diagnostic output goes to stderr only — never stdout — so callers that
# capture the return value of atlas_aci_image_status see only the status line.
#
# Bash 3.2 compatible — no associative arrays, no ${var,,}, no readarray.
# See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

# Guard against sourcing more than once (idempotent source).
if [ -n "${_LIB_MCP_ATLAS_ACI_LOADED:-}" ]; then
  return 0
fi
_LIB_MCP_ATLAS_ACI_LOADED=1

# ---------------------------------------------------------------------------
# atlas_aci_check_docker_cli
#   Returns 0 if the `docker` binary is on PATH, 2 otherwise.
#   On failure: writes a one-line actionable message to stderr.
# ---------------------------------------------------------------------------
atlas_aci_check_docker_cli() {
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi
  printf '%s\n' \
    "Docker is not installed. Install Docker Desktop (macOS) or Docker Engine (Linux): https://docs.docker.com/get-docker/" \
    >&2
  return 2
}

# ---------------------------------------------------------------------------
# atlas_aci_check_docker_daemon
#   Returns 0 if the Docker daemon is reachable (`docker info` exits 0), 3
#   otherwise.  Assumes the CLI is already on PATH (call atlas_aci_check_docker_cli
#   first).
#   On failure: writes a one-line actionable message to stderr.
# ---------------------------------------------------------------------------
atlas_aci_check_docker_daemon() {
  if docker info >/dev/null 2>&1; then
    return 0
  fi
  printf '%s\n' \
    "Docker daemon is not reachable. On macOS, open Docker Desktop. On Linux, run 'sudo systemctl start docker'." \
    >&2
  return 3
}

# ---------------------------------------------------------------------------
# atlas_aci_check_image <full-ref>
#   Returns 0 if `docker image inspect <full-ref>` succeeds (image is in the
#   local store), 4 otherwise.
#   Uses `docker image inspect`, NOT `docker images`, because the latter has
#   different semantics for digest-only references.
#   On failure: writes a one-line actionable message to stderr.
# ---------------------------------------------------------------------------
atlas_aci_check_image() {
  local ref="$1"
  if docker image inspect "$ref" >/dev/null 2>&1; then
    return 0
  fi
  printf '%s\n' \
    "Atlas-ACI image not loaded on this host: ${ref}. Run 'eidolons mcp atlas-aci pull' to fetch it, or build it from the Atlas-ACI repository's Dockerfile." \
    >&2
  return 4
}

# ---------------------------------------------------------------------------
# atlas_aci_image_status <full-ref>
#   Runs the three check functions in sequence and prints a single structured
#   line to STDOUT (suitable for machine-readable parsing by `doctor`):
#
#     ok <ref>
#     missing-docker <ref>
#     daemon-down <ref>
#     image-missing <ref>
#
#   Exit code mirrors the first failing underlying function (2, 3, or 4), or
#   0 when all checks pass.  Diagnostic messages from each check still go to
#   stderr as usual.
# ---------------------------------------------------------------------------
atlas_aci_image_status() {
  local ref="$1"

  if ! atlas_aci_check_docker_cli; then
    printf 'missing-docker %s\n' "$ref"
    return 2
  fi

  if ! atlas_aci_check_docker_daemon; then
    printf 'daemon-down %s\n' "$ref"
    return 3
  fi

  if ! atlas_aci_check_image "$ref"; then
    printf 'image-missing %s\n' "$ref"
    return 4
  fi

  printf 'ok %s\n' "$ref"
  return 0
}
