#!/usr/bin/env bash
#
# cli/src/lib.sh — shared helpers for eidolons subcommands.
# Source at the top of any subcommand script: . "$(dirname "$0")/lib.sh"
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Re-derive EIDOLONS_HOME + NEXUS from environment or script location.
EIDOLONS_HOME="${EIDOLONS_HOME:-$HOME/.eidolons}"
NEXUS="${EIDOLONS_NEXUS:-$EIDOLONS_HOME/nexus}"
CACHE_DIR="$EIDOLONS_HOME/cache"
ROSTER_FILE="$NEXUS/roster/index.yaml"

mkdir -p "$CACHE_DIR"

# ─── UI layer (theme + panels) ─────────────────────────────────────────────
# theme.sh detects fancy vs plain mode and exports color vars (BOLD, DIM,
# GREEN, YELLOW, RED, BLUE, CYAN, AMBER, MUTED, RESET) plus role aliases
# (UI_PRIMARY, UI_SUCCESS, UI_INFO, UI_WARN, UI_ERROR, UI_ACCENT,
# UI_MUTED). Plain mode → all empty strings, identical to the historical
# behaviour every test asserts on. panel.sh adds ui_banner / ui_section /
# ui_divider / ui_kv on top.
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui/theme.sh"
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui/panel.sh"

# ─── Verbosity tier ──────────────────────────────────────────────────────
# VERBOSITY=quiet|default|verbose. Resolution:
#   EIDOLONS_QUIET=1   → quiet      (env override applies everywhere)
#   EIDOLONS_VERBOSE=1 → verbose    (env override applies everywhere)
#   otherwise          → verbose    (legacy behaviour for non-init commands)
#
# init.sh and sync.sh override the default to "default" — the curated
# stage-banner + ACQUIRED-card UX. Other commands (verify, doctor,
# upgrade, release, mcp, etc.) inherit "verbose" so their say/info
# progress lines stay visible.
#
# Tier behaviour (consumed by say/info/ok below):
#   quiet   — only warn/die and explicit ui_* cards print.
#   default — say/info suppressed; ok prints; ui_section banners + cards drive output.
#   verbose — say/info/ok all print (legacy behaviour, plus new cards in init/sync).
#
# VERBOSITY is exported so subshells (e.g. the exec'd sync.sh) inherit it.
if [[ -z "${VERBOSITY:-}" ]]; then
  if [[ "${EIDOLONS_QUIET:-0}" == "1" ]]; then
    VERBOSITY="quiet"
  elif [[ "${EIDOLONS_VERBOSE:-0}" == "1" ]]; then
    VERBOSITY="verbose"
  else
    VERBOSITY="verbose"
  fi
fi
export VERBOSITY

# ─── Logging ───────────────────────────────────────────────────────────────
# All log output goes to stderr so functions whose stdout is captured by
# the caller (e.g. fetch_eidolon, roster_preset_members) can emit progress
# without corrupting their return value.
#
# Icon glyphs (▸✓·⚠✗) are pinned by tests — keep them as-is. Colors are
# now sourced from theme.sh role aliases instead of raw ANSI vars, so a
# theme swap automatically restyles all logs.
#
# Verbosity gates:
#   say  — suppressed under quiet and default (stage banners replace these).
#   info — suppressed under quiet and default; prints under verbose only.
#   ok   — prints under default and verbose; suppressed under quiet.
#   warn / die — always print regardless of tier.
#
# Note: ok continues to print at default tier so non-init commands
# (verify, doctor, upgrade) retain their success summaries. sync.sh
# replaces its per-member ok lines with ui_acquire_card directly.
say() {
  [[ "${VERBOSITY:-default}" == "verbose" ]] || return 0
  printf "%s%s%s %s\n" "${BOLD}" "${GLYPH_PROGRESS}" "${RESET}" "$*" >&2
}
ok() {
  [[ "${VERBOSITY:-default}" == "quiet" ]] && return 0
  printf "%s%s%s %s\n" "${UI_SUCCESS}" "${GLYPH_OK}" "${RESET}" "$*" >&2
}
info() {
  [[ "${VERBOSITY:-default}" == "verbose" ]] || return 0
  printf "%s%s%s %s\n" "${UI_INFO}" "${GLYPH_INFO}" "${RESET}" "$*" >&2
}
warn()  { printf "%s%s%s %s\n" "${UI_WARN}"  "${GLYPH_WARN}"  "${RESET}" "$*" >&2; }
die()   { printf "%s%s%s %s\n" "${UI_ERROR}" "${GLYPH_ERROR}" "${RESET}" "$*" >&2; exit 1; }

# ─── YAML → JSON ──────────────────────────────────────────────────────────
# Preferred: yq (mikefarah/yq or kislyuk/yq). Fallback: python3. Last resort: die.
yaml_to_json() {
  local file="$1"
  if command -v yq >/dev/null 2>&1; then
    # Handle both mikefarah/yq (Go) and kislyuk/yq (Python wrapper)
    if yq --version 2>&1 | grep -qi "mikefarah"; then
      yq -o=json eval '.' "$file"
    else
      yq . "$file"
    fi
  elif command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    python3 -c "import sys, json, yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" "$file"
  else
    die "Cannot parse YAML: neither yq nor python3+PyYAML is available.
  Fix (recommended): rerun the bootstrap installer to auto-install yq:
      curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
  Or install yq manually: https://github.com/mikefarah/yq/releases
  Or install PyYAML:      pip install --user pyyaml"
  fi
}

# ─── Roster queries ───────────────────────────────────────────────────────
# roster_list_names        → names, one per line
# roster_get NAME          → JSON object for that Eidolon (or exits 1)
# roster_preset_members P  → preset members, one per line
roster_list_names() {
  yaml_to_json "$ROSTER_FILE" | jq -r '.eidolons[].name'
}
roster_get() {
  local name="$1"
  local result
  result="$(yaml_to_json "$ROSTER_FILE" \
    | jq --arg n "$name" '.eidolons[] | select(.name == $n or ((.aliases // []) | index($n) != null))')"
  if [[ -z "$result" || "$result" == "null" ]]; then
    die "Eidolon '$name' not found in roster. Try: eidolons list"
  fi
  echo "$result"
}
roster_preset_members() {
  local preset="$1"
  yaml_to_json "$ROSTER_FILE" \
    | jq -r --arg p "$preset" '.presets[$p].members[]?' \
    | grep -v '^$' \
    || die "Preset '$preset' not found. Try: eidolons list --presets"
}
roster_presets() {
  yaml_to_json "$ROSTER_FILE" | jq -r '.presets | keys[]'
}

# ─── Release integrity ───────────────────────────────────────────────────
# The roster may include TUF-style target metadata under
# .versions.releases[VERSION]. Existing entries without metadata stay
# installable in compatibility mode, but entries that opt in must verify.

sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    die "Need shasum or sha256sum for release integrity verification"
  fi
}

integrity_enforcement_mode() {
  if [[ -n "${EIDOLONS_INTEGRITY_ENFORCEMENT:-}" ]]; then
    echo "$EIDOLONS_INTEGRITY_ENFORCEMENT"
    return
  fi
  yaml_to_json "$ROSTER_FILE" 2>/dev/null \
    | jq -r '.integrity.enforcement // "warn"' 2>/dev/null \
    || echo "warn"
}

semver_tag_for() {
  local version="$1"
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
    echo "v$version"
    return 0
  fi
  return 1
}

release_metadata_for() {
  local name="$1" version="$2"
  roster_get "$name" \
    | jq --arg v "$version" '.versions.releases[$v] // empty'
}

