#!/usr/bin/env bash
# cli/src/nexus.sh — eidolons nexus command family
#
# Usage:
#   eidolons nexus refresh [--quiet]
#   eidolons nexus channel [<ref>]
#   eidolons nexus status
#
# Subcommands:
#   refresh              Force a roster refresh now (path-restricted; skip-gated; non-fatal).
#   channel [<ref>]      Get or set the roster channel (.roster_ref sidecar).
#                        No arg: print current channel.
#                        With <ref>: write .roster_ref (main|stable|<tag>|<sha>|<branch>).
#   status               Read-only report: CLI version/ref + roster channel + freshness.
#
# Exit codes:
#   0  success
#   1  generic failure
#   2  usage error (empty / whitespace-only arg to channel set)
#
# All log output to stderr. Bash 3.2 compatible.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

usage() {
  cat <<EOF
eidolons nexus — inspect and control the nexus roster channel

Usage: eidolons nexus <subcommand> [options]

Subcommands:
  refresh [--quiet]     Force a roster data refresh now (path-restricted;
                        honors skip-guards; non-fatal when offline).
  channel [<ref>]       Get or set the roster channel.
                        No arg: print current channel.
                        <ref>: set to main, stable, <tag>, <sha>, or <branch>.
  status                Read-only report of CLI version, roster channel,
                        effective ref, and freshness verdict.

Skip guards:
  nexus refresh is a no-op when EIDOLONS_NEXUS is set (local checkout) or
  EIDOLONS_SKIP_REFRESH=1. channel get/set and status always function.

Examples:
  eidolons nexus channel            # show current channel
  eidolons nexus channel stable     # track latest release tag
  eidolons nexus channel main       # track main branch (default)
  eidolons nexus channel v1.16.0    # freeze to a specific tag
  eidolons nexus refresh            # force roster data update now
  eidolons nexus status             # show split CLI-pin vs roster-channel

Exit codes:
  0  success / informational   2  usage error (empty arg to channel set)
EOF
}

