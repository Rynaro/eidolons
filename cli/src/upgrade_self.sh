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
#   --allow-unverified   Proceed when release integrity has no evidence either
#                        way (absent/network). Never overrides a detected
#                        mismatch or a corrupt clone — those always refuse.
#
# Exit codes:
#   0  success or no-op
#   1  generic failure
#   2  already at requested ref but not the latest (informational)
#   4  NETWORK_ERROR (cannot reach upstream)
#   5  INTEGRITY_ERROR (mismatch, corrupt clone, or no evidence refused under strict)
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
ALLOW_UNVERIFIED=false
INTEGRITY_TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      [[ $# -lt 2 ]] && { echo "--ref requires an argument" >&2; exit 1; }
      REF="$2"; shift 2 ;;
    --rollback)          ROLLBACK=true;          shift ;;
    --check)             CHECK=true;             shift ;;
    --force)             FORCE=true;             shift ;;
    --non-interactive)   NON_INTERACTIVE=true;   shift ;;
    --allow-unverified)  ALLOW_UNVERIFIED=true;  shift ;;
    -h|--help)
      cat <<'HELP'
eidolons upgrade self — atomic nexus self-upgrade

Usage: eidolons upgrade self [--ref <ref>] [--check] [--rollback]
                              [--force] [--non-interactive] [--allow-unverified]

Flags:
  --ref <ref>          Upgrade to a specific branch, tag, or SHA.
  --rollback           Restore the previous nexus from ~/.eidolons/nexus.prev/.
  --check              Show upgrade plan without modifying anything.
  --force              Skip dirty-check and proceed without confirmation.
  --non-interactive    Fail on prompts instead of waiting for input.
  --allow-unverified   Proceed when integrity has no evidence either way
                        (absent/network). Never overrides a detected mismatch.

Exit codes:
  0  success / no-op   4  network error
  1  generic failure   5  integrity check failed, or no evidence refused under strict
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

# Defense-in-depth: backfill .roster_ref for pre-v1.11.0 installs so that
# nexus_refresh tracks main even when upgrade self runs before any sync/init
# call that would otherwise trigger the backfill via nexus_refresh.
# nexus_ensure_roster_ref is a no-op when .roster_ref already exists.
if [[ -d "$NEXUS/.git" ]]; then
  nexus_ensure_roster_ref
fi

# ─── Helpers ──────────────────────────────────────────────────────────────

# Write install metadata sidecars into a nexus directory.
# B1: do NOT touch .roster_ref here — it pins the roster-refresh target
# separately from the CLI self-pin (.install_ref). The upgrade_self path
# only updates the CLI version; the user's configured roster branch must
# survive intact so nexus_refresh continues tracking the right branch.
# .roster_ref is written exclusively by install.sh (bootstrap) and
# nexus_roster_ref reads it via nexus_refresh in lib.sh.
_write_install_sidecars() {
  local dir="$1" ref="$2"
  local commit
  commit="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"

  # Ensure .gitignore excludes sidecar files.
  # B1: .roster_ref is also excluded here so it survives atomic swap + rollback.
  if [[ ! -f "$dir/.gitignore" ]]; then
    printf '.install_date\n.install_ref\n.install_commit\n.roster_ref\n' > "$dir/.gitignore"
  else
    local sc
    for sc in .install_date .install_ref .install_commit .roster_ref; do
      grep -qxF "$sc" "$dir/.gitignore" 2>/dev/null \
        || printf '%s\n' "$sc" >> "$dir/.gitignore"
    done
  fi

  # Only .install_date, .install_ref, and .install_commit are written here.
  # .roster_ref is intentionally left alone — see B1 note above.
  printf '%s\n' "$(date -u +%Y-%m-%d)" > "$dir/.install_date"
  printf '%s\n' "$ref"                 > "$dir/.install_ref"
  printf '%s\n' "$commit"             > "$dir/.install_commit"
}

