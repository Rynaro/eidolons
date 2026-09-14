#!/usr/bin/env bash
# eidolons remove — safely remove one managed Eidolon from this project.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: eidolons remove <name> [--non-interactive]

Removes only Eidolons-managed project state for the named member, then
regenerates eidolons.lock and host wiring with `eidolons sync`.
EOF
}

NAME=""
NON_INTERACTIVE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "Unknown option: $1 (see 'eidolons remove --help')" ;;
    *) [[ -z "$NAME" ]] || die "Remove accepts one Eidolon name at a time."; NAME="$1"; shift ;;
  esac
done
[[ -n "$NAME" ]] || { usage >&2; exit 2; }
manifest_exists || die "No eidolons.yaml found. Run 'eidolons init' first."
roster_get "$NAME" >/dev/null
manifest_members | grep -Fxq "$NAME" || die "$NAME is not a member of $PROJECT_MANIFEST."

# Validate the transformed document before replacing the original.
_manifest_tmp="$(mktemp "${PROJECT_MANIFEST}.XXXXXX")"
if ! EIDOLONS_REMOVE_NAME="$NAME" yq eval 'del(.members[] | select(.name == strenv(EIDOLONS_REMOVE_NAME)))' \
      "$PROJECT_MANIFEST" > "$_manifest_tmp" \
    || ! yq eval '.members | type == "!!seq"' "$_manifest_tmp" >/dev/null 2>&1; then
  rm -f "$_manifest_tmp"
  die "Could not remove $NAME from $PROJECT_MANIFEST structurally; it was left unchanged."
fi
mv -f "$_manifest_tmp" "$PROJECT_MANIFEST"

# Only remove the package root that Eidolons owns. Host documents may contain
# user-authored material; sync regenerates managed adapter surfaces instead of
# attempting broad text deletion here.
if [[ -d ".eidolons/$NAME" ]]; then
  rm -rf ".eidolons/$NAME"
  ok "Removed .eidolons/$NAME/"
fi

_remaining="$(manifest_members | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$_remaining" -eq 0 ]]; then
  for _host_doc in "AGENTS.md" "CLAUDE.md" ".github/copilot-instructions.md" "GEMINI.md"; do
    remove_marker_block "$_host_doc" "cortex"
    remove_marker_block "$_host_doc" "dispatch-pointer"
  done
  [[ -d ".eidolons/cortex" ]] && rm -rf ".eidolons/cortex"
  remove_marker_block ".gitignore" "gitignore" "# "
fi

say "Regenerating lockfile and managed host wiring"
sync_args=()
[[ "$NON_INTERACTIVE" == true ]] && sync_args=(--non-interactive)
exec bash "$SELF_DIR/sync.sh" "${sync_args[@]}"