release_integrity_status() {
  local name="$1" version="$2" meta
  meta="$(release_metadata_for "$name" "$version" 2>/dev/null || true)"
  if [[ -n "$meta" && "$meta" != "null" ]]; then
    echo "verified"
    return
  fi
  if [[ "$(integrity_enforcement_mode)" == "strict" ]]; then
    echo "missing"
  else
    echo "legacy-warning"
  fi
}

git_archive_sha256() {
  # The release template (eidolon-release-template.yml) generates the
  # source archive with:
  #   git archive --format=tar --prefix="${GITHUB_REPOSITORY#*/}-$version/" HEAD
  # The prefix changes every byte of the tar (every entry's path is
  # prepended with it), so the consumer-side hash MUST use the same
  # prefix or every comparison will be a false mismatch.
  #
  # Args: dir [prefix]
  #   dir    — git working tree to archive
  #   prefix — optional tar entry prefix (e.g. "ATLAS-1.2.2/"). If
  #            omitted, archive without prefix (legacy callers).
  local dir="$1" prefix="${2:-}" tmp sum
  tmp="$(mktemp)"
  if [[ -n "$prefix" ]]; then
    if ! git -C "$dir" archive --format=tar --prefix="$prefix" HEAD > "$tmp" 2>/dev/null; then
      rm -f "$tmp"; return 1
    fi
  else
    if ! git -C "$dir" archive --format=tar HEAD > "$tmp" 2>/dev/null; then
      rm -f "$tmp"; return 1
    fi
  fi
  sum="$(sha256_file "$tmp")"
  rm -f "$tmp"
  echo "$sum"
}

# Derive the canonical archive prefix from a roster source.repo and
# release version. Mirrors the release template's
# `${GITHUB_REPOSITORY#*/}-$version/` convention.
release_archive_prefix() {
  local source_repo="$1" version="$2"
  echo "${source_repo#*/}-${version}/"
}

# _verify_release_integrity_internal NAME VERSION CLONE_DIR
# Internal variant that returns codes instead of calling die on cache drift.
# Return codes:
#   0  — verified (all checks pass)
#   2  — cache-stale (commit/tree/archive mismatch; clone is intact but wrong)
#   3  — cache-corrupt (HEAD unresolvable; git plumbing failed)
# Exits 1 (via die) only for invariant violations that are not cache drift:
#   - no release metadata under strict mode
#   - non-SemVer version
#   - metadata tag != expected tag (roster configuration error)
# All log output goes to stderr. No stdout output.
_verify_release_integrity_internal() {
  local name="$1" version="$2" clone_dir="$3"
  local meta mode expected_tag expected_commit expected_tree expected_archive
  local actual_tag actual_commit actual_tree actual_archive

  # Always check HEAD resolvability first, regardless of roster metadata.
  # A corrupt or partial clone (rc=3) always needs re-cloning, even in compat
  # mode where we cannot compare commits. This catches F2 (interrupted clone)
  # and F3 (corrupt .git) before the metadata gate.
  actual_commit="$(git -C "$clone_dir" rev-parse HEAD 2>/dev/null || echo "")"
  if [[ -z "$actual_commit" ]]; then
    warn "$name@$version cannot resolve cloned commit (corrupt or incomplete clone)"
    return 3
  fi

  meta="$(release_metadata_for "$name" "$version" 2>/dev/null || true)"
  if [[ -z "$meta" || "$meta" == "null" ]]; then
    mode="$(integrity_enforcement_mode)"
    if [[ "$mode" == "strict" ]]; then
      die "$name@$version has no roster release integrity metadata"
    fi
    warn "$name@$version has no roster release integrity metadata; compatibility install is warning-only"
    return 0
  fi

  expected_tag="$(echo "$meta" | jq -r --arg v "$version" '.tag // ("v" + $v)')"
  expected_commit="$(echo "$meta" | jq -r '.commit // empty')"
  expected_tree="$(echo "$meta" | jq -r '.tree // empty')"
  expected_archive="$(echo "$meta" | jq -r '.archive_sha256 // empty')"

  if ! semver_tag_for "$version" >/dev/null; then
    die "$name@$version is not a SemVer release (expected X.Y.Z)"
  fi
  if [[ "$expected_tag" != "v$version" ]]; then
    die "$name@$version roster metadata points at tag $expected_tag, expected v$version"
  fi

  actual_tag="$(git -C "$clone_dir" describe --tags --exact-match HEAD 2>/dev/null || true)"
  if [[ -n "$actual_tag" && "$actual_tag" != "$expected_tag" ]]; then
    warn "$name@$version tag drift: clone is $actual_tag but roster expects $expected_tag"
    return 2
  fi

  # actual_commit already resolved above.
  if [[ -n "$expected_commit" && "$actual_commit" != "$expected_commit" ]]; then
    warn "$name@$version commit mismatch: got $actual_commit, expected $expected_commit"
    return 2
  fi

  actual_tree="$(git -C "$clone_dir" rev-parse 'HEAD^{tree}' 2>/dev/null || echo "")"
  if [[ -n "$expected_tree" && "$actual_tree" != "$expected_tree" ]]; then
    warn "$name@$version tree mismatch: got ${actual_tree:-unknown}, expected $expected_tree"
    return 2
  fi

  if [[ -n "$expected_archive" ]]; then
    local source_repo prefix
    source_repo="$(roster_get "$name" | jq -r '.source.repo // empty')"
    [[ -n "$source_repo" ]] || die "$name@$version cannot resolve source.repo for archive verification"
    prefix="$(release_archive_prefix "$source_repo" "$version")"
    actual_archive="$(git_archive_sha256 "$clone_dir" "$prefix" || echo "")"
    [[ -n "$actual_archive" ]] || die "$name@$version cannot compute release archive checksum"
    if [[ "$actual_archive" != "$expected_archive" ]]; then
      warn "$name@$version archive checksum mismatch: got $actual_archive, expected $expected_archive"
      return 2
    fi
  fi

  ok "$name@$version release integrity verified"
  return 0
}

# verify_release_integrity NAME VERSION CLONE_DIR
# Public wrapper — calls die on any failure (cache drift or upstream truth mismatch).
# Used by callers that do not need the auto-recovery path.
verify_release_integrity() {
  local name="$1" version="$2" clone_dir="$3"
  local _vri_rc=0
  _verify_release_integrity_internal "$name" "$version" "$clone_dir" || _vri_rc=$?
  case "$_vri_rc" in
    0) return 0 ;;
    2) die "$name@$version integrity check failed (commit/tree/archive mismatch)" ;;
    3) die "$name@$version integrity check failed (cannot resolve HEAD — clone may be corrupt)" ;;
    *) die "$name@$version integrity check failed (rc=$_vri_rc)" ;;
  esac
}

# cache_invalidate NAME VERSION
# Removes the cache directory for NAME@VERSION. Idempotent. Bash 3.2 safe.
# Defensively pins the prefix to $CACHE_DIR/ to avoid rm -rf on arbitrary paths.
cache_invalidate() {
  local name="$1" version="$2"
  local target="$CACHE_DIR/${name}@${version}"
  # Safety: must start with the known cache dir prefix.
  case "$target" in
    "$CACHE_DIR/"*) : ;;
    *) warn "cache_invalidate: refusing to remove path outside CACHE_DIR: $target"; return 1 ;;
  esac
  if [[ -d "$target" ]]; then
    rm -rf "$target"
    info "cache_invalidate: removed $target"
  fi
  return 0
}

# lock_manifest_sha256 hashes the per-Eidolon install.manifest.json file (a
# single JSON file emitted by the upstream installer), not the tree of files
# under .eidolons/<name>/. See docs/release-integrity.md "Hash semantics" for
# the trade-off — manifest_sha256 is file-scoped so it stays stable across
# legitimate host-wiring variations; archive_sha256 covers tree-wide drift.
lock_manifest_sha256() {
  local manifest="$1"
  [[ -f "$manifest" ]] || return 1
  sha256_file "$manifest"
}