# Check whether the nexus working tree is dirty (uncommitted local changes).
# Keep this in sync with REFRESH_PATHS in nexus_refresh (lib.sh STORY-1):
#   roster   EIDOLONS.md   methodology/cortex
# Those three paths are excluded from the porcelain check because nexus_refresh
# path-checkout induces drift there intentionally (CLI pinned / roster floats).
# The upgrade-self clone+swap discards the old cache entirely, so data-layer
# drift is throwaway. Genuine edits to CLI code (cli/src/*.sh, etc.) still trip
# the guard — that is the guard's only real job.
_nexus_is_dirty() {
  [[ -d "$NEXUS/.git" ]] || return 1  # no .git → not a git repo, not "dirty"
  local status
  # Pathspec negation `:!<path>` excludes refresh-managed data paths.
  # Verified to work on macOS git (2.39+) and GitHub Actions runner git.
  status="$(git -C "$NEXUS" status --porcelain -- \
    . ':!roster' ':!EIDOLONS.md' ':!methodology/cortex' 2>/dev/null | head -1)"
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

# _upgrade_self_enforcement_mode — the fail-closed enforcement read (AC-23),
# normalised AT THIS CALL SITE ONLY. integrity_enforcement_mode (lib.sh) is
# NOT changed: verify.sh:68 and doctor.sh:230 share it and the per-Eidolon
# member integrity path is frozen anti-scope (risk R-6,
# https://github.com/Rynaro/eidolons/issues/562). That helper echoes
# EIDOLONS_INTEGRITY_ENFORCEMENT verbatim and returns the literal string
# "warn" when $ROSTER_FILE is unreadable (`set -o pipefail` fires the
# `|| echo "warn"` on a failing yaml_to_json) — indistinguishable at the call
# site from a roster that genuinely says `warn`. Hence clause (ii)'s
# independent parse check, rather than a smarter read of the helper's output.
#
# (i) EIDOLONS_INTEGRITY_ENFORCEMENT set: trim + lowercase (bash 3.2:
#     `tr '[:upper:]' '[:lower:]'`, never `${var,,}`), accept ONLY
#     strict/warn; anything else — including empty after trim — resolves to
#     the REFUSING posture (strict).
# (ii) Unset: consult integrity_enforcement_mode AND independently confirm
#     $ROSTER_FILE parses (yaml_to_json succeeds). If it does not parse or
#     does not exist, use strict regardless of what the helper returned.
_upgrade_self_enforcement_mode() {
  local raw normalized

  # `${VAR+x}` (existence test) rather than `${VAR:-}` (value test) — the
  # criterion's "including empty" clause covers the variable being SET to an
  # empty string, which `-n "${VAR:-}"` cannot distinguish from unset. Unset
  # falls through to clause (ii) below; set-but-empty is handled here and
  # resolves to strict, same as any other unrecognised value.
  if [[ -n "${EIDOLONS_INTEGRITY_ENFORCEMENT+x}" ]]; then
    raw="${EIDOLONS_INTEGRITY_ENFORCEMENT}"
    normalized="$(printf '%s' "$raw" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
      strict|warn) echo "$normalized"; return 0 ;;
      *)           echo "strict";      return 0 ;;
    esac
  fi

  # Parenthesised (subshell) call: yaml_to_json's own last resort is
  # die() -> exit 1 when no YAML backend is available at all, and an
  # unparenthesised call here would take the whole script down with it
  # instead of reporting "unparseable" to this function's caller. A subshell
  # confines that exit to itself.
  if ! ( yaml_to_json "$ROSTER_FILE" >/dev/null 2>&1 ); then
    echo "strict"
    return 0
  fi

  raw="$(integrity_enforcement_mode)"
  normalized="$(printf '%s' "$raw" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    strict|warn) echo "$normalized"; return 0 ;;
    *)           echo "strict";      return 0 ;;
  esac
}

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

