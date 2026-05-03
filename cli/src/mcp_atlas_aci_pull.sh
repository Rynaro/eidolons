#!/usr/bin/env bash
# cli/src/mcp_atlas_aci_pull.sh — pull (or build) the Atlas-ACI Docker image
# so 'eidolons mcp atlas-aci' can scaffold a working .mcp.json.
#
# Usage:
#   eidolons mcp atlas-aci pull [--image-digest <sha256>] [--build-locally [--git-ref REF]]
#
# Why this command exists:
#   The Atlas-ACI image is published to ghcr.io/rynaro/atlas-aci. The default
#   happy path is 'docker pull ghcr.io/rynaro/atlas-aci@sha256:<digest>', which
#   works on any host with anonymous ghcr.io access.
#   The --build-locally flag is the air-gap escape hatch: it invokes
#   'docker build https://github.com/Rynaro/atlas-aci.git#<ref>:mcp-server'
#   for environments where ghcr.io is unreachable or the registry is temporarily
#   unavailable. This path must never be removed (P0 invariant — see T9).
#   To change the pinned digest, update DEFAULT_IMAGE_DIGEST in
#   cli/src/mcp_atlas_aci.sh (the source-of-truth) and mirror it below.
#   A digest bump must touch both files consciously.
#
# Bash 3.2 compatible — no associative arrays, no ${var,,}, no readarray.
# See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp_atlas_aci.sh"

# ─── Constants ────────────────────────────────────────────────────────────
# Source-of-truth for these constants lives in cli/src/mcp_atlas_aci.sh.
# A version bump must update that file first, then update the constants below
# to match (comment-bound contract).
#
# Pin: ghcr.io/rynaro/atlas-aci v0.2.2 (first signed GHCR publish).
DEFAULT_IMAGE_REF="ghcr.io/rynaro/atlas-aci"
DEFAULT_IMAGE_DIGEST="${DEFAULT_IMAGE_DIGEST:-sha256:386677f06b0ce23cb4883f6c0f91d8eac22328cd7d9451ae241e2f183207ad96}"
DEFAULT_IMAGE_FULL_REF="${DEFAULT_IMAGE_REF}@${DEFAULT_IMAGE_DIGEST}"
# Default git ref for --build-locally. Override with --git-ref.
ATLAS_ACI_BUILD_REF="main"

# ─── Argument parsing ─────────────────────────────────────────────────────
IMAGE_DIGEST=""
IMAGE_DIGEST_EXPLICIT=false   # set to true when user passes --image-digest
BUILD_LOCALLY=false
GIT_REF=""

usage() {
  cat >&2 <<EOF
eidolons mcp atlas-aci pull — obtain the Atlas-ACI Docker image on this host

Usage: eidolons mcp atlas-aci pull [OPTIONS]

Options:
  --image-digest DIGEST  Override the pinned digest (default: ${DEFAULT_IMAGE_DIGEST}).
  --build-locally        Build the image locally from source instead of pulling from ghcr.io.
  --git-ref REF          Git ref to build from when --build-locally is used (default: ${ATLAS_ACI_BUILD_REF}).
  -h, --help             Show this help.

What it does:
  1. Verifies Docker CLI is installed.
  2. Verifies the Docker daemon is reachable.
  3. If the image is already in the local store, exits 0 immediately (no-op).
  4. Pulls from ghcr.io (default), or builds locally if --build-locally is passed.

Air-gap / offline use:
  If ghcr.io is unreachable, use --build-locally to build the image from the
  Atlas-ACI source repository via the Docker remote git context.

After obtaining the image by any method, re-run this command to confirm.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --image-digest)
      [ -z "${2:-}" ] && die "--image-digest requires an argument"
      IMAGE_DIGEST="$2"
      IMAGE_DIGEST_EXPLICIT=true
      shift 2
      ;;
    --build-locally)
      BUILD_LOCALLY=true
      shift
      ;;
    --git-ref)
      [ -z "${2:-}" ] && die "--git-ref requires an argument"
      GIT_REF="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      warn "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

# ─── Defaults ─────────────────────────────────────────────────────────────
IMAGE_DIGEST="${IMAGE_DIGEST:-$DEFAULT_IMAGE_DIGEST}"
GIT_REF="${GIT_REF:-$ATLAS_ACI_BUILD_REF}"
IMAGE_REF="${DEFAULT_IMAGE_REF}@${IMAGE_DIGEST}"