# ─── Host detection ───────────────────────────────────────────────────────
# Detect which hosts are in use in the current project (cwd).
# Emits: one host per line from {claude-code, copilot, cursor, opencode, codex}
#
# AGENTS.md / codex co-ownership truth table (T.3 of openai-codex-host-support):
#   .codex/  present                              → codex (definitive Codex-only signal)
#   AGENTS.md only (no .github/, no .codex/)      → codex (NOT copilot)
#   .github/ only (no AGENTS.md, no .codex/)      → copilot
#   AGENTS.md AND .github/ (no .codex/)           → BOTH copilot and codex
#   .codex/ AND .github/                          → BOTH codex and copilot
# Sources:
#   https://developers.openai.com/codex/guides/agents-md
#   https://developers.openai.com/codex/subagents
detect_hosts() {
  local hosts=()
  local has_agents_md=0 has_github=0 has_codex_dir=0

  [[ -f "AGENTS.md" ]] && has_agents_md=1
  [[ -d ".github"  ]] && has_github=1
  [[ -d ".codex"   ]] && has_codex_dir=1

  [[ -f "CLAUDE.md" || -d ".claude"      ]] && hosts+=("claude-code")

  # Codex / Copilot disambiguation. Order matters because tests check for
  # presence/absence of specific tokens; we keep emission order stable.
  if (( has_codex_dir == 1 )); then
    hosts+=("codex")
    if (( has_github == 1 )); then
      hosts+=("copilot")
    fi
  elif (( has_agents_md == 1 && has_github == 1 )); then
    hosts+=("copilot")
    hosts+=("codex")
  elif (( has_agents_md == 1 )); then
    hosts+=("codex")
  elif (( has_github == 1 )); then
    hosts+=("copilot")
  fi

  [[ -d ".cursor" || -f ".cursorrules"   ]] && hosts+=("cursor")
  [[ -d ".opencode"                      ]] && hosts+=("opencode")
  if (( ${#hosts[@]} > 0 )); then
    printf "%s\n" "${hosts[@]}"
  fi
  return 0
}

# ─── Eidolon repo fetching ────────────────────────────────────────────────
# fetch_eidolon NAME VERSION → echoes path to cached clone
#
# Auto-recovery flow:
#   1. If clone dir has no .git → fresh clone (unchanged path).
#   2. If .git exists → run internal integrity check (returns code 0/2/3).
#      rc=0 → cache is valid; log and return path.
#      rc∈{2,3} → log stale/corrupt status, invalidate cache, re-clone once,
#                 then call verify_release_integrity (the die-on-failure variant).
#                 If THAT fails, die with an "upstream-truth mismatch" message.
# Stdout is the cache path only. All log output via info/warn/say (stderr).
fetch_eidolon() {
  local name="$1" version="${2:-latest}"
  local entry; entry="$(roster_get "$name")"
  local repo; repo="$(echo "$entry" | jq -r '.source.repo')"
  local ref meta_tag
  if [[ "$version" == "latest" ]]; then
    version="$(echo "$entry" | jq -r '.versions.latest')"
  fi
  meta_tag="$(echo "$entry" | jq -r --arg v "$version" '.versions.releases[$v].tag // empty')"
  if [[ -n "$meta_tag" ]]; then
    ref="$meta_tag"
  else
    ref="v$version"
  fi

  local clone_dir="$CACHE_DIR/${name}@${version}"
  if [[ ! -d "$clone_dir/.git" ]]; then
    say "Fetching $name@$version from github.com/$repo"
    git clone --depth 1 --branch "$ref" "https://github.com/$repo" "$clone_dir" >/dev/null 2>&1 \
      || die "Failed to clone github.com/$repo at $ref"
    verify_release_integrity "$name" "$version" "$clone_dir"
  else
    # Cache exists — run internal check to detect stale or corrupt state.
    local _fe_rc=0
    _verify_release_integrity_internal "$name" "$version" "$clone_dir" || _fe_rc=$?
    if [[ "$_fe_rc" -eq 0 ]]; then
      info "Using cached $name@$version"
    else
      # Cache is stale (rc=2) or corrupt (rc=3) — invalidate and re-clone once.
      local _status_label="stale"
      [[ "$_fe_rc" -eq 3 ]] && _status_label="corrupt"
      warn "$name@$version cache invalid (${_status_label}); re-cloning from github.com/$repo"
      cache_invalidate "$name" "$version"
      say "Fetching $name@$version from github.com/$repo"
      git clone --depth 1 --branch "$ref" "https://github.com/$repo" "$clone_dir" >/dev/null 2>&1 \
        || die "Failed to clone github.com/$repo at $ref after cache invalidation"
      # Re-verify after fresh clone. If this fails it is an upstream-truth mismatch — fatal.
      local _fe_rc2=0
      _verify_release_integrity_internal "$name" "$version" "$clone_dir" || _fe_rc2=$?
      if [[ "$_fe_rc2" -ne 0 ]]; then
        die "$name@$version commit mismatch persists after cache re-clone — upstream tag at github.com/$repo may have been force-moved. Investigate roster vs. upstream attestation."
      fi
    fi
  fi
  echo "$clone_dir"
}

# ─── EIIS conformance check ───────────────────────────────────────────────
# Delegates to the standalone checker at Rynaro/eidolons-eiis when reachable,
# falls back to the inline file-existence check when offline.

# eiis_required_version → reads `eiis_required` from roster/index.yaml
eiis_required_version() {
  local roster="$NEXUS/roster/index.yaml"
  [[ -f "$roster" ]] || { echo "1.1"; return; }
  yaml_to_json "$roster" 2>/dev/null | jq -r '.eiis_required // "1.1"'
}

# resolve_eiis_tag REQ → echoes the tag to clone (e.g. "1.1" → "1.1.4")
# `eiis_required` in the roster is a major.minor compat declaration; the
# actual EIIS repo tags are full SemVer (v1.0.0, v1.1.0, …). When REQ is
# already a full SemVer it round-trips unchanged.
resolve_eiis_tag() {
  local req="$1"
  if [[ "$req" =~ ^[0-9]+\.[0-9]+$ ]]; then
    local resolved
    resolved=$(git ls-remote --tags --refs https://github.com/Rynaro/eidolons-eiis 2>/dev/null \
      | awk -v p="refs/tags/v${req}." '$2 ~ "^"p { sub("refs/tags/v", "", $2); print $2 }' \
      | sort -V \
      | tail -1)
    [[ -n "$resolved" ]] && { echo "$resolved"; return; }
  fi
  echo "$req"
}

# fetch_eiis [VERSION] → echoes path to cached clone, or returns non-zero on failure
fetch_eiis() {
  local version="${1:-$(eiis_required_version)}"
  local resolved; resolved="$(resolve_eiis_tag "$version")"
  local clone_dir="$CACHE_DIR/eiis@${resolved}"
  if [[ ! -d "$clone_dir/.git" ]]; then
    mkdir -p "$CACHE_DIR"
    git clone --depth 1 --branch "v$resolved" \
      "https://github.com/Rynaro/eidolons-eiis" "$clone_dir" >/dev/null 2>&1 \
      || return 1
  fi
  echo "$clone_dir"
}

eiis_check() {
  local dir="$1"
  local name="$2"
  local checker_dir
  if checker_dir="$(fetch_eiis 2>/dev/null)" \
     && [[ -n "$checker_dir" && -x "$checker_dir/conformance/check.sh" ]]; then
    if bash "$checker_dir/conformance/check.sh" "$dir" >/dev/null 2>&1; then
      return 0
    fi
    warn "$name fails EIIS conformance"
    warn "  Re-run for details: bash $checker_dir/conformance/check.sh \"$dir\""
    return 1
  fi

  # Offline fallback — keep behaviour byte-compatible with v1.0 inline check.
  local required=( "AGENTS.md" "CLAUDE.md" "install.sh" "agent.md" "README.md" )
  local missing=()
  for f in "${required[@]}"; do
    [[ -f "$dir/$f" ]] || missing+=("$f")
  done
  if (( ${#missing[@]} > 0 )); then
    warn "$name is not fully EIIS-conformant (missing: ${missing[*]})"
    warn "  Continuing anyway. Run 'eidolons doctor' after install for full report."
    return 1
  fi
  return 0
}

# ─── Project manifest (eidolons.yaml) ─────────────────────────────────────
PROJECT_MANIFEST="eidolons.yaml"
PROJECT_LOCK="eidolons.lock"

manifest_exists() { [[ -f "$PROJECT_MANIFEST" ]]; }

# Read installed members from eidolons.yaml → one name per line
manifest_members() {
  [[ -f "$PROJECT_MANIFEST" ]] || return 0
  yaml_to_json "$PROJECT_MANIFEST" | jq -r '.members[].name // empty'
}

# ─── Bash 3.2-portable timeout wrapper ────────────────────────────────────
# with_timeout SECONDS CMD ARGS...
# Runs CMD with the given timeout. Returns CMD's exit code on completion,
# or 124 (GNU timeout convention) when the timer fires. macOS bash 3.2
# safe — no `wait -n`, no GNU-only `timeout` binary required.
#
# FD-hygiene note: the timer subshell forks a `sleep "$secs"`. If the main
# command completes first we kill the timer (SIGTERM) and pkill its sleep
# child explicitly. Without that, an orphaned sleep can keep bats' output
# pipe open and the entire test runner blocks until the timeout expires —
# observed as a ~10× slowdown in `bats cli/tests/release.bats` (S1/S10/S12
# pass `--release-timeout=600 --intake-timeout=300` defaults, so per-test
# orphan sleeps gated bats at 10+ minutes of wall while CPU was idle). The
# subshell also closes its inherited FDs 3-9 before forking sleep so the
# orphan never grabs bats' pipe in the first place — defence in depth.
with_timeout() {
  local secs="$1"; shift
  if [[ -z "${1:-}" ]]; then
    return 2
  fi
  "$@" &
  local pid=$!
  # Timer subshell:
  #   - stdin/stdout/stderr → /dev/null so the subshell does not hold an
  #     inherited command-substitution pipe open after the main command
  #     completes (the parent's $(with_timeout ...) capture would otherwise
  #     block until the timer fires regardless of the polled function
  #     returning early).
  #   - FDs 3..9 explicitly closed before exec, so an orphaned `sleep` does
  #     not inherit bats' output pipe (bats reaps a test by waiting for EOF
  #     on the read-end of that pipe; an orphan write-end blocks the reap).
  ( exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- 0</dev/null
    sleep "$secs" && kill -9 "$pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  local timer=$!
  local rc=0
  wait "$pid" 2>/dev/null || rc=$?
  # If the timer-killer is still alive, the command completed first; reap
  # both the timer subshell and any inner `sleep` it forked. The bare
  # `kill $timer` only SIGTERMs the subshell; the sleep child is reparented
  # to init and would keep running until $secs elapses. pkill -P targets
  # the timer's direct children (i.e. the sleep) so we don't leave a
  # process lying around for the duration of $RELEASE_TIMEOUT.
  if kill -0 "$timer" 2>/dev/null; then
    pkill -P "$timer" 2>/dev/null || true
    kill "$timer" 2>/dev/null || true
    wait "$timer" 2>/dev/null || true
  else
    # Timer fired — command was killed.
    wait "$timer" 2>/dev/null || true
    rc=124
  fi
  return "$rc"
}

# ─── Nexus version probes ─────────────────────────────────────────────────
# nexus_current_tag → echoes the exact-match tag at $NEXUS HEAD, or short SHA
#                     when not on a tag, or "unknown" when nexus has no .git.
nexus_current_tag() {
  if [[ ! -d "$NEXUS/.git" ]]; then
    echo "unknown"
    return 0
  fi
  local tag
  tag="$(git -C "$NEXUS" describe --tags --exact-match HEAD 2>/dev/null || true)"
  if [[ -n "$tag" ]]; then
    echo "$tag"
    return 0
  fi
  git -C "$NEXUS" rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

# nexus_current_commit → echoes the full SHA at HEAD, or "unknown".
nexus_current_commit() {
  if [[ ! -d "$NEXUS/.git" ]]; then
    echo "unknown"
    return 0
  fi
  git -C "$NEXUS" rev-parse HEAD 2>/dev/null || echo "unknown"
}

# nexus_latest_tag → highest vX.Y.Z tag from the nexus remote.
# Echoes the empty string + returns non-zero when the probe fails (offline,
# DNS error, timeout). 10-second cap via with_timeout.
nexus_latest_tag() {
  local repo="${EIDOLONS_REPO:-https://github.com/Rynaro/eidolons}"
  local tmp; tmp="$(mktemp)"
  if with_timeout 10 git ls-remote --tags --refs "$repo" >"$tmp" 2>/dev/null; then
    local latest
    latest="$(awk '$2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+$/ { sub("refs/tags/", "", $2); print $2 }' "$tmp" \
              | sort -V | tail -1)"
    rm -f "$tmp"
    if [[ -n "$latest" ]]; then
      echo "$latest"
      return 0
    fi
    return 1
  fi
  rm -f "$tmp"
  return 1
}

# nexus_self_update TAG → fetch + reset --hard FETCH_HEAD against TAG.
# Returns 0 on success, 1 on fetch failure (state untouched on failure).
nexus_self_update() {
  local tag="$1"
  local repo="${EIDOLONS_REPO:-https://github.com/Rynaro/eidolons}"
  [[ -d "$NEXUS/.git" ]] || return 1
  if ! git -C "$NEXUS" fetch --depth 1 origin "$tag" >/dev/null 2>&1; then
    return 1
  fi
  git -C "$NEXUS" reset --hard FETCH_HEAD >/dev/null 2>&1 || return 1
  return 0
}

# read_nexus_version → echoes the installed nexus version from $NEXUS/VERSION,
# falling back to `git describe` then to "0.0.0-dev".
read_nexus_version() {
  local vfile="$NEXUS/VERSION"
  if [[ -f "$vfile" ]]; then
    tr -d '[:space:]' < "$vfile"
    return 0
  fi
  local gdesc
  gdesc="$(git -C "$NEXUS" describe --tags --abbrev=0 2>/dev/null || true)"
  if [[ -n "$gdesc" ]]; then
    echo "${gdesc#v}"
    return 0
  fi
  echo "0.0.0-dev"
}

# nexus_install_date → ISO date from .install_date sidecar; falls back to "unknown".
nexus_install_date() {
  cat "$NEXUS/.install_date" 2>/dev/null || echo "unknown"
}

# nexus_install_ref → ref string from .install_ref sidecar; falls back to "unknown".
nexus_install_ref() {
  cat "$NEXUS/.install_ref" 2>/dev/null || echo "unknown"
}

# nexus_clone_to_sibling TAG DEST_DIR → shallow-clones the nexus remote at TAG
# into DEST_DIR. Returns 0 on success, 1 on failure. stdout is the dest dir.
# The actual swap is the caller's responsibility.
nexus_clone_to_sibling() {
  local tag="$1" dest="$2"
  local repo="${EIDOLONS_REPO:-https://github.com/Rynaro/eidolons}"
  rm -rf "$dest"
  if ! git clone --depth 1 --branch "$tag" "$repo" "$dest" >/dev/null 2>&1; then
    rm -rf "$dest"
    return 1
  fi
  echo "$dest"
  return 0
}

# nexus_atomic_swap NEW_DIR PREV_DIR → moves $NEXUS to $PREV_DIR then $NEW_DIR to $NEXUS.
# Verifies NEW_DIR contains cli/eidolons before starting. Pure renames — reversible.
nexus_atomic_swap() {
  local new_dir="$1" prev_dir="$2"
  if [[ ! -f "$new_dir/cli/eidolons" ]]; then
    warn "nexus_atomic_swap: $new_dir does not contain cli/eidolons — refusing"
    return 1
  fi
  if [[ -d "$prev_dir" ]]; then
    rm -rf "$prev_dir"
  fi
  mv "$NEXUS" "$prev_dir"
  mv "$new_dir" "$NEXUS"
  return 0
}

# nexus_rollback PREV_DIR FAILED_DIR → moves $NEXUS to $FAILED_DIR then $PREV_DIR to $NEXUS.
# Verifies PREV_DIR exists and contains cli/eidolons.
nexus_rollback() {
  local prev_dir="$1" failed_dir="$2"
  if [[ ! -d "$prev_dir" ]]; then
    warn "nexus_rollback: no previous nexus at $prev_dir"
    return 1
  fi
  if [[ ! -f "$prev_dir/cli/eidolons" ]]; then
    warn "nexus_rollback: $prev_dir does not contain cli/eidolons — refusing"
    return 1
  fi
  if [[ -d "$failed_dir" ]]; then
    rm -rf "$failed_dir"
  fi
  mv "$NEXUS" "$failed_dir"
  mv "$prev_dir" "$NEXUS"
  return 0
}

# nexus_verify_release VERSION CLONE_DIR → verifies the clone against
# roster/index.yaml nexus.versions.releases.<version>. Unlike
# _verify_release_integrity_internal (which reads from eidolons[]), this
# function reads from the top-level nexus: block.
# Return codes:
#   0 — verified (all checks pass, or metadata absent — skip with warning)
#   2 — mismatch (commit / tree / archive drift)
#   3 — corrupt clone (HEAD unresolvable)
nexus_verify_release() {
  local version="$1" clone_dir="$2"
  local actual_commit

  actual_commit="$(git -C "$clone_dir" rev-parse HEAD 2>/dev/null || echo "")"
  if [[ -z "$actual_commit" ]]; then
    warn "nexus@$version cannot resolve cloned commit"
    return 3
  fi

  # Read metadata from roster nexus.versions.releases.<version>
  local meta
  meta="$(yaml_to_json "$ROSTER_FILE" 2>/dev/null \
    | jq --arg v "$version" '.nexus.versions.releases[$v] // empty' 2>/dev/null || true)"

  if [[ -z "$meta" || "$meta" == "null" || "$meta" == "empty" ]]; then
    warn "nexus@$version has no release integrity metadata in roster — skipping verification"
    return 0
  fi

  # Check for placeholder values written at bootstrap time.
  local expected_commit expected_tree expected_archive
  expected_commit="$(echo "$meta" | jq -r '.commit // empty')"
  expected_tree="$(echo "$meta" | jq -r '.tree // empty')"
  expected_archive="$(echo "$meta" | jq -r '.archive_sha256 // empty')"

  # Skip verification when placeholders are present (bootstrap window).
  case "$expected_commit" in
    "<"*) warn "nexus@$version commit placeholder detected — skipping verification (bootstrap window)"; return 0 ;;
  esac

  if [[ -n "$expected_commit" && "$actual_commit" != "$expected_commit" ]]; then
    warn "nexus@$version commit mismatch: got $actual_commit, expected $expected_commit"
    return 2
  fi

  local actual_tree
  actual_tree="$(git -C "$clone_dir" rev-parse 'HEAD^{tree}' 2>/dev/null || echo "")"
  case "$expected_tree" in
    "<"*) : ;;  # placeholder
    "")  : ;;
    *)
      if [[ "$actual_tree" != "$expected_tree" ]]; then
        warn "nexus@$version tree mismatch: got ${actual_tree:-unknown}, expected $expected_tree"
        return 2
      fi
      ;;
  esac

  case "$expected_archive" in
    "<"*) : ;;  # placeholder
    "")  : ;;
    *)
      local prefix actual_archive
      prefix="eidolons-${version}/"
      actual_archive="$(git_archive_sha256 "$clone_dir" "$prefix" || echo "")"
      if [[ -z "$actual_archive" ]]; then
        warn "nexus@$version cannot compute archive checksum"
        return 2
      fi
      if [[ "$actual_archive" != "$expected_archive" ]]; then
        warn "nexus@$version archive checksum mismatch: got $actual_archive, expected $expected_archive"
        return 2
      fi
      ;;
  esac

  ok "nexus@$version release integrity verified"
  return 0
}

# ─── SemVer helpers (pure bash, no external deps) ─────────────────────────
# semver_lt A B → exit 0 when A < B (strict), exit 1 otherwise.
# Uses `sort -V` for the comparison; both args must be plain X.Y.Z (no prefix).
semver_lt() {
  local a="$1" b="$2"
  if [[ "$a" == "$b" ]]; then
    return 1
  fi
  local first
  first="$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)"
  if [[ "$first" == "$a" ]]; then
    return 0
  fi
  return 1
}

# semver_satisfies CONSTRAINT VERSION → exit 0 when VERSION satisfies CONSTRAINT.
# CONSTRAINT may be "^X.Y.Z", "~X.Y.Z", "=X.Y.Z" or bare "X.Y.Z".
# Caret/tilde follow npm/cargo SemVer conventions.
semver_satisfies() {
  local constraint="$1" version="$2"
  local op="" base="" cmajor cminor _cpatch vmajor vminor _vpatch
  case "$constraint" in
    ^*) op="^"; base="${constraint#^}" ;;
    ~*) op="~"; base="${constraint#~}" ;;
    =*) op="="; base="${constraint#=}" ;;
    *)  op="="; base="$constraint" ;;
  esac

  # Validate both as X.Y.Z. If either malformed, fall back to literal equality.
  case "$base" in
    [0-9]*.[0-9]*.[0-9]*) : ;;
    *) [[ "$base" == "$version" ]] && return 0 || return 1 ;;
  esac
  case "$version" in
    [0-9]*.[0-9]*.[0-9]*) : ;;
    *) return 1 ;;
  esac

  cmajor="${base%%.*}"
  cminor="${base#*.}"; cminor="${cminor%%.*}"
  _cpatch="${base##*.}"
  vmajor="${version%%.*}"
  vminor="${version#*.}"; vminor="${vminor%%.*}"
  _vpatch="${version##*.}"

  # version must be >= base
  if semver_lt "$version" "$base"; then
    return 1
  fi

  case "$op" in
    =)
      [[ "$version" == "$base" ]] && return 0 || return 1
      ;;
    ~)
      # >= base, < base.major.(base.minor + 1).0
      [[ "$vmajor" == "$cmajor" && "$vminor" == "$cminor" ]] && return 0 || return 1
      ;;
    ^)
      if [[ "$cmajor" == "0" ]]; then
        # ^0.Y.Z → >= base, < 0.(Y+1).0  (npm semantics)
        [[ "$vmajor" == "0" && "$vminor" == "$cminor" ]] && return 0 || return 1
      else
        # ^X.Y.Z → >= base, < (X+1).0.0
        [[ "$vmajor" == "$cmajor" ]] && return 0 || return 1
      fi
      ;;
  esac
  return 1
}

