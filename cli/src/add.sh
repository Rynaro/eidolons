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

# ─── Update eidolons.yaml structurally ───────────────────────────────────
# A line append silently placed a member under whichever key happened to be
# last, and could produce a second members: block. mikefarah/yq preserves the
# surrounding document structure/comments while editing the members sequence.
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
  _manifest_tmp="$(mktemp "${PROJECT_MANIFEST}.XXXXXX")"
  if ! EIDOLONS_ADD_NAME="$name" EIDOLONS_ADD_VERSION="$spec" EIDOLONS_ADD_SOURCE="github:$repo" \
      yq eval '.members += [{"name": strenv(EIDOLONS_ADD_NAME), "version": strenv(EIDOLONS_ADD_VERSION), "source": strenv(EIDOLONS_ADD_SOURCE)}]' \
        "$PROJECT_MANIFEST" > "$_manifest_tmp" \
      || ! yq eval '.' "$_manifest_tmp" >/dev/null 2>&1; then
    rm -f "$_manifest_tmp"
    die "Could not update $PROJECT_MANIFEST structurally; it was left unchanged."
  fi
  mv -f "$_manifest_tmp" "$PROJECT_MANIFEST"
done

# ─── Delegate install to sync ────────────────────────────────────────────
say "Running sync"
sync_args=()
[[ "$NON_INTERACTIVE" == true ]] && sync_args=(--non-interactive)
exec bash "$SELF_DIR/sync.sh" "${sync_args[@]}"
