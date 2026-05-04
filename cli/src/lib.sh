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

# ─── Logging ───────────────────────────────────────────────────────────────
# All log output goes to stderr so functions whose stdout is captured by
# the caller (e.g. fetch_eidolon, roster_preset_members) can emit progress
# without corrupting their return value.
#
# Icon glyphs (▸✓·⚠✗) are pinned by tests — keep them as-is. Colors are
# now sourced from theme.sh role aliases instead of raw ANSI vars, so a
# theme swap automatically restyles all logs.
say()   { printf "%s%s%s %s\n" "${BOLD}"        "${GLYPH_PROGRESS}" "${RESET}" "$*" >&2; }
ok()    { printf "%s%s%s %s\n" "${UI_SUCCESS}"  "${GLYPH_OK}"       "${RESET}" "$*" >&2; }
info()  { printf "%s%s%s %s\n" "${UI_INFO}"     "${GLYPH_INFO}"     "${RESET}" "$*" >&2; }
warn()  { printf "%s%s%s %s\n" "${UI_WARN}"     "${GLYPH_WARN}"     "${RESET}" "$*" >&2; }
die()   { printf "%s%s%s %s\n" "${UI_ERROR}"    "${GLYPH_ERROR}"    "${RESET}" "$*" >&2; exit 1; }

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
with_timeout() {
  local secs="$1"; shift
  if [[ -z "${1:-}" ]]; then
    return 2
  fi
  "$@" &
  local pid=$!
  ( sleep "$secs" && kill -9 "$pid" 2>/dev/null ) &
  local timer=$!
  local rc=0
  wait "$pid" 2>/dev/null || rc=$?
  # If the timer-killer is still alive, the command completed first; reap it.
  if kill -0 "$timer" 2>/dev/null; then
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
# upsert_marker_block DST MARKER_NAME CONTENT
#
# Owns a marker-bounded region in a composable host-doc file (CLAUDE.md,
# AGENTS.md, .github/copilot-instructions.md). If the region already
# exists, rewrites its body in place. Otherwise appends a new block.
# The marker pattern is <!-- eidolon:<MARKER_NAME> start/end -->.
# All arguments must be plain strings (no embedded newlines in MARKER_NAME).
# Idempotent: calling twice with the same content leaves the file unchanged.
# Bash 3.2 safe — no associative arrays, no ${var,,}, no mapfile.
# All log output goes to stderr; stdout is clean for captured callers.
upsert_marker_block() {
  local dst="$1" marker_name="$2" content="$3"
  local start="<!-- eidolon:${marker_name} start -->"
  local end="<!-- eidolon:${marker_name} end -->"

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
  fi

  rm -f "$content_file"
  info "  upsert_marker_block: $mode $marker_name block in $dst"
}

# remove_marker_block DST MARKER_NAME
#
# Removes the marker-bounded block <!-- eidolon:<MARKER_NAME> start/end -->
# from DST. No-ops when the marker is absent or DST does not exist.
# Idempotent. Bash 3.2 safe.
remove_marker_block() {
  local dst="$1" marker_name="$2"
  local start="<!-- eidolon:${marker_name} start -->"
  local end="<!-- eidolon:${marker_name} end -->"

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
  info "  remove_marker_block: removed $marker_name block from $dst"
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