# ─── Marker-bounded block upsert ─────────────────────────────────────────
# upsert_marker_block DST MARKER_NAME CONTENT [PREFIX]
#
# Owns a marker-bounded region in a composable host-doc file (CLAUDE.md,
# AGENTS.md, .github/copilot-instructions.md). If the region already
# exists, rewrites its body in place. Otherwise appends a new block.
# The marker pattern is <!-- eidolon:<MARKER_NAME> start/end -->.
#
# Optional PREFIX is prepended to each marker line — used for file
# formats where the bare HTML comment is not a valid line (e.g.
# `.gitignore` needs `# ` so the marker is interpreted as a comment).
# When unset, the marker lines are emitted verbatim (legacy behaviour).
#
# All arguments must be plain strings (no embedded newlines in MARKER_NAME).
# Idempotent: calling twice with the same content leaves the file unchanged.
# Bash 3.2 safe — no associative arrays, no ${var,,}, no mapfile.
# All log output goes to stderr; stdout is clean for captured callers.
upsert_marker_block() {
  local dst="$1" marker_name="$2" content="$3" prefix="${4:-}"
  local start="${prefix}<!-- eidolon:${marker_name} start -->"
  local end="${prefix}<!-- eidolon:${marker_name} end -->"

  mkdir -p "$(dirname "$dst")" 2>/dev/null || true

  local content_file tmp mode
  content_file="$(mktemp)"
  printf '%s\n' "$content" > "$content_file"

  if [[ -f "$dst" ]] && grep -qF "$start" "$dst" 2>/dev/null; then
    mode="rewritten"
    tmp="$(mktemp)"
    awk -v start="$start" -v end="$end" -v cf="$content_file" '
      BEGIN { in_block = 0 }
      $0 == start {
        print start
        while ((getline line < cf) > 0) print line
        close(cf)
        in_block = 1
        next
      }
      $0 == end {
        print end
        in_block = 0
        next
      }
      !in_block { print }
    ' "$dst" > "$tmp"
    mv "$tmp" "$dst"
    chmod 0644 "$dst" 2>/dev/null || true
  elif [[ -f "$dst" ]]; then
    mode="appended"
    {
      printf '\n%s\n' "$start"
      cat "$content_file"
      printf '%s\n' "$end"
    } >> "$dst"
  else
    mode="created"
    {
      printf '%s\n' "$start"
      cat "$content_file"
      printf '%s\n' "$end"
    } > "$dst"
    chmod 0644 "$dst" 2>/dev/null || true
  fi

  rm -f "$content_file"
  info "  upsert_marker_block: $mode $marker_name block in $dst"
}