# ─── Integrity verification ────────────────────────────────────────────────
# nexus_verify_release (lib.sh) CLASSIFIES evidence from two sources (the
# installed roster + the upstream default branch) and returns a token on
# NEXUS_VERIFY_STATUS. Policy is applied HERE, at the call site — mirrors
# verify.sh:68 and doctor.sh:230, which both consult integrity_enforcement_mode
# where they are called rather than inside a shared helper.
#
# Every read of NEXUS_VERIFY_STATUS is ${NEXUS_VERIFY_STATUS:-}: on the
# non-tag branch below, nexus_verify_release is never called, and
# `set -euo pipefail` (line 24) turns an unguarded read into an
# `unbound variable` abort immediately before the summary line.
if _is_semver_tag "$TARGET_REF"; then
  info "Verifying release integrity for nexus@$TARGET_VERSION"
  _verify_rc=0
  nexus_verify_release "$TARGET_VERSION" "$NEXUS_NEW" || _verify_rc=$?
  _verify_status="${NEXUS_VERIFY_STATUS:-}"

  case "$_verify_rc" in
    2)
      # Mismatch is unconditional: never relaxed by --allow-unverified or by
      # EIDOLONS_INTEGRITY_ENFORCEMENT=warn. A flag wide enough to swallow a
      # detected mismatch is not an escape hatch, it is an off switch.
      echo "" >&2
      echo "Integrity check failed for nexus $TARGET_VERSION (mismatch)." >&2
      echo "Refusing to swap. The previous nexus is intact." >&2
      rm -rf "$NEXUS_NEW"
      exit 5
      ;;
    3)
      # Corrupt clone is likewise unconditional.
      echo "" >&2
      echo "Integrity check failed (corrupt clone) for nexus $TARGET_VERSION." >&2
      echo "Refusing to swap. The previous nexus is intact." >&2
      rm -rf "$NEXUS_NEW"
      exit 5
      ;;
    4)
      # No evidence anywhere. Policy depends on the token and on enforcement
      # mode. The placeholder row is a separate, intentional bootstrap-window
      # skip (anti-scope: not repurposed) and warns+proceeds under BOTH modes,
      # unaffected by --allow-unverified.
      if [[ "${_verify_status:-}" == "placeholder" ]]; then
        warn "nexus@$TARGET_VERSION release metadata is a bootstrap placeholder — skipping verification."
        INTEGRITY_TOKEN="UNVERIFIED - placeholder"
      else
        # AC-25: a suppressed witness is named, not folded into the benign
        # case. The severity rule can select `absent` while the OTHER source
        # actually reported `network` (upstream unreachable) — that source's
        # report is real evidence of a fetch failure, not silence, and
        # folding it into the plain "(absent)" reason makes it
        # indistinguishable from the benign release-day window where both
        # sources are genuinely silent. The severity ORDER is unchanged
        # (absent still wins, strict still refuses); this only changes what
        # the message says. Both new globals follow the same ${VAR:-}
        # discipline as NEXUS_VERIFY_STATUS.
        _reason="${_verify_status:-absent}"
        if [[ "$_reason" == "absent" ]] \
          && { [[ "${NEXUS_VERIFY_INSTALLED_STATUS:-}" == "network" ]] || [[ "${NEXUS_VERIFY_UPSTREAM_STATUS:-}" == "network" ]]; }; then
          _reason="absent, upstream unreachable"
        fi

        _mode="$(_upgrade_self_enforcement_mode)"
        if [[ "$_mode" == "strict" && "$ALLOW_UNVERIFIED" != true ]]; then
          echo "" >&2
          echo "nexus@$TARGET_VERSION release integrity could not be verified (${_reason})." >&2
          echo "Refusing to swap under strict enforcement. The previous nexus is intact." >&2
          echo "  Re-run with --allow-unverified, or set EIDOLONS_INTEGRITY_ENFORCEMENT=warn, to proceed anyway." >&2
          rm -rf "$NEXUS_NEW"
          exit 5
        fi
        warn "nexus@$TARGET_VERSION release integrity could not be verified (${_reason}); proceeding unverified."
        INTEGRITY_TOKEN="UNVERIFIED - ${_reason}"
      fi
      ;;
    0)
      if [[ "${_verify_status:-}" == "verified:local-only" ]]; then
        INTEGRITY_TOKEN="verified:local-only"
      else
        INTEGRITY_TOKEN="verified"
      fi
      ;;
    *)
      # Out-of-contract return code from nexus_verify_release. Its documented
      # closed set is {0,2,3,4} (lib.sh:1155-1164) — anything else means the
      # function changed under us, or a future call site drops the `||
      # _verify_rc=$?` guard and lets an unrelated failure's exit status land
      # here. The old catch-all treated every such code as "verified", which
      # is a fail-open default on the security path this change exists to
      # close (see verification.md — the checker forced `return 4` to
      # `return 9` and got exit 0, "(integrity: verified)", swap completed).
      # Refuse instead, and name the code so the failure is diagnosable.
      echo "" >&2
      echo "nexus@$TARGET_VERSION integrity check returned an unexpected code (rc=${_verify_rc}) from nexus_verify_release." >&2
      echo "Refusing to swap. The previous nexus is intact." >&2
      rm -rf "$NEXUS_NEW"
      exit 5
      ;;
  esac
