#!/usr/bin/env bash
# cli/src/mcp_atlas_aci_pull.sh — thin wrapper over mcp_driver_oci_image_pull
# for the atlas-aci MCP. Preserves back-compat for callers that invoke this
# script directly (e.g. mcp_driver_oci_image_refresh, mcp_refresh.sh --image-digest).
#
# OQ-1.A: this script is now a thin wrapper. All pull logic lives in the generic
# mcp_driver_oci_image_pull function in lib_mcp.sh. This script delegates and
# passes all flags through unchanged.
#
# Usage:
#   eidolons mcp atlas-aci pull [--image-digest <sha256>] [--build-locally [--git-ref REF]]
#
# INVARIANT (P0): the --build-locally branch is the air-gap escape hatch.
# It must never be removed. The implementation lives in mcp_driver_oci_image_pull
# (cli/src/lib_mcp.sh). The source-grep guard in T9 Case 9 is updated to search
# lib_mcp.sh instead of this file.
#
# Back-compat constants (retained for comment-bound contract):
#   DEFAULT_IMAGE_REF    = ghcr.io/rynaro/atlas-aci
#   DEFAULT_IMAGE_DIGEST = from catalogue pins.stable (resolved by the driver)
#   ATLAS_ACI_BUILD_REF  = main (default, overridable with --git-ref)
#
# Bash 3.2 compatible — no associative arrays, no ${var,,}, no readarray.
# See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"

# Delegate all arguments to the generic pull driver for atlas-aci.
# mcp_driver_oci_image_pull reads the catalogue for the image ref and pinned
# digest; --image-digest overrides; --build-locally gates to source.build.
exec bash "$SELF_DIR/mcp_pull.sh" "atlas-aci" "$@"