# remove_marker_block DST MARKER_NAME [PREFIX]
#
# Removes the marker-bounded block <!-- eidolon:<MARKER_NAME> start/end -->
# from DST. PREFIX is prepended to the marker lines for file formats
# that require comment-line wrapping (e.g. `.gitignore` uses `# `).
# No-ops when the marker is absent or DST does not exist.
# Idempotent. Bash 3.2 safe.
remove_marker_block() {
  local dst="$1" marker_name="$2" prefix="${3:-}"
  local start="${prefix}<!-- eidolon:${marker_name} start -->"
  local end="${prefix}<!-- eidolon:${marker_name} end -->"

  [[ -f "$dst" ]] || return 0
  grep -qF "$start" "$dst" 2>/dev/null || return 0

  local tmp
  tmp="$(mktemp)"
  awk -v start="$start" -v end="$end" '
    BEGIN { in_block = 0 }
    $0 == start { in_block = 1; next }
    $0 == end   { in_block = 0; next }
    !in_block   { print }
  ' "$dst" > "$tmp"
  mv "$tmp" "$dst"
  chmod 0644 "$dst" 2>/dev/null || true
  info "  remove_marker_block: removed $marker_name block from $dst"
}

# ─── Dispatch-pointer vendor docs (PR-A1 / B2 / R3) ─────────────────────
# Vendor → root file mapping for hosts.pointer_targets derivation.
# Canonical table — single source of truth. Used by _vendor_file_for_host
# and derive_pointer_targets_from_hosts.
#
# Host          Vendor file
# claude-code   CLAUDE.md
# codex         AGENTS.md
# copilot       .github/copilot-instructions.md
# gemini        GEMINI.md
# cursor        (none — tool-config dir, not an agent-instructions file)
# opencode      AGENTS.md (shares with codex; deduped by caller)
#
# DISPATCH_POINTER_VENDORS is REMOVED in v1.7.0; apply_dispatch_pointers
# now receives pointer_targets_csv as its first argument.

