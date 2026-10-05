#!/usr/bin/env bash
# eidolons add — add one or more Eidolons to this project
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_model_resolve.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_model_wiring.sh"

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
_manifest_tmp="$(mktemp "${PROJECT_MANIFEST}.XXXXXX")"
cp "$PROJECT_MANIFEST" "$_manifest_tmp"
for name in "${NAMES[@]}"; do
  if yq -r '.members[].name' "$_manifest_tmp" | grep -Fxq "$name"; then
    info "$name already in eidolons.yaml — skipping manifest update"
    continue
  fi
  entry="$(roster_get "$name")"
  latest="$(echo "$entry" | jq -r '.versions.latest')"
  repo="$(echo "$entry" | jq -r '.source.repo')"
  spec="${VERSION_SPEC:-^$latest}"

  say "Adding $name@$spec to $PROJECT_MANIFEST"
  _manifest_next="$(mktemp "${PROJECT_MANIFEST}.XXXXXX")"
  if ! EIDOLONS_ADD_NAME="$name" EIDOLONS_ADD_VERSION="$spec" EIDOLONS_ADD_SOURCE="github:$repo" \
      yq eval '.members += [{"name": strenv(EIDOLONS_ADD_NAME), "version": strenv(EIDOLONS_ADD_VERSION), "source": strenv(EIDOLONS_ADD_SOURCE)}]' \
        "$_manifest_tmp" > "$_manifest_next" \
      || ! yq eval '.' "$_manifest_next" >/dev/null 2>&1; then
    rm -f "$_manifest_tmp" "$_manifest_next"
    die "Could not update $PROJECT_MANIFEST structurally; it was left unchanged."
  fi
  mv -f "$_manifest_next" "$_manifest_tmp"
done
if ! cmp -s "$_manifest_tmp" "$PROJECT_MANIFEST"; then
  model_resolve_init "" "" "$_manifest_tmp"
  if ! model_wiring_preflight_resolution_all || ! model_wiring_preflight_existing_all; then
    rm -f "$_manifest_tmp"
    die "Model policy is incomplete; $PROJECT_MANIFEST was left unchanged. Set models.hosts.<host>.profile for each wired host."
  fi
  chmod --reference="$PROJECT_MANIFEST" "$_manifest_tmp" 2>/dev/null || true
  mv -f "$_manifest_tmp" "$PROJECT_MANIFEST"
else
  rm -f "$_manifest_tmp"
fi

# ─── Delegate install to sync ────────────────────────────────────────────
say "Running sync"
sync_args=()
[[ "$NON_INTERACTIVE" == true ]] && sync_args=(--non-interactive)
exec bash "$SELF_DIR/sync.sh" "${sync_args[@]}"