else
  # No release record exists for a non-tag ref by construction — an explicit
  # --ref <branch|sha> is a developer opt-in, and refusing it would break that
  # documented workflow. This warning must not assert that anything was
  # verified (that was the second live instance of #561's defect class).
  warn "Non-tag ref '$TARGET_REF': no release record exists for a non-tag ref; nothing was verified."
  INTEGRITY_TOKEN="UNVERIFIED - non-tag ref"
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

# ─── Carry .roster_ref into nexus.new (STORY-4) ──────────────────────────
# The fresh clone ($NEXUS_NEW) has no .roster_ref; we must carry the old
# value forward so the user's configured channel survives the swap.
# B1 invariant preserved: _write_install_sidecars intentionally does NOT write
# .roster_ref (it only writes the CLI-pin sidecars). We carry it here explicitly.
_old_roster_ref="${EIDOLONS_ROSTER_REF:-}"
if [[ -f "$NEXUS/.roster_ref" ]]; then
  _old_roster_ref="$(tr -d '[:space:]' < "$NEXUS/.roster_ref" || true)"
fi
printf '%s\n' "${_old_roster_ref:-main}" > "$NEXUS_NEW/.roster_ref"

# ─── Atomic swap ─────────────────────────────────────────────────────────
say "Swapping nexus.new into place"
_prev_ver=""
if [[ -f "$NEXUS/VERSION" ]]; then
  _prev_ver="$(tr -d '[:space:]' < "$NEXUS/VERSION")"
else
  _prev_ver="$CURRENT_VERSION"
fi

nexus_atomic_swap "$NEXUS_NEW" "$NEXUS_PREV"

# ─── Terminal summary ───────────────────────────────────────────────────────
# The outcome rides on EVERY path that completes an upgrade — this is what
# makes the NO NEW SILENT SUCCESS invariant satisfiable rather than
# aspirational (one grep: "integrity: verified" vs "integrity: UNVERIFIED").
# INTEGRITY_TOKEN is set on every branch above (tag: verified /
# verified:local-only / UNVERIFIED - <token>; non-tag: UNVERIFIED - non-tag ref).
echo ""
ok "Upgraded nexus $_prev_ver -> $TARGET_VERSION (integrity: ${INTEGRITY_TOKEN:-UNVERIFIED - unknown})"
if [[ -d "$NEXUS_PREV" ]]; then
  echo "  Previous nexus preserved at $NEXUS_PREV" >&2
  echo "  To roll back: eidolons upgrade self --rollback" >&2
fi
exit 0
