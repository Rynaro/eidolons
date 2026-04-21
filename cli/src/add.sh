#!/usr/bin/env bash
# eidolons add — add one or more Eidolons to this project
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

VERSION_SPEC=""
NON_INTERACTIVE=false

usage() {
  cat <<EOF
eidolons add — add one or more Eidolons to this project

Usage: eidolons add <n> [<n>...] [OPTIONS]

Options:
  --version SPEC        Version constraint (e.g. ^1.0.0, ~2.3, =3.0.0)
                        Applies to all names in this invocation.
  --non-interactive     Fail on prompts
  -h, --help            Show this help

Examples:
  eidolons add atlas
  eidolons add atlas spectra
  eidolons add forge --version ^0.1.0
EOF
}

NAMES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)          VERSION_SPEC="$2"; shift 2 ;;
    --non-interactive)  NON_INTERACTIVE=true; shift ;;
    -h|--help)          usage; exit 0 ;;
    -*)                 echo "Unknown option: $1" >&2; exit 2 ;;
    *)                  NAMES+=("$1"); shift ;;
  esac
done

(( ${#NAMES[@]} > 0 )) || { usage; exit 2; }

manifest_exists || die "No eidolons.yaml found. Run 'eidolons init' first."

# Validate every requested name
for name in "${NAMES[@]}"; do
  roster_get "$name" >/dev/null
done

# ─── Append to eidolons.yaml ─────────────────────────────────────────────
# This is a simple line-oriented append. For complex cases we'd shell out to yq.
for name in "${NAMES[@]}"; do
  if manifest_members | grep -Fxq "$name"; then
    info "$name already in eidolons.yaml — skipping manifest update"
    continue
  fi
  entry="$(roster_get "$name")"
  latest="$(echo "$entry" | jq -r '.versions.latest')"
  repo="$(echo "$entry" | jq -r '.source.repo')"
  spec="${VERSION_SPEC:-^$latest}"

  say "Adding $name@$spec to $PROJECT_MANIFEST"
  cat >> "$PROJECT_MANIFEST" <<ENTRY
  - name: $name
    version: "$spec"
    source: github:$repo
ENTRY
done

# ─── Delegate install to sync ────────────────────────────────────────────
say "Running sync"
exec bash "$CLI_SRC/sync.sh" ${NON_INTERACTIVE:+--non-interactive}
