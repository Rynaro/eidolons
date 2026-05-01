#!/usr/bin/env bash
# cli/src/mcp_atlas_aci_pull.sh — pull (or guide acquisition of) the Atlas-ACI
# Docker image so 'eidolons mcp atlas-aci' can scaffold a working .mcp.json.
#
# Usage:
#   eidolons mcp atlas-aci pull [--image-digest <sha256>]
#
# Why this command exists:
#   The Atlas-ACI image reference used in .mcp.json is a bare name+digest:
#     atlas-aci@sha256:...
#   Docker treats bare names as docker.io/library/<name>, which is not a
#   published registry — so auto-pull never works on a fresh host. This
#   command tries `docker pull` anyway (in case a registry-prefixed alias
#   was configured locally), and on failure prints the three concrete
#   alternatives for obtaining the image.
#   When a public registry is confirmed for Atlas-ACI, change DEFAULT_IMAGE_DIGEST
#   in cli/src/mcp_atlas_aci.sh (the source-of-truth) and update the template.
#   This script reads the same default via the comment below — a future bump
#   must touch both files consciously.
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
# Source-of-truth for this digest lives in cli/src/mcp_atlas_aci.sh
# (DEFAULT_IMAGE_DIGEST).  A version bump must update that file first,
# then update the constant below to match.
DEFAULT_IMAGE_DIGEST="sha256:f66dc2578f1fe4a028f42dd8d09c2e07576dd1fd6587ddd46c8704c44f8e502c"

# ─── Argument parsing ─────────────────────────────────────────────────────
IMAGE_DIGEST=""

usage() {
  cat >&2 <<EOF
eidolons mcp atlas-aci pull — obtain the Atlas-ACI Docker image on this host

Usage: eidolons mcp atlas-aci pull [OPTIONS]

Options:
  --image-digest DIGEST  Override the pinned digest (default: ${DEFAULT_IMAGE_DIGEST}).
  -h, --help             Show this help.

What it does:
  1. Verifies Docker CLI is installed.
  2. Verifies the Docker daemon is reachable.
  3. If the image is already in the local store, exits 0 immediately (no-op).
  4. Attempts 'docker pull atlas-aci@<digest>'. This succeeds only if a local
     registry alias or mirror is configured — the bare reference has no public
     registry. On failure, prints three concrete alternatives.

Three alternatives when auto-pull fails:
  1. Build locally from the Atlas-ACI source repository.
  2. Load from a tarball (docker load -i atlas-aci.tar).
  3. Pull from a private/org registry and re-tag.

After obtaining the image by any method, re-run this command to confirm.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --image-digest)
      [ -z "${2:-}" ] && die "--image-digest requires an argument"
      IMAGE_DIGEST="$2"
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
IMAGE_REF="atlas-aci@${IMAGE_DIGEST}"

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

# ─── Step 4: Attempt docker pull ──────────────────────────────────────────
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

# ─── Step 4 failure: three-alternatives block ─────────────────────────────
printf '%s\n' \
  "Atlas-ACI image could not be auto-pulled. The image reference '${IMAGE_REF}'" \
  "has no registry prefix; Docker treats it as docker.io/library/atlas-aci which" \
  "is not a published image." \
  "" \
  "To obtain the image, do ONE of:" \
  "" \
  "  1. Build locally from the Atlas-ACI source:" \
  "       git clone https://github.com/Rynaro/atlas-aci" \
  "       cd atlas-aci && docker build -t atlas-aci ." \
  "       docker tag atlas-aci atlas-aci@${IMAGE_DIGEST}     # if your build matches" \
  "" \
  "  2. Load from a tarball someone shared with you:" \
  "       docker load -i atlas-aci.tar" \
  "" \
  "  3. Pull from a private registry (if your org publishes one):" \
  "       docker pull <registry>/atlas-aci@${IMAGE_DIGEST}" \
  "       docker tag <registry>/atlas-aci@${IMAGE_DIGEST} atlas-aci@${IMAGE_DIGEST}" \
  "" \
  "Then re-run 'eidolons mcp atlas-aci pull' to verify." \
  >&2

exit 1
