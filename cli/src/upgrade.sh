#!/usr/bin/env bash
# eidolons upgrade — upgrade pinned Eidolon versions
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

# TODO: v1.1 — full semver-aware upgrade.
# For now: re-run sync with latest roster (--refresh-cache).

warn "eidolons upgrade is a stub in v1.0. Workaround:"
echo ""
echo "  1. Manually bump versions in eidolons.yaml"
echo "  2. rm -rf ~/.eidolons/cache     # force re-fetch"
echo "  3. eidolons sync                 # pull latest within constraint"
echo ""
exit 1