nexus_sub="${1:-}"
[ $# -gt 0 ] && shift

case "$nexus_sub" in
  refresh)
    # ─── nexus refresh ───────────────────────────────────────────────────
    # Force a roster refresh. Honors skip guards (EIDOLONS_NEXUS / EIDOLONS_SKIP_REFRESH).
    _quiet=false
    for _a in "$@"; do
      case "$_a" in --quiet|-q) _quiet=true ;; esac
    done

    if [[ -n "${EIDOLONS_NEXUS:-}" ]]; then
      [[ "$_quiet" == false ]] && say "nexus refresh: skipped (local checkout — EIDOLONS_NEXUS set)" >&2
      exit 0
    fi
    if [[ "${EIDOLONS_SKIP_REFRESH:-0}" == "1" ]]; then
      [[ "$_quiet" == false ]] && say "nexus refresh: skipped (EIDOLONS_SKIP_REFRESH=1)" >&2
      exit 0
    fi

    [[ "$_quiet" == false ]] && say "nexus refresh: refreshing roster data from channel $(nexus_roster_ref 2>/dev/null || echo main)" >&2
    nexus_refresh
    [[ "$_quiet" == false ]] && ok "nexus refresh: done" >&2
    exit 0
    ;;

  channel)
    # ─── nexus channel [<ref>] ────────────────────────────────────────────
    if [[ $# -eq 0 ]]; then
      # GET: print current channel.
      nexus_ensure_roster_ref 2>/dev/null || true
      nexus_roster_ref
      exit 0
    fi

    new_ref="${1:-}"
    # Reject empty or whitespace-only arg.
    trimmed_ref="$(printf '%s' "$new_ref" | tr -d '[:space:]')"
    if [[ -z "$trimmed_ref" ]]; then
      echo "Error: channel ref must not be empty." >&2
      echo "" >&2
      usage >&2
      exit 2
    fi

    # Ensure the sidecar is gitignored.
    nexus_ensure_roster_ref 2>/dev/null || true
    nexus_ensure_gitignore_sidecar ".roster_ref" 2>/dev/null || true

    # Read old value for the echo.
    old_ref="$(nexus_roster_ref 2>/dev/null || echo main)"

    # Atomic write: write to a temp file then mv into place.
    _roster_ref_tmp="$NEXUS/.roster_ref.tmp.$$"
    printf '%s\n' "$trimmed_ref" > "$_roster_ref_tmp"
    mv "$_roster_ref_tmp" "$NEXUS/.roster_ref"

    echo "roster channel: $old_ref -> $trimmed_ref"
    exit 0
    ;;

  status)
    # ─── nexus status ────────────────────────────────────────────────────
    # Read-only report. Always exits 0.

    # CLI section. Use read_nexus_version (guards a missing VERSION file via the
    # git-describe fallback) — a bare `< "$NEXUS/VERSION"` redirect leaks a raw
    # "No such file" shell error that tr's 2>/dev/null does not suppress.
    _cli_version="$(read_nexus_version 2>/dev/null || echo "0.0.0-dev")"
    _cli_ref="$(nexus_install_ref 2>/dev/null || echo unknown)"
    _cli_commit="$(cat "$NEXUS/.install_commit" 2>/dev/null || \
      git -C "$NEXUS" rev-parse --short HEAD 2>/dev/null || echo unknown)"

    # Roster section.
    nexus_ensure_roster_ref 2>/dev/null || true
    _channel="$(nexus_roster_ref 2>/dev/null || echo main)"

    # Resolve effective ref for "stable".
    _effective_ref="$_channel"
    if [[ "$_channel" == "stable" ]]; then
      _resolved_stable="$(nexus_latest_tag 2>/dev/null || true)"
      if [[ -n "$_resolved_stable" ]]; then
        _effective_ref="$_resolved_stable"
      else
        _effective_ref="stable (unresolvable — offline?)"
      fi
    fi

    # Determine cache HEAD of roster/index.yaml (best-effort).
    _cache_head="unknown"
    if [[ -d "$NEXUS/.git" ]]; then
      _cache_head="$(git -C "$NEXUS" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    fi

    # Upstream probe (skip when local-checkout / skip-refresh).
    _upstream="unreachable"
    _freshness="unknown (offline)"
    if [[ -z "${EIDOLONS_NEXUS:-}" && "${EIDOLONS_SKIP_REFRESH:-0}" != "1" && -d "$NEXUS/.git" ]]; then
      _repo="${EIDOLONS_REPO:-https://github.com/Rynaro/eidolons}"
      # Use ls-remote (lightweight) to probe the channel ref HEAD.
      _fetch_ref="$_effective_ref"
      _upstream_sha=""
      _upstream_sha="$(with_timeout 8 git ls-remote --refs "$_repo" "$_fetch_ref" 2>/dev/null \
        | awk '{print $1}' | head -1 || true)"
      if [[ -n "$_upstream_sha" ]]; then
        _upstream="${_upstream_sha:0:7}"
        # Compare with cache HEAD.
        _cache_full="$(git -C "$NEXUS" rev-parse HEAD 2>/dev/null || true)"
        if [[ "$_upstream_sha" == "$_cache_full" ]]; then
          _freshness="up-to-date"
        else
          _freshness="behind (run: eidolons nexus refresh)"
        fi
      else
        _upstream="unreachable"
        _freshness="unknown (offline)"
      fi
    else
      if [[ -n "${EIDOLONS_NEXUS:-}" ]]; then
        _freshness="skipped (local checkout)"
      elif [[ "${EIDOLONS_SKIP_REFRESH:-0}" == "1" ]]; then
        _freshness="skipped (EIDOLONS_SKIP_REFRESH=1)"
      fi
    fi

    echo ""
    echo "CLI"
    printf '  version:    %s\n' "$_cli_version"
    printf '  ref:        %s\n' "$_cli_ref"
    printf '  commit:     %s\n' "${_cli_commit:0:7}"
    echo ""
    echo "ROSTER"
    printf '  channel:    %s  (effective: %s)\n' "$_channel" "$_effective_ref"
    printf '  cache HEAD: %s\n' "$_cache_head"
    printf '  upstream:   %s\n' "$_upstream"
    printf '  freshness:  %s\n' "$_freshness"
    echo ""
    exit 0
    ;;

  -h|--help|help|"")
    usage
    exit 0
    ;;

  *)
    echo "Unknown nexus subcommand: $nexus_sub" >&2
    echo "" >&2
    usage >&2
    exit 2
    ;;
esac
