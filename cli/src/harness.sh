#!/usr/bin/env bash
# eidolons harness — manage the Junction harness (F7, P3 seamless adoption layer)
# ═══════════════════════════════════════════════════════════════════════════
#
# Subcommands:
#   install [<version>]   Bootstrap Junction into $EIDOLONS_HOME/cache/junction@<ver>/
#   up                    Verify harness is present; print version + path
#   verify [<args>...]    Pass-through to 'junction verify'; inherit exit code
#   uninstall [--yes]     Remove Junction cache dirs + .eidolons/harness/ marker
#
# Design notes:
#   - Bash 3.2 strict (macOS default). No bash-4 features.
#   - All log output goes to stderr (say/ok/info/warn/die). Stdout is reserved
#     for machine-readable output (e.g. 'up' prints the resolved binary path).
#   - Idempotent: install twice == no-op on second run.
#   - Junction is a harness, not an Eidolon. It does NOT appear in the roster.
#     Version resolution uses the GitHub Releases API (via gh) or falls back
#     to the $JUNCTION_VERSION env var or the string "latest".
#   - Install target: $EIDOLONS_HOME/cache/junction@<ver>/
#   - Marker file: ./.eidolons/harness/manifest.json (written by 'eidolons sync',
#     not by 'harness install' itself — the marker is a sync-layer concern per
#     Story S20b).
#   - 'up': in v0.1, this is a thin wrapper that prints version + path and
#     soft-warns on Docker daemon absence. The full "boot the Junction runtime"
#     semantics are a future APIVR-Δ-on-Junction concern (round 4+).

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

# ─── Constants ────────────────────────────────────────────────────────────────
JUNCTION_REPO="Rynaro/Junction"
JUNCTION_CACHE_PREFIX="junction@"
# Marker dir for the consumer project (sync writes manifest.json here).
HARNESS_MARKER_DIR="./.eidolons/harness"

usage() {
  cat <<EOF
eidolons harness — manage the Junction harness

Usage: eidolons harness <subcommand> [options]

Subcommands:
  install [<version>]   Install Junction into the Eidolons cache. Idempotent.
                        Defaults to \$JUNCTION_VERSION, then GitHub latest release,
                        then "latest". Accepts a semver tag (e.g. "0.1.0").
  up                    Verify Junction is installed; print version + cache path.
                        Soft-warns if Docker daemon is unreachable (round-4 posture).
  verify [<args>...]    Pass-through to 'junction verify'. Inherits exit code.
  uninstall [--yes]     Remove Junction cache dirs and the .eidolons/harness/
                        marker dir from cwd. Asks for confirmation unless --yes.

Options:
  -h, --help            Show this help

Environment:
  JUNCTION_VERSION      Pin the version to install (overrides GitHub release probe)
  EIDOLONS_HOME         Eidolons cache root (default: ~/.eidolons)

Notes:
  Junction is not an Eidolon and does not appear in the roster.
  'eidolons sync' writes .eidolons/harness/manifest.json when Junction is detected.

EOF
}

# ─── Version resolution ────────────────────────────────────────────────────
# _resolve_junction_version [requested]
# If requested is non-empty and not "latest", echo it and return.
# Otherwise try: $JUNCTION_VERSION env var → gh API probe → "latest".
# Always echoes a non-empty string. Never calls die.
_resolve_junction_version() {
  local requested="${1:-}"

  # Explicit non-"latest" request wins unconditionally.
  if [[ -n "$requested" && "$requested" != "latest" ]]; then
    echo "$requested"
    return 0
  fi

  # Environment override.
  if [[ -n "${JUNCTION_VERSION:-}" && "${JUNCTION_VERSION}" != "latest" ]]; then
    echo "$JUNCTION_VERSION"
    return 0
  fi

  # GitHub Releases API probe via gh (if available).
  if command -v gh >/dev/null 2>&1; then
    local tag
    tag="$(gh api "repos/${JUNCTION_REPO}/releases/latest" --jq '.tag_name' 2>/dev/null || true)"
    if [[ -n "$tag" ]]; then
      # Strip leading 'v' to normalise to semver (e.g. v0.1.0 → 0.1.0).
      echo "${tag#v}"
      return 0
    fi
  fi

  # Last resort: the literal string "latest".
  echo "latest"
}

# ─── Cache path helpers ───────────────────────────────────────────────────
# _junction_cache_dir VERSION → absolute path $CACHE_DIR/junction@VERSION
_junction_cache_dir() {
  local version="$1"
  echo "${CACHE_DIR}/${JUNCTION_CACHE_PREFIX}${version}"
}

# _find_any_junction_cache → echoes the first junction@* dir found, or empty string
_find_any_junction_cache() {
  local dir
  # Bash 3.2 safe: use a loop + glob expansion instead of mapfile.
  for dir in "${CACHE_DIR}/${JUNCTION_CACHE_PREFIX}"*/; do
    if [[ -d "$dir" ]]; then
      # Strip trailing slash.
      echo "${dir%/}"
      return 0
    fi
  done
  return 0
}