# ─── Bootstrap-digest pre-flight ──────────────────────────────────────────
# Refuse early if the digest is still the all-zeros placeholder (no real release
# yet). Bypassed when the user explicitly passes --image-digest (known override)
# or --build-locally (the build path doesn't require a real registry digest).
# Literal string compare — bash 3.2 portable, no external tools.
_BOOTSTRAP_PLACEHOLDER="sha256:0000000000000000000000000000000000000000000000000000000000000000"
if [ "$IMAGE_DIGEST_EXPLICIT" = "false" ] && [ "$BUILD_LOCALLY" = "false" ] && [ "$IMAGE_DIGEST" = "$_BOOTSTRAP_PLACEHOLDER" ]; then
  die "DEFAULT_IMAGE_DIGEST is still the bootstrap placeholder. The first ghcr.io/rynaro/atlas-aci release has not landed yet (or the digest constant has not been updated). Either:
  1. Run 'eidolons mcp atlas-aci pull --build-locally' to build from source (air-gap escape hatch).
  2. Pass --image-digest sha256:<real-digest> to override.
  3. Wait for the first published release and the corresponding digest-bump PR.
See .spectra/plans/atlas-aci-ghcr-distribution-2026-05-01/spec.md §'Bootstrap problem'."
fi

# ─── Step 1: Docker CLI check ─────────────────────────────────────────────
if ! atlas_aci_check_docker_cli; then
  exit 1
fi

# ─── Step 2: Docker daemon check ──────────────────────────────────────────
if ! atlas_aci_check_docker_daemon; then
  exit 1
fi

# ─── Step 3: Image presence check ─────────────────────────────────────────
if atlas_aci_check_image "$IMAGE_REF"; then
  info "image already present, nothing to do"
  exit 0
fi

# ─── Step 4: Build locally OR pull from GHCR ──────────────────────────────

# INVARIANT (P0): the --build-locally branch is the air-gap escape hatch. It must never be removed. See .spectra/plans/atlas-aci-ghcr-distribution-2026-05-01/spec.md §"Architecture & invariants honored".
if [ "$BUILD_LOCALLY" = "true" ]; then
  _build_tag="${DEFAULT_IMAGE_REF}:locally-built-$(date +%Y%m%d-%H%M%S)"
  _build_url="https://github.com/Rynaro/atlas-aci.git#${GIT_REF}:mcp-server"

  say "Building locally: docker build -t ${_build_tag} ${_build_url}"
  if docker build -t "$_build_tag" "$_build_url" >&2; then
    ok "Local build complete. Image tagged: ${_build_tag}"
    warn "Note: locally-built images cannot match the upstream registry digest (${IMAGE_DIGEST})."
    warn "To use this image, pass --image-digest to override the pinned digest, or reference"
    warn "the locally-built tag directly in your docker run command: ${_build_tag}"
    exit 0
  else
    warn "Local build failed."
    exit 8
  fi
fi

# ─── Step 4a: Attempt docker pull from GHCR ───────────────────────────────
say "Attempting: docker pull ${IMAGE_REF}"

_pull_tmpfile="$(mktemp)"
# Capture combined stdout+stderr from docker pull for diagnostics.
if docker pull "$IMAGE_REF" >"$_pull_tmpfile" 2>&1; then
  rm -f "$_pull_tmpfile"
  # Re-verify: confirm the pull actually landed the expected digest.
  if atlas_aci_check_image "$IMAGE_REF"; then
    ok "Image pulled and verified: ${IMAGE_REF}"
    exit 0
  else
    # Pull claimed success but inspect still fails — unusual, surface clearly.
    die "docker pull reported success but the image is still not in the local store for '${IMAGE_REF}'. Try 'docker image inspect ${IMAGE_REF}' to diagnose."
  fi
fi

rm -f "$_pull_tmpfile"

# ─── Step 4a failure: fallback alternatives block ─────────────────────────
printf '%s\n' \
  "Atlas-ACI image could not be pulled from ${DEFAULT_IMAGE_REF}." \
  "This may be a temporary ghcr.io outage, a network restriction, or an air-gap environment." \
  "" \
  "To obtain the image, do ONE of:" \
  "" \
  "  1. Build locally (recommended air-gap / offline escape hatch):" \
  "       eidolons mcp atlas-aci pull --build-locally [--git-ref REF]" \
  "" \
  "  2. Load from a tarball someone shared with you:" \
  "       docker load -i atlas-aci.tar" \
  "" \
  "  3. Pull from a private registry mirror (if your org publishes one):" \
  "       docker pull <registry>/atlas-aci@${IMAGE_DIGEST}" \
  "       docker tag <registry>/atlas-aci@${IMAGE_DIGEST} ${IMAGE_REF}" \
  "" \
  "Then re-run 'eidolons mcp atlas-aci pull' to verify." \
  >&2

exit 1