# _vendor_file_for_host HOST
#
# Echoes the canonical vendor file for a given host slug, or empty string
# when the host has no root vendor file (cursor). Bash 3.2 case-based.
_vendor_file_for_host() {
  case "$1" in
    claude-code) echo "CLAUDE.md" ;;
    codex)       echo "AGENTS.md" ;;
    copilot)     echo ".github/copilot-instructions.md" ;;
    gemini)      echo "GEMINI.md" ;;
    opencode)    echo "AGENTS.md" ;;
    cursor)      echo "" ;;
    *)           echo "" ;;
  esac
}

# derive_pointer_targets_from_hosts HOSTS_CSV
#
# Echoes a comma-separated, deduplicated list of vendor files derived from
# HOSTS_CSV via the _vendor_file_for_host mapping. Preserves stable order:
# CLAUDE.md, AGENTS.md, GEMINI.md, .github/copilot-instructions.md.
# Empty hosts_csv → empty output. Bash 3.2 safe.
derive_pointer_targets_from_hosts() {
  local hosts_csv="${1:-}"
  local _out="" _v _seen_agents=false _seen_claude=false _seen_gemini=false _seen_copilot=false
  local _h
  # Use stable order regardless of input order.
  for _h in claude-code codex opencode gemini copilot cursor; do
    case ",$hosts_csv," in
      *",${_h},"*)
        _v="$(_vendor_file_for_host "$_h")"
        [[ -z "$_v" ]] && continue
        case "$_v" in
          CLAUDE.md)
            [[ "$_seen_claude" == "true" ]] && continue
            _seen_claude=true ;;
          AGENTS.md)
            [[ "$_seen_agents" == "true" ]] && continue
            _seen_agents=true ;;
          GEMINI.md)
            [[ "$_seen_gemini" == "true" ]] && continue
            _seen_gemini=true ;;
          .github/copilot-instructions.md)
            [[ "$_seen_copilot" == "true" ]] && continue
            _seen_copilot=true ;;
        esac
        if [[ -z "$_out" ]]; then _out="$_v"; else _out="$_out,$_v"; fi
        ;;
    esac
  done
  printf '%s\n' "$_out"
}

# detect_vendor_files_on_disk
#
# Echoes (one per line) the subset of the closed vendor file set that
# exists in the current working directory. Bash 3.2 safe.
detect_vendor_files_on_disk() {
  local v
  for v in CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md; do
    [[ -f "$v" ]] && printf '%s\n' "$v"
  done
}

# _dispatch_vendor_host VENDOR
#
# Echoes the host name that corresponds to a given vendor file.
# Bash 3.2 case-based mapping (no associative arrays).
# Returns empty string for unknown vendors.
_dispatch_vendor_host() {
  case "$1" in
    CLAUDE.md)                        echo "claude-code" ;;
    GEMINI.md)                        echo "gemini"      ;;
    .github/copilot-instructions.md)  echo "copilot"     ;;
    *)                                echo ""            ;;
  esac
}

# _cortex_doc_host DOC
#
# Echoes the host name that corresponds to a root host-doc for the cortex
# injection pass. AGENTS.md returns "codex" as a sentinel; the caller
# handles the codex-OR-opencode special case.
# Bash 3.2 case-based mapping.
_cortex_doc_host() {
  case "$1" in
    CLAUDE.md)                        echo "claude-code" ;;
    .github/copilot-instructions.md)  echo "copilot"     ;;
    AGENTS.md)                        echo "codex"       ;;
    *)                                echo ""            ;;
  esac
}

