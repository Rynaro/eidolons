#!/usr/bin/env bash
# eidolons remove — remove an Eidolon from this project
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

NAME="${1:-}"
[[ -z "$NAME" ]] && die "Usage: eidolons remove <name>"

# ─── Cortex host-doc block removal ────────────────────────────────────────
# Remove the <!-- eidolon:cortex start/end --> block from all root host docs
# that carry it. This runs before the per-Eidolon removal stub so that the
# cortex is cleaned up even while the full remove pipeline is v1.1-stubbed.
#
# Policy: remove the cortex block only when the named Eidolon is the LAST
# installed member. If other Eidolons remain, the cortex stays useful.

_remaining="$(manifest_members 2>/dev/null | grep -v "^${NAME}$" | grep -v '^$' | wc -l | tr -d ' ')" || _remaining=0
if [[ "$_remaining" -eq 0 ]]; then
  say "Last Eidolon — removing cortex + dispatch-pointer host-doc blocks and .eidolons/cortex/"
  # Cortex block lived in the original three; the dispatch-pointer block
  # also lives in GEMINI.md (added by PR-A1). Iterate both surfaces.
  for _host_doc in "AGENTS.md" "CLAUDE.md" ".github/copilot-instructions.md" "GEMINI.md"; do
    remove_marker_block "$_host_doc" "cortex"
    remove_marker_block "$_host_doc" "dispatch-pointer"
  done
  # Remove the mirrored cortex directory.
  if [[ -d ".eidolons/cortex" ]]; then
    rm -rf ".eidolons/cortex"
    ok "Removed .eidolons/cortex/"
  fi
else
  info "Other Eidolons remain — cortex + dispatch-pointer blocks preserved"
fi

# ─── Per-Eidolon removal (v1.1) ──────────────────────────────────────────
# TODO: full implementation in v1.1
# Planned behavior:
#   - Remove member entry from eidolons.yaml
#   - Remove .eidolons/<n>/ directory
#   - Remove host dispatch sections scoped to this Eidolon (bounded by markers)
#   - Regenerate eidolons.lock via `eidolons sync`

die "eidolons remove — per-Eidolon removal not yet implemented (planned: v1.1).

Cortex host-doc blocks have been cleaned up (if this was the last Eidolon).

Workaround for per-Eidolon cleanup:
  1. Edit eidolons.yaml and delete the member entry.
  2. rm -rf .eidolons/<n>/
  3. Manually clean host dispatch files (AGENTS.md, CLAUDE.md sections).
  4. Run 'eidolons sync' to regenerate eidolons.lock.

This will be automated once per-Eidolon install.sh writes install.manifest.json
with per-file provenance (EIIS v1.0 already specifies this — we just need the
reverse-lookup logic here)."
