#!/usr/bin/env bash
# cli/src/mcp_atlas_aci.sh — Atlas-ACI per-project MCP generator.
#
# Renders cli/templates/mcp/atlas-aci.mcp.json.tmpl into <project-root>/.mcp.json
# and pre-creates <project-root>/.atlas/memex/ (the host-side bind-mount surface
# the Atlas-ACI Docker container needs for its sqlite codegraph DB).
#
# Usage:
#   eidolons mcp atlas-aci [--force] [--image-digest <sha256>] [--project-root <path>]
#                          [--skip-image-check]
#
# Subcommand surface (routed here from cli/eidolons — see T3):
#   --project-root PATH    Directory to scaffold (default: cwd).
#   --image-digest DIGEST  Override the pinned Docker image digest.
#   --force                Overwrite an existing .mcp.json without prompting.
#   --skip-image-check     Skip Docker + image pre-flight checks. Use only in CI
#                          where the image is loaded after scaffolding. Emits a
#                          warning; the MCP server will fail at boot if the image
#                          is absent.
#   -h, --help             Print this help.
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
# Default image reference and digest — bump here (one place) on Atlas-ACI image version bumps.
# Mirror the same constants in cli/src/mcp_atlas_aci_pull.sh (comment-bound contract).
#
# Pin: ghcr.io/rynaro/atlas-aci v0.2.2 (first signed GHCR publish, multi-arch amd64+arm64,
# cosign keyless signature + SBOM (SPDX) + build provenance, Trivy gate green).
DEFAULT_IMAGE_REF="ghcr.io/rynaro/atlas-aci"
DEFAULT_IMAGE_DIGEST="sha256:386677f06b0ce23cb4883f6c0f91d8eac22328cd7d9451ae241e2f183207ad96"
DEFAULT_IMAGE_FULL_REF="${DEFAULT_IMAGE_REF}@${DEFAULT_IMAGE_DIGEST}"

# Template path — resolved relative to the nexus (SELF_DIR/../templates/...).
TEMPLATE_FILE="$SELF_DIR/../templates/mcp/atlas-aci.mcp.json.tmpl"

# ─── Argument parsing ─────────────────────────────────────────────────────
PROJECT_ROOT=""
IMAGE_DIGEST=""
IMAGE_DIGEST_EXPLICIT=false   # set to true when user passes --image-digest
FORCE=false
SKIP_IMAGE_CHECK=false

usage() {
  cat >&2 <<EOF
eidolons mcp atlas-aci — generate a per-project Atlas-ACI MCP configuration

Usage: eidolons mcp atlas-aci [OPTIONS]

Options:
  --project-root PATH    Project directory to scaffold (default: current dir).
  --image-digest DIGEST  Docker image digest to pin (default: ${DEFAULT_IMAGE_DIGEST}).
  --force                Overwrite an existing .mcp.json without prompting.
  --skip-image-check     Skip Docker + image pre-flight. Use only in CI where
                         the image is loaded after scaffolding. The MCP server
                         will fail at boot if the image is absent.
  -h, --help             Show this help.

What it does:
  1. Runs a Docker + image pre-flight check (skip with --skip-image-check).
  2. Computes a project slug from the project root directory name.
  3. Pre-creates <project-root>/.atlas/memex/ and writes .gitkeep if absent.
  4. Renders the Atlas-ACI MCP template into <project-root>/.mcp.json.

The generated .mcp.json wires Atlas-ACI as a Docker-based MCP server with:
  - A per-project container name (atlas-aci-<slug>) for parallel-project isolation.
  - Distinct bind mounts so each project's codegraph.db is independent.
  - The pinned image digest (no tag drift).

If the image is not on your host yet, run 'eidolons mcp atlas-aci pull' first.
Rerun with --force to regenerate .mcp.json after an image-digest bump.
Existing .atlas/memex/codegraph.db is NEVER deleted.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      [[ -z "${2:-}" ]] && die "--project-root requires an argument"
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --image-digest)
      [[ -z "${2:-}" ]] && die "--image-digest requires an argument"
      IMAGE_DIGEST="$2"
      IMAGE_DIGEST_EXPLICIT=true
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --skip-image-check)
      SKIP_IMAGE_CHECK=true
      shift
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
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
IMAGE_DIGEST="${IMAGE_DIGEST:-$DEFAULT_IMAGE_DIGEST}"

# Resolve to an absolute path (guard against relative inputs).
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" \
  || die "Project root does not exist: ${PROJECT_ROOT}"

# ─── Bootstrap-digest pre-flight ──────────────────────────────────────────
# Refuse early if the digest is still the all-zeros placeholder that ships
# before the first ghcr.io/rynaro/atlas-aci release. A literal string compare
# is portable to bash 3.2 (no regex, no ${var,,}, no external tools).
# Bypassed when the user explicitly passes --image-digest (they know what they
# are doing — the guard is for the default case only).
_BOOTSTRAP_PLACEHOLDER="sha256:0000000000000000000000000000000000000000000000000000000000000000"
if [ "$IMAGE_DIGEST_EXPLICIT" = "false" ] && [ "$IMAGE_DIGEST" = "$_BOOTSTRAP_PLACEHOLDER" ]; then
  die "DEFAULT_IMAGE_DIGEST is still the bootstrap placeholder. The first ghcr.io/rynaro/atlas-aci release has not landed yet (or the digest constant has not been updated). Either:
  1. Run 'eidolons mcp atlas-aci pull --build-locally' to build from source (air-gap escape hatch).
  2. Pass --image-digest sha256:<real-digest> to override.
  3. Wait for the first published release and the corresponding digest-bump PR.