# dispatch_pointer_text_for VENDOR
#
# Echoes the markdown body of the dispatch-pointer block for a given
# vendor file. Heading depth is `## Eidolons` (polite to a user's
# existing top-level `# `). Bash 3.2 safe — uses printf line-by-line
# (no heredocs nested in $()).
dispatch_pointer_text_for() {
  local vendor="$1"
  case "$vendor" in
    CLAUDE.md)
      printf '%s\n' \
        "## Eidolons" \
        "" \
        "This project uses [Eidolons](https://github.com/Rynaro/eidolons). The canonical agent dispatch table, methodology references, and per-Eidolon hand-off contracts live at [\`./EIDOLONS.md\`](./EIDOLONS.md). Read that file first before responding to any prompt that mentions an Eidolon or matches a TRANCE complexity signal."
      ;;
    GEMINI.md)
      printf '%s\n' \
        "## Eidolons" \
        "" \
        "See [\`./EIDOLONS.md\`](./EIDOLONS.md) for the Eidolons agent dispatch table and methodology references."
      ;;
    .github/copilot-instructions.md)
      printf '%s\n' \
        "This project uses Eidolons. The canonical agent instructions live in \`EIDOLONS.md\` at the repository root. Refer to that file before invoking any agent or methodology."
      ;;
    *)
      printf '%s\n' \
        "See \`./EIDOLONS.md\` for Eidolons agent dispatch and methodology."
      ;;
  esac
}

# apply_dispatch_pointers [<hosts_csv>]
#
# Writes the dispatch-pointer block to every vendor file in
# DISPATCH_POINTER_VENDORS whose corresponding host is in hosts_csv.
# When hosts_csv is empty (legacy callers), all vendors are written (back-compat).
# Pointers redirect to ./EIDOLONS.md (the canonical composition surface).
#
# Warn-and-append protocol: when a vendor file pre-exists with non-empty,
# non-Eidolons content AND the dispatch-pointer marker is absent, emit one
# warn line BEFORE appending. Subsequent syncs (where the marker already
# exists) silently rewrite the block in place — no warn fires.
#
# Opt-outs:
#   EIDOLONS_NO_GEMINI=1  — deprecated; emits deprecation warn in v1.5.0.
#                           gemini is now host-gated via hosts.wire.
#                           Will be removed in v1.6.0.
#
# Bash 3.2 safe. Stdout clean; all log output to stderr (via warn/info/ok).
apply_dispatch_pointers() {
  local hosts_csv="${1:-}"
  local vendor ptr_text warn_append host_for_vendor
  # Deprecation warn for EIDOLONS_NO_GEMINI (v1.5.0: honor+warn; v1.6.0: remove).
  if [[ "${EIDOLONS_NO_GEMINI:-0}" == "1" ]]; then
    warn "EIDOLONS_NO_GEMINI is deprecated; gemini is now host-gated via hosts.wire. Remove the env var and ensure 'gemini' is not in hosts.wire. This env var will be removed in v1.6.0."
  fi
  for vendor in $DISPATCH_POINTER_VENDORS; do
    host_for_vendor="$(_dispatch_vendor_host "$vendor")"
    # Host-gated: skip the vendor if its host is not in hosts.wire.
    # Empty hosts_csv = unrestricted (back-compat fallthrough).
    if [[ -n "$hosts_csv" ]] && [[ ",${hosts_csv}," != *",${host_for_vendor},"* ]]; then
      info "  skipping $vendor (host=$host_for_vendor not in hosts.wire)"
      continue
    fi
    # EIDOLONS_NO_GEMINI=1 still honored (with above deprecation warn already emitted).
    if [[ "$vendor" == "GEMINI.md" ]] && [[ "${EIDOLONS_NO_GEMINI:-0}" == "1" ]]; then
      info "  EIDOLONS_NO_GEMINI=1 — skipping GEMINI.md (deprecated opt-out)"
      continue
    fi
    ptr_text="$(dispatch_pointer_text_for "$vendor")"
    # Detect "first append into populated content" — for the warn line.
    warn_append=false
    if [[ -f "$vendor" ]] \
       && [[ -s "$vendor" ]] \
       && ! grep -qF "<!-- eidolon:dispatch-pointer start -->" "$vendor" 2>/dev/null; then
      warn_append=true
    fi
    upsert_marker_block "$vendor" "dispatch-pointer" "$ptr_text"
    if [[ "$warn_append" == "true" ]]; then
      warn "$vendor exists with user content; appending dispatch-pointer block. To remove, delete <!-- eidolon:dispatch-pointer start --> ... end --> markers and re-run sync."
    fi
  done
}

# ─── Installer subprocess capture ───────────────────────────────────────
# run_installer_captured <name> <verbosity> <clone_dir> [installer_args...]
#
# Invokes the per-Eidolon install.sh. Behaviour gates on verbosity:
#   - verbose: stdout/stderr pass through directly (no capture); installer
#     interactivity is preserved (e.g. for future interactive installers).
#   - default | quiet: combined stdout+stderr captured to a tmpfile. On
#     non-zero exit, the LAST 20 LINES of the tmpfile are dumped to stderr
#     via printf '  [name] %s\n' (one re-prefixed line each), then the function
#     returns the installer's exit code. On zero exit, the tmpfile is silently
#     unlinked. The function NEVER emits the captured stdout on success.
#
# Stdout: clean (no echo to stdout). All log output to stderr.
# Exit code: the installer's exit code (0 on success, non-zero on failure).
# Bash 3.2 safe: no coproc, no process-substitution with exit-code dependence,
# no readarray. Tmpfile created via mktemp; per-call cleanup (no outer trap).
#
# NOTE: per-Eidolon installers invoked from eidolons sync MUST be non-interactive.
# Captured stdout/stderr means the installer's TTY is /dev/null-equivalent.
# Installers reading </dev/tty or prompting for stdin input will hang.
# The roster's current members are non-interactive (EIIS §3 conformant).
run_installer_captured() {
  local name="$1" verbosity="$2" clone_dir="$3"
  shift 3
  local rc=0 tmpfile=""

  if [[ "$verbosity" == "verbose" ]]; then
    # Pass-through (legacy behaviour — installer stdout visible directly).
    bash "$clone_dir/install.sh" "$@"
    return $?
  fi

  # Captured path (default + quiet).
  # Bash 3.2 + set -e safe: `cmd && rc=0 || rc=$?` avoids set -e abort while
  # still capturing the real exit code. Under set -e, a command in a &&/||
  # chain is not subject to automatic exit on failure.
  tmpfile="$(mktemp)"
  bash "$clone_dir/install.sh" "$@" >"$tmpfile" 2>&1 && rc=0 || rc=$?

  if [[ $rc -ne 0 ]]; then
    # Buffered tail of the captured output on failure.
    warn "$name install.sh failed (exit $rc). Last 20 lines of installer output:"
    tail -n 20 "$tmpfile" | while IFS= read -r _line; do
      printf '  [%s] %s\n' "$name" "$_line" >&2
    done
  fi

  rm -f "$tmpfile"
  return $rc
}