# _junction_binary CACHE_DIR → path to the junction binary, or empty
_junction_binary() {
  local cdir="$1"
  if [[ -x "$cdir/junction" ]]; then
    echo "$cdir/junction"
  elif [[ -x "$cdir/bin/junction" ]]; then
    echo "$cdir/bin/junction"
  fi
}

# _junction_version_from_cache CACHE_DIR → version string (from dir name or binary)
_junction_version_from_cache() {
  local cdir="$1"
  local base
  base="$(basename "$cdir")"
  # Dir is named junction@<version>; strip the prefix.
  echo "${base#${JUNCTION_CACHE_PREFIX}}"
}

# ─── Subcommand: install ───────────────────────────────────────────────────
# _harness_install [<version>]
# Fetches Junction from GitHub Releases into $CACHE_DIR/junction@<ver>/.
# Idempotent: a second run with the same version is a no-op.
# A different version triggers a fresh fetch alongside the existing one
# (does not remove the previous version — that's uninstall's job).
_harness_install() {
  local requested="${1:-}"
  local version
  version="$(_resolve_junction_version "$requested")"

  local cache_dir
  cache_dir="$(_junction_cache_dir "$version")"

  # Idempotency gate: cache dir already exists → nothing to do.
  if [[ -d "$cache_dir" ]]; then
    local bin
    bin="$(_junction_binary "$cache_dir")"
    if [[ -n "$bin" ]]; then
      ok "Junction already installed at $version ($bin)"
      return 0
    fi
    # Dir exists but binary is absent — treat as incomplete, re-fetch.
    warn "Cache dir exists but junction binary absent; re-fetching."
    rm -rf "$cache_dir"
  fi

  # Validate: if version is still "latest" we can't form a useful tag.
  # Proceed but warn — the tarball download will use the real latest tag.
  if [[ "$version" == "latest" ]]; then
    warn "Junction version could not be resolved; installing as 'latest'."
    warn "Set \$JUNCTION_VERSION or install gh (https://cli.github.com) for pinned installs."
  fi

  say "Installing Junction@${version} into ${cache_dir}"
  mkdir -p "$cache_dir"

  # Build the tarball URL.  Junction releases use the pattern:
  #   github.com/Rynaro/Junction/releases/download/v<ver>/junction_<ver>_<os>_<arch>.tar.gz
  # For bootstrap we use Junction's own install.sh (curl | bash pattern,
  # mirrors how the nexus itself is bootstrapped).
  #
  # The install.sh is passed JUNCTION_VERSION and JUNCTION_INSTALL_DIR so it
  # deposits the binary where we want it.
  local install_url="https://raw.githubusercontent.com/${JUNCTION_REPO}/main/install.sh"
  local ver_tag="$version"
  [[ "$ver_tag" == "latest" ]] || ver_tag="v${version}"

  # Check whether curl or wget is available.
  if command -v curl >/dev/null 2>&1; then
    JUNCTION_INSTALL_DIR="$cache_dir" JUNCTION_VERSION="$version" \
      bash <(curl -fsSL "$install_url") >/dev/null 2>&1 \
      || {
        rm -rf "$cache_dir"
        die "Failed to install Junction@${version}. Check network access and the version string."
      }
  elif command -v wget >/dev/null 2>&1; then
    JUNCTION_INSTALL_DIR="$cache_dir" JUNCTION_VERSION="$version" \
      bash <(wget -qO- "$install_url") >/dev/null 2>&1 \
      || {
        rm -rf "$cache_dir"
        die "Failed to install Junction@${version}. Check network access and the version string."
      }
  else
    die "Neither curl nor wget found. Install one to bootstrap Junction."
  fi

  # Verify the binary landed.
  local bin
  bin="$(_junction_binary "$cache_dir")"
  if [[ -z "$bin" ]]; then
    rm -rf "$cache_dir"
    die "Junction install completed but binary not found in $cache_dir"
  fi

  ok "Junction@${version} installed at ${bin}"
}

# ─── Subcommand: up ───────────────────────────────────────────────────────
# _harness_up
# Confirms Junction is installed; prints version + binary path to stdout.
# Soft-warns (not fails) on Docker daemon absence (round-4 posture per spec §7.2).
# NOTE (v0.1): This is a thin presence+health wrapper. The full "boot the
# Junction runtime" semantics are deferred to a future round (APIVR-Δ-on-Junction).
_harness_up() {
  local any_cache
  any_cache="$(_find_any_junction_cache)"

  if [[ -z "$any_cache" ]]; then
    warn "Junction is not installed. Run: eidolons harness install"
    return 1
  fi

  local ver bin
  ver="$(_junction_version_from_cache "$any_cache")"
  bin="$(_junction_binary "$any_cache")"

  if [[ -z "$bin" ]]; then
    warn "Junction cache found at $any_cache but binary is absent."
    warn "Run: eidolons harness install"
    return 1
  fi

  info "Junction version : $ver"
  info "Junction binary  : $bin"

  # Docker daemon soft-warn (round-4 posture; non-fatal per spec §7.2).
  if command -v docker >/dev/null 2>&1; then
    if ! docker info >/dev/null 2>&1; then
      warn "Docker daemon unreachable. Junction's container executor will not function."
      warn "Start Docker or use 'junction --no-container' when running plans."
    else
      info "Docker daemon    : reachable"
    fi
  else
    warn "Docker not found. Junction's container executor will not function."
    warn "Install Docker or use 'junction --no-container' when running plans."
  fi

  # Machine-readable: echo binary path to stdout for scripted callers.
  echo "$bin"
  ok "Junction harness is up"
}