See .spectra/plans/atlas-aci-ghcr-distribution-2026-05-01/spec.md §'Bootstrap problem'."
fi

# ─── Docker + image pre-flight ────────────────────────────────────────────
# Runs before any filesystem write so a broken setup never leaves a partial
# scaffold tree. Use --skip-image-check only in CI where the image is loaded
# after scaffolding (e.g. the image is built in a later pipeline step).
if [ "$SKIP_IMAGE_CHECK" = "true" ]; then
  warn "Skipping image pre-flight check (--skip-image-check). The MCP server will fail at boot if the image is not loaded."
else
  if ! atlas_aci_check_docker_cli; then
    exit 1
  fi
  if ! atlas_aci_check_docker_daemon; then
    exit 1
  fi
  if ! atlas_aci_check_image "${DEFAULT_IMAGE_REF}@${IMAGE_DIGEST}"; then
    exit 1
  fi
fi

# ─── Template presence check ──────────────────────────────────────────────
# The template is shipped by T2. If T2 has not landed yet, fail clearly.
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  die "Template not found: $TEMPLATE_FILE
  This file is created by task T2 of the atlas-aci-sqlite-cross-project-fix spec.
  Ensure T2 has been merged before running this command."
fi

# ─── Compute project slug ─────────────────────────────────────────────────
# Slug rule: lowercase, replace non-alnum with '-', collapse runs, trim edges.
# Bash 3.2 safe: use 'tr' for lowercasing (no \${var,,}).
_basename="$(basename "$PROJECT_ROOT")"
PROJECT_SLUG="$(printf '%s' "$_basename" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -cs 'a-z0-9' '-' \
  | sed -e 's|^-||' -e 's|-$||')"

# Guard against an empty or degenerate slug (e.g. root dir "/").
if [[ -z "$PROJECT_SLUG" || "$PROJECT_SLUG" == "-" ]]; then
  die "Cannot compute a valid project slug from directory name '${_basename}'. Use a meaningful directory name."
fi

say "Project root:   $PROJECT_ROOT"
say "Project slug:   $PROJECT_SLUG"
say "Image digest:   $IMAGE_DIGEST"

# ─── Pre-create .atlas/memex/ ─────────────────────────────────────────────
MEMEX_DIR="$PROJECT_ROOT/.atlas/memex"
GITKEEP="$MEMEX_DIR/.gitkeep"

if [[ ! -d "$MEMEX_DIR" ]]; then
  say "Creating $MEMEX_DIR"
  mkdir -p "$MEMEX_DIR"
fi

if [[ ! -f "$GITKEEP" ]]; then
  : > "$GITKEEP"
  ok "Wrote $GITKEEP"
else
  info "$GITKEEP already present — skipping"
fi

# ─── Idempotency guard ────────────────────────────────────────────────────
MCP_JSON="$PROJECT_ROOT/.mcp.json"

if [[ -f "$MCP_JSON" ]] && [[ "$FORCE" != "true" ]]; then
  die "$MCP_JSON already exists.
  Re-run with --force to overwrite it, or merge manually.
  Note: --force never deletes .atlas/memex/codegraph.db."
fi

# ─── Render template ──────────────────────────────────────────────────────
say "Rendering template: $TEMPLATE_FILE"

# Use | as the sed delimiter so absolute paths (which contain /) are safe.
# Three substitution passes: PROJECT_ROOT, PROJECT_SLUG, IMAGE_DIGEST.
sed \
  -e "s|__PROJECT_ROOT__|${PROJECT_ROOT}|g" \
  -e "s|__PROJECT_SLUG__|${PROJECT_SLUG}|g" \
  -e "s|__IMAGE_DIGEST__|${IMAGE_DIGEST}|g" \
  "$TEMPLATE_FILE" > "$MCP_JSON"

ok "Written: $MCP_JSON"

# ─── Summary ──────────────────────────────────────────────────────────────
info "Atlas-ACI MCP scaffold complete."
info "  Container name : atlas-aci-${PROJECT_SLUG}"
info "  Bind mount     : ${MEMEX_DIR} → /memex (inside container)"
info "  Image digest   : ${IMAGE_DIGEST}"
info ""
info "Next steps:"
info "  1. Commit .atlas/memex/.gitkeep so the directory exists in fresh clones."
info "  2. Optionally add .mcp.json to .gitignore if it contains machine-specific paths."
info "  3. Start Claude Code in '${PROJECT_ROOT}' — the MCP server wires automatically."
info "  4. To regenerate after an image update: eidolons mcp atlas-aci --force --image-digest <new-digest>"
