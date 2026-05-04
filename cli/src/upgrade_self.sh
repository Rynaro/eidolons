#!/usr/bin/env bash
# eidolons upgrade self — atomic nexus self-upgrade with rollback.
#
# Usage:
#   eidolons upgrade self [OPTIONS]
#
# Flags:
#   --ref <ref>          Upgrade to a specific branch, tag, or SHA (skips discovery).
#   --rollback           Swap nexus.prev back into place. Uses nexus.prev if it exists.
#   --check              Read-only: show what would change, then exit 0.
#   --force              Skip dirty-working-tree check and smoke-test wait.
#   --non-interactive    Proceed without confirmation prompts.
#
# Exit codes:
#   0  success or no-op
#   1  generic failure
#   2  already at requested ref but not the latest (informational)
#   4  NETWORK_ERROR (cannot reach upstream)
#   5  INTEGRITY_ERROR
#   6  smoke test failed on new nexus
#   7  rollback requested but no nexus.prev
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

# ─── Argument parsing (bash 3.2 safe — case-statement, no getopt) ─────────
REF=""
ROLLBACK=false
CHECK=false
FORCE=false
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      [[ $# -lt 2 ]] && { echo "--ref requires an argument" >&2; exit 1; }
      REF="$2"; shift 2 ;;
    --rollback)        ROLLBACK=true;           shift ;;
    --check)           CHECK=true;              shift ;;
    --force)           FORCE=true;              shift ;;
    --non-interactive) NON_INTERACTIVE=true;    shift ;;
    -h|--help)
      cat <<'HELP'
eidolons upgrade self — atomic nexus self-upgrade

Usage: eidolons upgrade self [--ref <ref>] [--check] [--rollback]
                              [--force] [--non-interactive]

Flags:
  --ref <ref>          Upgrade to a specific branch, tag, or SHA.
  --rollback           Restore the previous nexus from ~/.eidolons/nexus.prev/.
  --check              Show upgrade plan without modifying anything.
  --force              Skip dirty-check and proceed without confirmation.
  --non-interactive    Fail on prompts instead of waiting for input.

Exit codes:
  0  success / no-op   4  network error
  1  generic failure   5  integrity check failed
  2  already current   6  smoke test failed
  7  no prev to roll back to
HELP
      exit 0 ;;
    --*)
      echo "Unknown option: $1" >&2
      echo "Run: eidolons upgrade self --help" >&2
      exit 1 ;;
    *)
      echo "Unexpected argument: $1" >&2
      exit 1 ;;
  esac
done

NEXUS_PREV="$EIDOLONS_HOME/nexus.prev"
NEXUS_NEW="$EIDOLONS_HOME/nexus.new"
NEXUS_FAILED="$EIDOLONS_HOME/nexus.failed"

# ─── Helpers ──────────────────────────────────────────────────────────────

# Write install metadata sidecars into a nexus directory.
_write_install_sidecars() {
  local dir="$1" ref="$2"
  local commit
  commit="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"

  # Ensure .gitignore excludes sidecar files.
  if [[ ! -f "$dir/.gitignore" ]]; then
    printf '.install_date\n.install_ref\n.install_commit\n' > "$dir/.gitignore"
  else
    local sc
    for sc in .install_date .install_ref .install_commit; do
      grep -qxF "$sc" "$dir/.gitignore" 2>/dev/null \
        || printf '%s\n' "$sc" >> "$dir/.gitignore"
    done
  fi

  printf '%s\n' "$(date -u +%Y-%m-%d)" > "$dir/.install_date"
  printf '%s\n' "$ref"                 > "$dir/.install_ref"
  printf '%s\n' "$commit"             > "$dir/.install_commit"
}

# Check whether the nexus working tree is dirty (uncommitted local changes).
_nexus_is_dirty() {
  [[ -d "$NEXUS/.git" ]] || return 1  # no .git → not a git repo, not "dirty"
  local status
  status="$(git -C "$NEXUS" status --porcelain 2>/dev/null | head -1)"
  [[ -n "$status" ]]
}