# ─── Subcommand: verify ───────────────────────────────────────────────────
# _harness_verify [<args>...]
# Pass-through to 'junction verify'. Inherits exit code verbatim.
# If junction is not installed, emits a clear error.
_harness_verify() {
  local any_cache bin
  any_cache="$(_find_any_junction_cache)"
  if [[ -z "$any_cache" ]]; then
    die "Junction is not installed. Run: eidolons harness install"
  fi
  bin="$(_junction_binary "$any_cache")"
  if [[ -z "$bin" ]]; then
    die "Junction binary not found in $any_cache. Run: eidolons harness install"
  fi
  # Pass-through: stdout and exit code go directly to the caller.
  exec "$bin" verify "$@"
}

# ─── Subcommand: uninstall ────────────────────────────────────────────────
# _harness_uninstall [--yes]
# Removes all $CACHE_DIR/junction@*/ directories and the Junction marker
# (./.eidolons/harness/manifest.json). Preserves harness hook shims (hooks/) and
# the memory cache (cache/) that share the dir; the dir is reclaimed only if left
# empty. Idempotent: second run is a no-op. Asks for confirmation unless --yes.
_harness_uninstall() {
  local yes=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y) yes=true; shift ;;
      *)        echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done

  # Collect what would be removed.
  local found_cache found_marker removed_any
  found_cache=false
  found_marker=false
  removed_any=false

  local dir
  for dir in "${CACHE_DIR}/${JUNCTION_CACHE_PREFIX}"*/; do
    if [[ -d "$dir" ]]; then
      found_cache=true
    fi
  done
  # Detect the Junction *marker* by its manifest file, not the parent dir:
  # .eidolons/harness/ is shared with harness hook shims (hooks/) and the memory
  # preflight cache (cache/), which this uninstall must not touch.
  if [[ -f "$HARNESS_MARKER_DIR/manifest.json" ]]; then
    found_marker=true
  fi

  if [[ "$found_cache" == "false" && "$found_marker" == "false" ]]; then
    ok "Junction is not installed (nothing to remove)"
    return 0
  fi

  # Confirmation prompt (skipped by --yes).
  if [[ "$yes" != "true" ]]; then
    say "About to remove:"
    if [[ "$found_cache" == "true" ]]; then
      for dir in "${CACHE_DIR}/${JUNCTION_CACHE_PREFIX}"*/; do
        [[ -d "$dir" ]] && echo "  - ${dir%/}" >&2
      done
    fi
    if [[ "$found_marker" == "true" ]]; then
      echo "  - $HARNESS_MARKER_DIR/manifest.json" >&2
    fi
    printf "Proceed? [y/N] " >&2
    local ans
    read -r ans || ans=""
    case "$ans" in
      [Yy]|[Yy][Ee][Ss]) : ;;
      *) die "Uninstall aborted." ;;
    esac
  fi

  # Remove cache dirs.
  for dir in "${CACHE_DIR}/${JUNCTION_CACHE_PREFIX}"*/; do
    if [[ -d "$dir" ]]; then
      rm -rf "${dir%/}"
      info "Removed cache: ${dir%/}"
      removed_any=true
    fi
  done

  # Remove the Junction marker ONLY (manifest.json), preserving any harness
  # hook shims / memory cache that share the dir. Reclaims the dir if empty.
  if [[ -f "$HARNESS_MARKER_DIR/manifest.json" ]]; then
    remove_junction_marker "$HARNESS_MARKER_DIR"
    info "Removed marker: $HARNESS_MARKER_DIR/manifest.json"
    removed_any=true
  fi

  if [[ "$removed_any" == "true" ]]; then
    ok "Junction harness uninstalled"
  else
    ok "Nothing to remove (already clean)"
  fi
}

# ─── Dispatch ─────────────────────────────────────────────────────────────
subcmd="${1:-}"
[[ $# -gt 0 ]] && shift

case "$subcmd" in
  install)   _harness_install "${1:-}" ;;
  up)        _harness_up ;;
  verify)    _harness_verify "$@" ;;
  uninstall) _harness_uninstall "$@" ;;
  -h|--help|help) usage; exit 0 ;;
  "")
    echo "Usage: eidolons harness <subcommand> [options]" >&2
    echo "" >&2
    echo "Available subcommands: install, up, verify, uninstall" >&2
    echo "Run 'eidolons harness --help' for full usage." >&2
    exit 2
    ;;
  *)
    echo "Unknown harness subcommand: $subcmd" >&2
    echo "" >&2
    echo "Available subcommands: install, up, verify, uninstall" >&2
    exit 2
    ;;
esac