# ─── .gitignore policy ───────────────────────────────────────────────────
# apply_eidolons_gitignore
#
# Writes (or upserts) a marker-bounded block into the consumer project's
# .gitignore that ignores the bulky per-Eidolon files under .eidolons/<name>/
# while allowlisting the nexus-owned cortex/ and harness/manifest.json.
# This lets `eidolons sync` recreate the working-set artefacts from cache
# without committing ~24k lines of vendored content to VCS.
#
# Behaviour:
#   - No-op when no `.git/` is present (info line, exit 0). The CLI never
#     creates a .gitignore in a non-git directory.
#   - Idempotent: marker-bounded upsert via upsert_marker_block; repeat
#     calls produce identical .gitignore content.
#   - One-time migration hint: if `git ls-files .eidolons/` reports any
#     tracked file, emit a stderr `info` block with the recommended
#     `git rm -r --cached` command. The CLI never modifies the git index.
#
# Output: all on stderr (so callers capturing stdout stay clean).
# Bash 3.2 safe.
apply_eidolons_gitignore() {
  # Bail if not a git repo. .gitignore policy only applies under VCS.
  if [[ ! -d ".git" ]]; then
    info "no .git/ detected — skipping .gitignore management"
    return 0
  fi

  # Built line-by-line to avoid a bash-3.2 parser quirk with heredocs
  # nested inside $() that contain unmatched single quotes.
  # `/.eidolons/*` matches the directory contents (not the directory
  # itself), which keeps cortex/ and harness/ traversable so the
  # allowlist re-includes below can take effect — git cannot re-include
  # a file whose parent directory is excluded.
  local content=""
  content="$content# Managed by eidolons. Recreated by \`eidolons sync\`. Do not edit between markers."$'\n'
  content="$content/.eidolons/*"$'\n'
  content="$content!/.eidolons/cortex/"$'\n'
  content="$content!/.eidolons/cortex/**"$'\n'
  content="$content!/.eidolons/harness/"$'\n'
  content="$content!/.eidolons/harness/manifest.json"

  # The "# " prefix forces the HTML-comment marker lines to be parsed by
  # git as comments. Without it, git would not always silently ignore
  # them (the literal `<!--` line is benign today, but the prefix makes
  # intent explicit and survives future gitignore parser changes).
  upsert_marker_block ".gitignore" "gitignore" "$content" "# "

  # Migration hint: if existing .eidolons/ files are tracked in git,
  # tell the user how to untrack them. The CLI does not modify the
  # consumer's git index; the hint is informational only.
  local tracked
  tracked="$(git ls-files .eidolons/ 2>/dev/null | head -1 || true)"
  if [[ -n "$tracked" ]]; then
    info "existing .eidolons/ is git-tracked. To apply the new policy run:"
    info "    git rm -r --cached .eidolons/ && git add .eidolons/cortex/ .eidolons/harness/manifest.json"
    info "    git commit -m 'chore: untrack regenerated eidolons artefacts'"
  fi
}

# ─── Member upgrade status helpers ───────────────────────────────────────
# Extracted from upgrade.sh so both upgrade and doctor share the same data path.
# (Bucket C, spec: eidolons-update-flow-2026-05-05.md)

# nexus_status_label CUR LATEST → one of: up-to-date | upgrade-available | unknown
# CUR and LATEST may carry a leading "v"; it is stripped before comparison.
# (This function is also defined file-locally in upgrade.sh for backward
#  compat; the lib copy is the canonical one going forward.)
_lib_nexus_status_label() {
  local cur="$1" latest="$2"
  if [[ -z "$latest" ]]; then
    echo "unknown"
    return 0
  fi
  local c="${cur#v}" l="${latest#v}"
  case "$c" in
    [0-9]*.[0-9]*.[0-9]*) : ;;
    *) echo "unknown"; return 0 ;;
  esac
  if [[ "$c" == "$l" ]]; then
    echo "up-to-date"
  elif semver_lt "$c" "$l"; then
    echo "upgrade-available"
  else
    echo "up-to-date"
  fi
}

# collect_member_upgrade_rows [TARGET_LIST]
# Echoes one TSV line per declared member (filtered by TARGET_LIST if given):
#   name<TAB>installed<TAB>latest<TAB>constraint<TAB>status
# status ∈ {up-to-date, upgrade-available, pinned-out, not-installed}
# TARGET_LIST is a comma-separated list of member names; empty = all members.
# Silently skips if eidolons.yaml is absent (manifest_exists returns false).
collect_member_upgrade_rows() {
  local target_list="${1:-}"
  manifest_exists || return 0
  local manifest_json members_json
  manifest_json="$(yaml_to_json "$PROJECT_MANIFEST")"
  members_json="$(echo "$manifest_json" | jq -c '.members[]')"

  local target_canon=""
  if [[ -n "$target_list" ]]; then
    target_canon="$(normalize_target_list "$target_list")" || return $?
  fi

  while IFS= read -r mline; do
    [[ -z "$mline" ]] && continue
    local name constraint roster_entry latest installed status
    name="$(echo "$mline" | jq -r '.name')"
    constraint="$(echo "$mline" | jq -r '.version')"
    if [[ -n "$target_canon" ]]; then
      if ! printf '%s\n' "$target_canon" | grep -Fxq "$name"; then
        continue
      fi
    fi
    roster_entry="$(roster_get "$name" 2>/dev/null || true)"
    if [[ -z "$roster_entry" ]]; then
      latest=""
    else
      latest="$(echo "$roster_entry" | jq -r '.versions.latest // empty')"
    fi
    installed="$(lock_member_version "$name")"
    if [[ -z "$installed" ]]; then
      status="not-installed"
    elif [[ -z "$latest" || "$installed" == "$latest" ]]; then
      status="up-to-date"
    elif semver_lt "$installed" "$latest"; then
      if semver_satisfies "$constraint" "$latest"; then
        status="upgrade-available"
      else
        status="pinned-out"
      fi
    else
      status="up-to-date"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "${installed:-—}" "${latest:-—}" "$constraint" "$status"
  done <<<"$members_json"
}

# ─── Release orchestration helpers ────────────────────────────────────────
# (Bucket A, spec: eidolons-update-flow-2026-05-05.md §6 Bucket A)

# release_check_gh_auth REPO SCOPE
# Verifies that `gh auth status` has the named scope for the given repo.
# Returns 0 on success, 1 on failure (auth missing or scope absent).
# All output to stderr only.
release_check_gh_auth() {
  local repo="$1" scope="$2"
  # Check gh auth status for the host.
  local auth_out
  auth_out="$(gh auth status --hostname github.com 2>&1 || true)"
  if ! echo "$auth_out" | grep -qi "Logged in to github.com"; then
    warn "gh not authenticated for github.com — run: gh auth login"
    return 1
  fi
  # Attempt a lightweight API call against the repo to validate token access.
  if ! gh api "repos/$repo" --silent 2>/dev/null; then
    warn "gh authentication insufficient for $repo (need '$scope' scope)"
    warn "Run: gh auth refresh -h github.com -s $scope"
    return 1
  fi
  return 0
}

# release_workflow_run_id REPO WORKFLOW_NAME
# Echoes the run ID of the most recently dispatched workflow run for WORKFLOW_NAME
# in REPO. Returns empty string + exit 1 if no run is found.
release_workflow_run_id() {
  local repo="$1" workflow_name="$2"
  local run_id
  run_id="$(gh run list -R "$repo" \
    --workflow "$workflow_name" \
    --limit 1 \
    --json databaseId \
    -q '.[0].databaseId // empty' 2>/dev/null || true)"
  if [[ -n "$run_id" ]]; then
    echo "$run_id"
    return 0
  fi
  return 1
}

# ─── Lockfile readers ─────────────────────────────────────────────────────
# lock_member_version NAME → echoes the resolved version for NAME from
# eidolons.lock, or empty string if absent / no lockfile.
lock_member_version() {
  local name="$1"
  [[ -f "$PROJECT_LOCK" ]] || { echo ""; return 0; }
  yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r --arg n "$name" '(.members // [])[] | select(.name == $n) | .version' \
    | head -1
}

# lock_member_resolved NAME → echoes the resolved commit fragment for NAME, or "".
lock_member_resolved() {
  local name="$1"
  [[ -f "$PROJECT_LOCK" ]] || { echo ""; return 0; }
  yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r --arg n "$name" '(.members // [])[] | select(.name == $n) | .resolved // ""' \
    | head -1
}
