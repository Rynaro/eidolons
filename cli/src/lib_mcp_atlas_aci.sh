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
# atlas_aci_check_registry_reachable <full-ref>
#   Performs an anonymous-token-authenticated HEAD request against the ghcr.io
#   v2 manifests endpoint to verify the pinned digest is publicly reachable.
#
#   Protocol (two-step):
#     1. Fetch an anonymous bearer token scoped to the repository.
#     2. HEAD the manifest URL; 200 → reachable, anything else → unreachable.
#
#   <full-ref> must be in the form: ghcr.io/<namespace>/<image>@sha256:<hex>
#   The function parses the namespace, image, and digest from the ref.
#
#   Returns 0 on 200 OK.
#   Returns 5 on 404, network error, missing curl, missing jq, or parse error.
#   All diagnostic output goes to stderr only.
# ---------------------------------------------------------------------------
atlas_aci_check_registry_reachable() {
  local full_ref="$1"

  # Graceful degradation: curl must be present.
  if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' \
      "atlas_aci_check_registry_reachable: curl not on PATH — skipping registry probe." \
      >&2
    return 5
  fi

  # Graceful degradation: jq must be present (used to extract the token).
  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' \
      "atlas_aci_check_registry_reachable: jq not on PATH — skipping registry probe." \
      >&2
    return 5
  fi

  # Parse the full-ref: ghcr.io/<namespace>/<image>@sha256:<hex>
  # Strip the registry host prefix.
  local _ref_no_host
  _ref_no_host="${full_ref#ghcr.io/}"

  # Extract namespace (first path segment before '/').
  local _namespace
  _namespace="${_ref_no_host%%/*}"

  # Extract image+digest (everything after the first '/').
  local _image_and_digest
  _image_and_digest="${_ref_no_host#*/}"

  # Split image from digest at the '@'.
  local _image
  _image="${_image_and_digest%%@*}"

  # Extract the digest (sha256:<hex>).
  local _digest
  _digest="${_image_and_digest#*@}"

  # Validate that we extracted non-empty parts.
  if [ -z "$_namespace" ] || [ -z "$_image" ] || [ -z "$_digest" ]; then
    printf '%s\n' \
      "atlas_aci_check_registry_reachable: cannot parse full-ref '${full_ref}' — expected ghcr.io/<ns>/<img>@sha256:<hex>. Use --build-locally as the recovery path." \
      >&2
    return 5
  fi

  # Step 1: fetch an anonymous bearer token for the repository.
  local _token_url="https://ghcr.io/token?scope=repository:${_namespace}/${_image}:pull"
  local _token_json
  _token_json="$(curl -fsSL "$_token_url" 2>/dev/null)" || {
    printf '%s\n' \
      "atlas_aci_check_registry_reachable: failed to fetch token from ghcr.io — network unreachable? Use --build-locally as the recovery path." \
      >&2
    return 5
  }

  local _token
  _token="$(printf '%s' "$_token_json" | jq -r '.token // empty' 2>/dev/null)"
  if [ -z "$_token" ]; then
    printf '%s\n' \
      "atlas_aci_check_registry_reachable: token response did not contain .token — unexpected ghcr.io response. Use --build-locally as the recovery path." \
      >&2
    return 5
  fi

  # Step 2: HEAD the manifest endpoint; 200 means the digest is reachable.
  local _manifest_url="https://ghcr.io/v2/${_namespace}/${_image}/manifests/${_digest}"
  local _http_status
  _http_status="$(curl -fsI \
    -H "Authorization: Bearer ${_token}" \
    -o /dev/null \
    -w '%{http_code}' \
    "$_manifest_url" 2>/dev/null)" || true

  if [ "$_http_status" = "200" ]; then
    return 0
  fi

  printf '%s\n' \
    "atlas_aci_check_registry_reachable: manifest HEAD returned '${_http_status:-<no response>}' for ${full_ref} — offline? or pinned digest yanked? Use --build-locally as the recovery path." \
    >&2
  return 5
}

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