# Determine whether REF is an exact SemVer vX.Y.Z tag (used for integrity).
_is_semver_tag() {
  local ref="$1"
  case "$ref" in
    v[0-9]*.[0-9]*.[0-9]*) return 0 ;;
    [0-9]*.[0-9]*.[0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

# Strip leading 'v' prefix.
_strip_v() { echo "${1#v}"; }

# ─── Rollback path ────────────────────────────────────────────────────────
if [[ "$ROLLBACK" == true ]]; then
  if [[ ! -d "$NEXUS_PREV" ]]; then
    say "No previous nexus found at $NEXUS_PREV"
    echo "" >&2
    die_exit7() { echo "Rollback unavailable: no nexus.prev exists." >&2; exit 7; }
    die_exit7
  fi

  # Read versions for the message.
  _cur_ver="$(read_nexus_version 2>/dev/null || echo unknown)"
  _prev_ver=""
  if [[ -f "$NEXUS_PREV/VERSION" ]]; then
    _prev_ver="$(tr -d '[:space:]' < "$NEXUS_PREV/VERSION")"
  else
    _prev_ver="$(git -C "$NEXUS_PREV" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo unknown)"
  fi

  say "Rolling back nexus $_cur_ver to $_prev_ver"
  nexus_rollback "$NEXUS_PREV" "$NEXUS_FAILED"

  echo ""
  ok "Rolled back nexus $_cur_ver -> $_prev_ver."
  echo "  The failed install is at $NEXUS_FAILED (remove when investigated)." >&2
  exit 0
fi

# ─── Dirty-tree guard (OQ-6) ──────────────────────────────────────────────
if [[ "$FORCE" != true ]] && _nexus_is_dirty; then
  echo "" >&2
  echo "The nexus has local changes (uncommitted edits in $NEXUS)." >&2
  echo "The upgrade swap will discard them." >&2
  echo "" >&2
  echo "  Commit or stash them first, or run:" >&2
  echo "    eidolons upgrade self --force" >&2
  echo "" >&2
  exit 1
fi

# ─── Discover target version ──────────────────────────────────────────────
CURRENT_VERSION="$(read_nexus_version)"
CURRENT_TAG="$(nexus_current_tag)"

if [[ -n "$REF" ]]; then
  TARGET_REF="$REF"
  say "Using pinned ref: $TARGET_REF"
else
  say "Probing upstream for latest stable release"
  LATEST_TAG=""
  LATEST_TAG="$(nexus_latest_tag 2>/dev/null || true)"
  if [[ -z "$LATEST_TAG" ]]; then
    echo "" >&2
    echo "Cannot reach upstream (https://github.com/Rynaro/eidolons)." >&2
    echo "Pass --ref <branch|tag|sha> to upgrade to a specific ref, or check connectivity." >&2
    echo "" >&2
    exit 4
  fi
  TARGET_REF="$LATEST_TAG"
fi

TARGET_VERSION="$(_strip_v "$TARGET_REF")"

# ─── No-op check: already at target ──────────────────────────────────────
if [[ -z "$REF" ]]; then
  CURRENT_BARE="$(_strip_v "$CURRENT_TAG")"
  LATEST_BARE="$(_strip_v "$LATEST_TAG")"
  if [[ "$CURRENT_BARE" == "$LATEST_BARE" ]]; then
    echo "" >&2
    ok "Already on v$CURRENT_BARE (latest). No upgrade needed."
    exit 0
  fi
fi

# ─── Downgrade warning (OQ-7) ─────────────────────────────────────────────
_is_downgrade=false
if _is_semver_tag "$TARGET_REF" && _is_semver_tag "$CURRENT_VERSION"; then
  if semver_lt "$TARGET_VERSION" "$CURRENT_VERSION" 2>/dev/null; then
    _is_downgrade=true
  fi
fi

if [[ "$_is_downgrade" == true ]]; then
  warn "Downgrading nexus $CURRENT_VERSION -> $TARGET_VERSION"
  if [[ "$FORCE" != true && "$NON_INTERACTIVE" != true ]]; then
    # shellcheck disable=SC1091
    . "$SELF_DIR/ui/prompt.sh" 2>/dev/null || true
    if command -v ui_confirm >/dev/null 2>&1; then
      if ! ui_confirm "Proceed with downgrade?" default-n; then
        die "Downgrade aborted."
      fi
    fi
  elif [[ "$FORCE" != true && "$NON_INTERACTIVE" == true ]]; then
    echo "Downgrade requires --force in non-interactive mode." >&2
    exit 1
  fi
fi

# ─── --check mode (read-only) ─────────────────────────────────────────────
if [[ "$CHECK" == true ]]; then
  _cur_commit="$(nexus_current_commit)"
  echo ""
  echo "  NEXUS"
  echo "    current:  $CURRENT_TAG  (commit ${_cur_commit:0:7})"
  echo "    target:   $TARGET_REF"
  CURRENT_BARE="$(_strip_v "$CURRENT_TAG")"
  if [[ "$CURRENT_BARE" == "$TARGET_VERSION" ]] && ! [[ "$_is_downgrade" == true ]]; then
    echo "    status:   up-to-date"
  else
    echo "    status:   upgrade available -> $TARGET_REF"
  fi
  echo ""
  exit 0
fi

# ─── Fetch into nexus.new ─────────────────────────────────────────────────
say "Upgrading nexus $CURRENT_VERSION -> $TARGET_VERSION"

# Clean up any stale nexus.new from a prior interrupted run.
rm -rf "$NEXUS_NEW"

say "Cloning $TARGET_REF into nexus.new"
if ! nexus_clone_to_sibling "$TARGET_REF" "$NEXUS_NEW" 2>/dev/null; then
  echo "" >&2
  echo "Failed to clone nexus at ref '$TARGET_REF' from upstream." >&2
  echo "The previous nexus is untouched." >&2
  rm -rf "$NEXUS_NEW"
  exit 1
fi

# ─── Integrity verification ───────────────────────────────────────────────
if _is_semver_tag "$TARGET_REF"; then
  info "Verifying release integrity for nexus@$TARGET_VERSION"
  _verify_rc=0
  nexus_verify_release "$TARGET_VERSION" "$NEXUS_NEW" || _verify_rc=$?
  if [[ "$_verify_rc" -eq 2 ]]; then
    echo "" >&2
    echo "Integrity check failed for nexus $TARGET_VERSION." >&2
    echo "Refusing to swap. The previous nexus is intact." >&2
    rm -rf "$NEXUS_NEW"
    exit 5
  elif [[ "$_verify_rc" -eq 3 ]]; then
    echo "" >&2
    echo "Integrity check failed (corrupt clone) for nexus $TARGET_VERSION." >&2
    echo "Refusing to swap. The previous nexus is intact." >&2
    rm -rf "$NEXUS_NEW"
    exit 5
  fi
else
  warn "Non-tag ref '$TARGET_REF': commit SHA verified, tree/archive checks skipped."
fi

# ─── Smoke test ───────────────────────────────────────────────────────────
if [[ "$FORCE" != true ]]; then
  info "Running smoke test on new nexus"
  _smoke_rc=0
  EIDOLONS_NEXUS="$NEXUS_NEW" bash "$NEXUS_NEW/cli/eidolons" --version --quiet \
    >/dev/null 2>&1 || _smoke_rc=$?
  if [[ "$_smoke_rc" -ne 0 ]]; then
    echo "" >&2
    echo "Smoke test failed on new nexus ($NEXUS_NEW)." >&2
    echo "The previous nexus is intact. New nexus left at $NEXUS_NEW for inspection." >&2
    exit 6
  fi
fi

# ─── Write install metadata into nexus.new before swap ───────────────────
_write_install_sidecars "$NEXUS_NEW" "$TARGET_REF"

# ─── Atomic swap ─────────────────────────────────────────────────────────
say "Swapping nexus.new into place"
_prev_ver=""
if [[ -f "$NEXUS/VERSION" ]]; then
  _prev_ver="$(tr -d '[:space:]' < "$NEXUS/VERSION")"
else
  _prev_ver="$CURRENT_VERSION"
fi

nexus_atomic_swap "$NEXUS_NEW" "$NEXUS_PREV"

echo ""
ok "Upgraded nexus $_prev_ver -> $TARGET_VERSION"
if [[ -d "$NEXUS_PREV" ]]; then
  echo "  Previous nexus preserved at $NEXUS_PREV" >&2
  echo "  To roll back: eidolons upgrade self --rollback" >&2
fi
exit 0
