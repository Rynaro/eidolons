#!/usr/bin/env bash
# eidolons remove — remove an Eidolon from this project
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

# TODO: full implementation in v1.1
# Planned behavior:
#   - Remove member entry from eidolons.yaml
#   - Remove .eidolons/<n>/ directory
#   - Remove host dispatch sections scoped to this Eidolon (bounded by markers)
#   - Regenerate eidolons.lock via `eidolons sync`

die "eidolons remove — not yet implemented (planned: v1.1).

Workaround:
  1. Edit eidolons.yaml and delete the member entry.
  2. rm -rf .eidolons/<n>/
  3. Manually clean host dispatch files (AGENTS.md, CLAUDE.md sections).
  4. Run 'eidolons sync' to regenerate eidolons.lock.

This will be automated once per-Eidolon install.sh writes install.manifest.json
with per-file provenance (EIIS v1.0 already specifies this — we just need the
reverse-lookup logic here)."
