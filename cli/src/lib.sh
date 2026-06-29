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
#
# Backend detection is memoised in `_YAML_TO_JSON_BACKEND` for the lifetime
# of the process. A single `eidolons init` previously paid the cold-start
# cost of ~14 yq invocations — half of them just probing `--version`.
# The backend never changes mid-run, so resolve it once at source time;
# exporting it survives `$(yaml_to_json …)` subshells (otherwise the
# cache would die with each subshell).
_resolve_yaml_to_json_backend() {
  if command -v yq >/dev/null 2>&1; then
    if yq --version 2>&1 | grep -qi "mikefarah"; then
      _YAML_TO_JSON_BACKEND="yq-mikefarah"
    else
      _YAML_TO_JSON_BACKEND="yq-kislyuk"
    fi
  elif command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    _YAML_TO_JSON_BACKEND="python3"
  else
    _YAML_TO_JSON_BACKEND="none"
  fi
  export _YAML_TO_JSON_BACKEND
}
[[ -z "${_YAML_TO_JSON_BACKEND:-}" ]] && _resolve_yaml_to_json_backend
yaml_to_json() {
  local file="$1"
  case "$_YAML_TO_JSON_BACKEND" in
    yq-mikefarah) yq -o=json eval '.' "$file" ;;
    yq-kislyuk)   yq . "$file" ;;
    python3)
      python3 -c "import sys, json, yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" "$file"
      ;;
    none|*)
      die "Cannot parse YAML: neither yq nor python3+PyYAML is available.
  Fix (recommended): rerun the bootstrap installer to auto-install yq:
      curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
  Or install yq manually: https://github.com/mikefarah/yq/releases
  Or install PyYAML:      pip install --user pyyaml"
      ;;
  esac
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

# ─── Telemetry helpers ────────────────────────────────────────────────────
# project_slug
#   Returns the canonical project slug for the current directory: basename of
#   $PWD, lowercased, with any non-alnum runs replaced by a single dash, and
#   leading/trailing dashes trimmed. Promoted from memory.sh:138-142 so it
#   is the single authoritative derivation. Output is byte-identical to the
#   inline version in memory.sh. All log → stderr; stdout = the slug string.
project_slug() {
  local _bn
  _bn="$(basename "$PWD")"
  printf '%s' "$_bn" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9' '-' \
    | sed -e 's|^-||' -e 's|-$||'
}

# eidolon_prompt_sha NAME
#   Returns the prompt-version identity string for a named Eidolon.
#   Default (free, coarse): the Eidolon's roster versions.latest ([REV-D3-1]).
#   Unknown name or roster lookup failure → prints "null" and returns 0 (honest
#   fallback; never fatal — capture path must be fail-open). All log → stderr.
eidolon_prompt_sha() {
  local _ename="$1"
  local _result
  _result="$(yaml_to_json "$ROSTER_FILE" 2>/dev/null \
    | jq -r --arg n "$_ename" \
        '.eidolons[] | select(.name == $n or ((.aliases // []) | index($n) != null)) | .versions.latest // "null"' \
        2>/dev/null \
    | head -1)" || true
  if [[ -z "$_result" ]]; then
    echo "null"
    return 0
  fi
  echo "$_result"
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
  # Always reap the timer subshell — whether it fired (then exits naturally)
  # or didn't (we kill it). pkill -P targets the timer's direct children
  # (i.e. the inner `sleep`) so a long $RELEASE_TIMEOUT doesn't leave an
  # orphan sleep running. Both branches are idempotent.
  pkill -P "$timer" 2>/dev/null || true
  kill "$timer" 2>/dev/null || true
  wait "$timer" 2>/dev/null || true
  # Decide whether the timer fired by inspecting the polled function's exit
  # code, not by polling the timer subshell's liveness. The previous
  # `kill -0 "$timer"` check raced under heavy runner load: after the
  # timer's `kill -9 "$pid"` returned, the timer subshell had not yet
  # finished its post-kill cleanup, so `kill -0` saw it alive and we
  # entered the "command completed first" branch even though `$pid` had
  # been killed (rc=137, SIGKILL). Now: rc==137 ⇒ timer fired ⇒ map to 124.
  # 143 (SIGTERM) is also mapped — the timer uses -9 today, but document
  # both to stay correct if a future change relaxes it.
  if [[ "$rc" -eq 137 || "$rc" -eq 143 ]]; then
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

# nexus_roster_ref → echoes the roster-refresh target, with fallback chain.
# B1: separates the CLI self-pin (.install_ref) from the roster-refresh target (.roster_ref).
# Resolution order:
#   1. $NEXUS/.roster_ref            (v1.11.0+ canonical)
#   2. $NEXUS/.install_ref           (back-compat for v1.10.0 installs)
#   3. echo ""                       (caller skips refresh)
# Bash 3.2 compatible.
nexus_roster_ref() {
  if [[ -f "$NEXUS/.roster_ref" ]]; then
    tr -d '[:space:]' < "$NEXUS/.roster_ref"
    return 0
  fi
  if [[ -f "$NEXUS/.install_ref" ]]; then
    tr -d '[:space:]' < "$NEXUS/.install_ref"
    return 0
  fi
  echo ""
}

# nexus_ensure_gitignore_sidecar FILE
#
# Ensures that FILE (a basename relative to $NEXUS) appears as a line in
# $NEXUS/.gitignore. If $NEXUS/.gitignore does not exist it is created.
# If it already contains FILE (exact-line match, no leading/trailing space)
# the function is a no-op. Bash 3.2 compatible. All log output to stderr.
#
# This is the canonical repair path for pre-v1.11.0 installs where
# cli/install.sh did not yet list certain sidecar files in .gitignore,
# causing them to show as untracked and tripping the dirty-tree guard in
# `eidolons upgrade self`.
nexus_ensure_gitignore_sidecar() {
  local _sidecar="$1"
  local _gi="$NEXUS/.gitignore"
  if [[ -f "$_gi" ]]; then
    grep -qxF "$_sidecar" "$_gi" 2>/dev/null && return 0
    printf '%s\n' "$_sidecar" >> "$_gi"
    info "nexus_ensure_gitignore_sidecar: added $_sidecar to $_gi (pre-v1.11.0 heal)"
  else
    printf '%s\n' "$_sidecar" > "$_gi"
    info "nexus_ensure_gitignore_sidecar: created $_gi with $_sidecar"
  fi
  return 0
}

# nexus_ensure_roster_ref → auto-backfill $NEXUS/.roster_ref for installs that
# pre-date v1.11.0 (when the .install_ref / .roster_ref split was introduced).
#
# If $NEXUS/.roster_ref does not exist, write the default value:
#   $EIDOLONS_ROSTER_REF  if that env var is set and non-empty
#   otherwise: "main"
#
# After writing the file, ensures it AND all other known sidecar files are
# listed in $NEXUS/.gitignore so they do not appear as untracked in `git
# status`. Pre-v1.11.0 installs lack the .roster_ref entry; older pre-1.11
# installs may also be missing .install_date / .install_ref / .install_commit.
# nexus_ensure_gitignore_sidecar is idempotent, so calling it for files that
# are already listed is a no-op.
#
# Emits one info line to stderr when backfilling so users can see what happened.
# Idempotent: once the file exists the write is a no-op (gitignore heal still runs).
# Bash 3.2 compatible.
nexus_ensure_roster_ref() {
  local _wrote=0
  if [[ ! -f "$NEXUS/.roster_ref" ]]; then
    local _default_ref
    if [[ -n "${EIDOLONS_ROSTER_REF:-}" ]]; then
      _default_ref="$EIDOLONS_ROSTER_REF"
    else
      _default_ref="main"
    fi
    printf '%s\n' "$_default_ref" > "$NEXUS/.roster_ref"
    _wrote=1
    info "Backfilled $NEXUS/.roster_ref = $_default_ref (pre-v1.11.0 install — see CHANGELOG [1.13.4])"
  fi
  # Always heal the .gitignore sidecar entries for all known sidecars.
  # This is safe on every install: nexus_ensure_gitignore_sidecar is
  # idempotent and only appends when the entry is genuinely missing.
  if [[ -d "$NEXUS/.git" || -f "$NEXUS/.gitignore" ]]; then
    local _sc
    for _sc in .install_date .install_ref .install_commit .roster_ref; do
      nexus_ensure_gitignore_sidecar "$_sc"
    done
  fi
}

# nexus_refresh — path-restricted fetch of the roster/data layer.
#
# Updates ONLY the three data-layer paths from the roster channel ref recorded
# in $NEXUS/.roster_ref (v1.11.0+) or $NEXUS/.install_ref (back-compat):
#
#   REFRESH_PATHS: roster   EIDOLONS.md   methodology/cortex
#
# CLI code paths (cli/, schemas/, VERSION, docs/, .github/, etc.) are NEVER
# touched — they stay pinned at the installed tag (.install_ref). This is the
# "CLI pinned / roster floats" contract: `eidolons upgrade self` controls the
# CLI version; nexus_refresh controls the roster catalogue data.
#
# IMPORTANT — delete-does-not-prune: git checkout FETCH_HEAD -- <path> copies
# files present at the ref into the working tree. If a file was DELETED at the
# roster ref it will NOT be removed from the local cache. Stale extra files
# under methodology/cortex/ are inert; index.yaml / mcps.yaml are single-file
# overwrites, so deletions within those files propagate correctly. upgrade self
# (full clone+swap) eventually clears any orphaned stale files.
#
# Skips silently when:
#   - EIDOLONS_NEXUS is set (local-checkout / test mode — never auto-fetch)
#   - EIDOLONS_SKIP_REFRESH=1 (user opt-out for offline-first workflows)
#   - $NEXUS has no .git directory (bare checkout; upgrade path handles it)
#   - .roster_ref and .install_ref both absent or contain "unknown"
#   - .roster_ref = "stable" and nexus_latest_tag fails (offline) → warn + skip
#
# On network failure: emits a warn and returns 0 (non-fatal; stale cache used).
# Bash 3.2 compatible.
nexus_refresh() {
  # Skip when caller explicitly pinned a local checkout.
  if [[ -n "${EIDOLONS_NEXUS:-}" ]]; then
    return 0
  fi
  # Honour opt-out flag.
  if [[ "${EIDOLONS_SKIP_REFRESH:-0}" == "1" ]]; then
    return 0
  fi
  # Only operate on git-managed nexus caches.
  if [[ ! -d "$NEXUS/.git" ]]; then
    return 0
  fi
  # Auto-backfill .roster_ref for pre-v1.11.0 installs (v1.13.3).
  nexus_ensure_roster_ref
  # B1: use nexus_roster_ref (prefers .roster_ref, falls back to .install_ref).
  local ref
  ref="$(nexus_roster_ref)"
  if [[ -z "$ref" || "$ref" == "unknown" ]]; then
    return 0
  fi
  # E5: "stable" is a magic channel token meaning "latest published release tag".
  # Resolve it at fetch time via nexus_latest_tag; offline → warn + skip.
  if [[ "$ref" == "stable" ]]; then
    local resolved_stable
    resolved_stable="$(nexus_latest_tag 2>/dev/null || true)"
    if [[ -z "$resolved_stable" ]]; then
      warn "nexus cache stale; using cached state (stable channel: nexus_latest_tag unavailable — network unavailable?)"
      return 0
    fi
    ref="$resolved_stable"
  fi
  local repo
  repo="${EIDOLONS_REPO:-https://github.com/Rynaro/eidolons}"
  if ! git -C "$NEXUS" fetch --depth 1 origin "$ref" >/dev/null 2>&1; then
    warn "nexus cache stale; using cached state (network unavailable or ref $ref not found)"
    return 0
  fi
  # Path-restricted checkout: update ONLY the roster/data layer.
  # REFRESH_PATHS (keep in sync with _nexus_is_dirty in upgrade_self.sh):
  #   roster   EIDOLONS.md   methodology/cortex
  # Each path is best-effort (|| true) so a ref lacking methodology/cortex/
  # (e.g. an ancient tag) does not abort the whole refresh.
  local _rp
  for _rp in roster EIDOLONS.md methodology/cortex; do
    git -C "$NEXUS" checkout FETCH_HEAD -- "$_rp" >/dev/null 2>&1 || true
  done
  return 0
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
  # In bash 3.2, ${var#~} does not strip a leading tilde because ~ is
  # treated as a tilde-expansion pattern glob. Store the operator chars in
  # local variables so ${constraint#$_op_char} works correctly.
  local _oc_caret="^" _oc_tilde="~" _oc_eq="="
  case "$constraint" in
    ^*) op="^"; base="${constraint#$_oc_caret}" ;;
    ~*) op="~"; base="${constraint#$_oc_tilde}" ;;
    =*) op="="; base="${constraint#$_oc_eq}" ;;
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

  # Note: bare ~) in a case pattern is subject to tilde expansion in bash 3.2
  # (expands to $HOME), so "~") must be quoted explicitly.
  case "$op" in
    "=")
      [[ "$version" == "$base" ]] && return 0 || return 1
      ;;
    "~")
      # >= base, < base.major.(base.minor + 1).0
      [[ "$vmajor" == "$cmajor" && "$vminor" == "$cminor" ]] && return 0 || return 1
      ;;
    "^")
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

# resolve_version_constraint NAME CONSTRAINT → echoes the best concrete version
# that satisfies CONSTRAINT from the roster's known version set for NAME.
#
# Resolution order:
#   1. Collect candidate versions from roster: .versions.latest +
#      .versions.pins.stable + keys of .versions.releases (if present).
#   2. Filter candidates through semver_satisfies CONSTRAINT.
#   3. Return the highest (sort -V tail -1) passing candidate.
#   4. If none pass: die with a helpful message listing available versions.
#
# For bare X.Y.Z or =X.Y.Z constraints the roster need not even contain the
# version; the constraint itself is returned unchanged (exact-pin workflow —
# fetch_eidolon will fail later if the tag doesn't exist).
#
# Bash 3.2 compatible: no associative arrays, no mapfile.
resolve_version_constraint() {
  local name="$1" constraint="$2"
  # bash 3.2: store operator chars in variables so ${var#$op} strips correctly.
  local _rc_caret="^" _rc_tilde="~" _rc_eq="="

  # For exact pins (bare X.Y.Z, =X.Y.Z) skip roster scan — return literal base.
  local _op_probe
  case "$constraint" in
    ^*|~*) _op_probe="range" ;;
    =*)    _op_probe="exact"; constraint="${constraint#$_rc_eq}" ;;
    *)     _op_probe="exact" ;;
  esac
  if [[ "$_op_probe" == "exact" ]]; then
    echo "$constraint"
    return 0
  fi

  # Collect known versions from the roster entry.
  # Query the roster directly via jq (bypassing roster_get which calls die) so
  # a missing entry returns empty rather than aborting via exit 1. This is
  # Bash 3.2 + set -e safe: no subshell exit propagation from die().
  local entry candidates best _v
  entry="$(yaml_to_json "$ROSTER_FILE" 2>/dev/null \
    | jq --arg n "$name" '.eidolons[] | select(.name == $n or ((.aliases // []) | index($n) != null))' \
    2>/dev/null || true)"
  if [[ -z "$entry" || "$entry" == "null" ]]; then
    # No roster entry — fall back to stripping the operator prefix.
    local base="${constraint#$_rc_caret}"; base="${base#$_rc_tilde}"
    echo "$base"
    return 0
  fi

  # Build a newline-separated list of candidate versions (deduplicated via sort).
  candidates="$(printf '%s\n' "$entry" \
    | jq -r '
        [
          (.versions.latest // empty),
          (.versions.pins.stable // empty),
          (.versions.releases // {} | keys[])
        ] | .[] | select(. != null and . != "")
      ' 2>/dev/null \
    | sort -Vu)"

  # Filter through semver_satisfies and pick the highest.
  best=""
  while IFS= read -r _v; do
    [[ -z "$_v" ]] && continue
    if semver_satisfies "$constraint" "$_v"; then
      if [[ -z "$best" ]]; then
        best="$_v"
      else
        best="$(printf '%s\n%s\n' "$best" "$_v" | sort -V | tail -1)"
      fi
    fi
  done <<EOF
$candidates
EOF

  if [[ -n "$best" ]]; then
    echo "$best"
    return 0
  fi

  # No candidate satisfied the constraint — die with a helpful message.
  local avail
  avail="$(printf '%s\n' "$candidates" | tr '\n' ' ' | sed 's/ *$//')"
  die "No version satisfies $constraint for $name; available: ${avail:-none}"
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
    # Newline-aware separator (D3). tail -c 2 + od -An -c is portable;
    # bash 3.2 safe. _sep carries the literal chars '\n' interpreted by
    # printf %b, ensuring the start marker is preceded by exactly one
    # blank line (\n\n boundary) regardless of the file's current tail bytes.
    local _tail_bytes _sep
    _tail_bytes="$(tail -c 2 "$dst" 2>/dev/null | od -An -c 2>/dev/null | tr -d ' ' || true)"
    case "$_tail_bytes" in
      *\\n\\n*) _sep="" ;;        # already ends with blank line
      *\\n*)    _sep="\\n" ;;     # ends with single newline → add one
      *)        _sep="\\n\\n" ;;  # no trailing newline
    esac
    {
      printf '%b%s\n' "$_sep" "$start"
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

# collapse_consecutive_blanks FILE
#
# Collapses runs of ≥2 consecutive empty lines to exactly 1. Idempotent.
# Bash 3.2 safe. No-op when FILE does not exist or is empty.
# Stdout clean; one info line to stderr on mutation.
collapse_consecutive_blanks() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  [[ -s "$file" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk '
    BEGIN { blank = 0 }
    /^$/  { if (blank < 1) print; blank++; next }
          { print; blank = 0 }
  ' "$file" > "$tmp"
  if ! cmp -s "$file" "$tmp"; then
    mv "$tmp" "$file"
    chmod 0644 "$file" 2>/dev/null || true
    info "  collapse_consecutive_blanks: normalised blank-line runs in $file"
  else
    rm -f "$tmp"
  fi
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
    cursor)      echo "AGENTS.md" ;;
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
    if [[ -f "$v" ]]; then printf '%s\n' "$v"; fi
  done
}

# ─── Round-4 AGENTS-precedence helpers ───────────────────────────────────────

# detect_agents_precedence_trigger HOSTS_CSV SHARED_DISPATCH
#
# Returns 0 (success) when AGENTS-precedence applies:
#   - AGENTS.md exists on disk, OR
#   - SHARED_DISPATCH == "true", OR
#   - "codex" appears in HOSTS_CSV (comma-separated host slugs).
# Returns 1 otherwise. Stdout clean; no log output. Bash 3.2 safe.
detect_agents_precedence_trigger() {
  local hosts_csv="${1:-}"
  local shared_dispatch="${2:-false}"
  [[ -f "AGENTS.md" ]] && return 0
  [[ "$shared_dispatch" == "true" ]] && return 0
  case ",$hosts_csv," in
    *",codex,"*) return 0 ;;
  esac
  return 1
}

# _csv_union CSV_A CSV_B
#
# Echoes a comma-separated union of CSV_A and CSV_B, preserving first-seen
# order and deduplicating elements. Bash 3.2 safe — no associative arrays.
_csv_union() {
  local csv_a="${1:-}" csv_b="${2:-}"
  local _out="" _seen="" _el
  for _el in $(printf '%s\n' "$csv_a" "$csv_b" | tr ',' '\n'); do
    [[ -z "$_el" ]] && continue
    # Check if already seen.
    case ",$_seen," in
      *",$_el,"*) continue ;;
    esac
    _seen="$_seen,$_el"
    if [[ -z "$_out" ]]; then _out="$_el"; else _out="$_out,$_el"; fi
  done
  printf '%s\n' "$_out"
}

# _validate_pointer_targets_csv CSV
#
# Echoes a validated comma-separated list. Unknown elements emit warn()
# (or die() when STRICT_HOSTS=true). Known elements are passed through.
# Bash 3.2 safe.
_validate_pointer_targets_csv() {
  local csv="${1:-}" _pt _out="" _strict="${STRICT_HOSTS:-false}"
  for _pt in $(printf '%s\n' "$csv" | tr ',' '\n'); do
    [[ -z "$_pt" ]] && continue
    case "$_pt" in
      CLAUDE.md|AGENTS.md|GEMINI.md|.github/copilot-instructions.md)
        if [[ -z "$_out" ]]; then _out="$_pt"; else _out="$_out,$_pt"; fi
        ;;
      *)
        if [[ "$_strict" == "true" ]]; then
          die "Unknown pointer target '$_pt' (--strict-hosts)"
        else
          warn "Unknown pointer target '$_pt' — skipping (valid: CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md)"
        fi
        ;;
    esac
  done
  printf '%s\n' "$_out"
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
    CLAUDE.md|AGENTS.md)
      # Same wording for both — AGENTS.md is now a first-class pointer target (D6).
      printf '%s\n' \
        "## Eidolons" \
        "" \
        "This project uses [Eidolons](https://github.com/Rynaro/eidolons). The canonical agent dispatch table, methodology references, and per-Eidolon hand-off contracts live at [\`./EIDOLONS.md\`](./EIDOLONS.md). Read that file before any non-trivial prompt — this is the default operating mode, not an opt-in."
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

# apply_dispatch_pointers <pointer_targets_csv> [<hosts_csv>]
#
# Writes the dispatch-pointer block to every vendor file in
# pointer_targets_csv. hosts_csv is optional context (for future use);
# the pointer_targets list IS the host-gating result by construction
# (init/sync already mapped hosts → vendors via _vendor_file_for_host).
#
# AGENTS.md is now a first-class target when present in pointer_targets_csv.
# Pointers redirect to ./EIDOLONS.md (the canonical composition surface).
#
# Warn-and-append protocol: when a vendor file pre-exists with non-empty,
# non-Eidolons content AND the dispatch-pointer marker is absent, emit one
# warn line BEFORE appending. Subsequent syncs silently rewrite in place.
#
# Opt-outs:
#   EIDOLONS_NO_GEMINI=1  — deprecated; honored with deprecation warn.
#                           gemini is now host-gated via pointer_targets.
#
# Bash 3.2 safe. Stdout clean; all log output to stderr (via warn/info/ok).
apply_dispatch_pointers() {
  local pointer_targets_csv="${1:-}"
  local hosts_csv="${2:-}"
  local vendor ptr_text warn_append
  # Deprecation warn for EIDOLONS_NO_GEMINI.
  if [[ "${EIDOLONS_NO_GEMINI:-0}" == "1" ]]; then
    warn "EIDOLONS_NO_GEMINI is deprecated; gemini is now gated via hosts.pointer_targets. Remove the env var. This env var will be removed in a future release."
  fi
  for vendor in $(echo "$pointer_targets_csv" | tr ',' ' '); do
    [[ -z "$vendor" ]] && continue
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
    collapse_consecutive_blanks "$vendor"
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

# ─── Junction marker teardown (collision-safe) ───────────────────────────
# remove_junction_marker [HARNESS_ROOT]
# Surgically removes the Junction harness *marker* (manifest.json) WITHOUT
# clobbering the sibling subsystems that share the .eidolons/harness/ parent:
#   - hooks/   — host-hook shims written by 'eidolons harness install'
#   - cache/   — memory preflight cache (memory.sh)
# The parent directory is reclaimed only when it is left empty: rmdir refuses a
# non-empty directory, so a surviving hooks/ or cache/ keeps it intact.
#
# Why this exists: 'eidolons mcp uninstall junction', 'eidolons sync' (Junction
# absent), and the legacy 'eidolons harness uninstall' previously all did
# `rm -rf .eidolons/harness`, which deleted the host-hook shims too. The orphaned
# .claude/settings.json hook entries then fired
#   /bin/sh: .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh: not found
# on every prompt. Removal of the Junction marker must be scoped to the marker.
#
# Always returns 0 (teardown is best-effort/idempotent). Bash 3.2 safe.
remove_junction_marker() {
  local hroot="${1:-./.eidolons/harness}"
  [[ -e "$hroot" ]] || return 0
  # Remove only the Junction-owned marker file.
  rm -f "$hroot/manifest.json" 2>/dev/null || true
  # Reclaim the dir only if nothing else (hooks/, cache/, …) still lives in it.
  rmdir "$hroot" 2>/dev/null || true
  return 0
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

# ─── doctor --deep helpers (D1..D6, Layer 1 methodology integrity) ─────────
# All helpers are bash 3.2 compatible: no associative arrays, no mapfile,
# no ${var,,}. All err/pass/warn calls write to stdout (doctor.sh convention).
# Each helper returns the count of failures (0 = pass, >0 = fail).
#
# NOTE: err/pass/warn are defined in doctor.sh, not in lib.sh. These helpers
# are designed to be called from doctor.sh after sourcing lib.sh. They use
# the same err/pass/warn signature: simple printf wrappers writing to stdout.

# _deep_check_outbound_links FILE NAME LABEL
#
# Shared helper for D2 (agent.md) and D3 (SPEC.md) outbound link checks.
# Greps FILE for paths matching the pattern:
#   (\.eidolons/[name]/)?(skills|templates|schemas)/[...].{md,json,yaml,yml}
# For each match, normalises to .eidolons/<name>/<rest> when no prefix,
# then verifies the file exists on disk. Returns count of broken refs.
# Bash 3.2 compatible: uses while-read loop over grep output.
_deep_check_outbound_links() {
  local file="$1" name="$2" label="$3"
  if [[ ! -f "$file" ]]; then
    if [[ "$label" == "SPEC.md" ]]; then
      # SPEC.md absent on legacy members (pre-v1.3) → warn, not err.
      warn "$name: $file missing (pre-v1.3 install — run 'eidolons sync' to update)"
    else
      err "$name: $file missing (cannot check outbound links)"
      return 1
    fi
    return 0
  fi
  local broken=0 ref normalised
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    case "$ref" in
      .eidolons/*) normalised="$ref" ;;
      *)           normalised=".eidolons/$name/$ref" ;;
    esac
    if [[ ! -f "$normalised" ]]; then
      err "$name: $label → $ref (resolves to $normalised, not found)"
      broken=$((broken + 1))
    fi
  done < <(grep -Eo '(\.eidolons/[a-z][a-z0-9-]*/)?(skills|templates|schemas)/[a-zA-Z0-9._/-]+\.(md|json|yaml|yml)' "$file" 2>/dev/null || true)
  if (( broken == 0 )); then
    pass "$name: $label outbound links resolve"
  fi
  return "$broken"
}

# deep_check_agent_token_budget NAME
#
# D1: count words in .eidolons/<n>/agent.md, multiply by 4/3, compare to 1000.
# MUST-fail when tokens > 1000. Returns 0 on pass, 1 on fail.
# Bash 3.2 compatible (arithmetic with $(( )) and wc -w).
deep_check_agent_token_budget() {
  local name="$1"
  local path=".eidolons/$name/agent.md"
  if [[ ! -f "$path" ]]; then
    err "$name: $path missing (cannot check token budget)"
    return 1
  fi
  local words tokens
  words="$(wc -w < "$path" | tr -d ' ')"
  tokens="$(( words * 4 / 3 ))"
  if (( tokens > 1000 )); then
    err "$name: agent.md is ~${tokens} tokens (budget: 1000) — re-install or trim"
    return 1
  fi
  pass "$name: agent.md within token budget (${tokens}/1000)"
  return 0
}

# deep_check_agent_links NAME
#
# D2: check outbound links in .eidolons/<n>/agent.md.
# Delegates to _deep_check_outbound_links. Returns broken-ref count.
deep_check_agent_links() {
  local name="$1"
  local path=".eidolons/$name/agent.md"
  # If agent.md is missing, D1 already errored; skip silently here.
  [[ -f "$path" ]] || return 0
  local rc=0
  _deep_check_outbound_links "$path" "$name" "agent.md" || rc=$?
  return "$rc"
}

# deep_check_spec_links NAME
#
# D3: check outbound links in .eidolons/<n>/SPEC.md.
# Delegates to _deep_check_outbound_links. SPEC.md absent → warn (not err).
deep_check_spec_links() {
  local name="$1"
  local rc=0
  _deep_check_outbound_links ".eidolons/$name/SPEC.md" "$name" "SPEC.md" || rc=$?
  return "$rc"
}

# deep_check_manifest_integrity NAME VERSION
#
# D4: compare installed manifest_sha256 against eidolons.lock entry.
# WARN-skip when lock has no manifest_sha256 (legacy/pre-1.4 installs).
# Returns 0 on pass or WARN-skip, 1 on mismatch/error.
deep_check_manifest_integrity() {
  local name="$1" version="$2"
  local lock_sha
  lock_sha="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r --arg n "$name" \
      '(.members // [])[] | select(.name == $n) | .manifest_sha256 // empty' 2>/dev/null || true)"
  if [[ -z "$lock_sha" ]]; then
    warn "$name@$version: no manifest_sha256 in lock (legacy / pre-1.4 release) — skip"
    return 0
  fi
  local installed_sha
  installed_sha="$(lock_manifest_sha256 ".eidolons/$name/install.manifest.json" 2>/dev/null || true)"
  if [[ -z "$installed_sha" ]]; then
    err "$name@$version: cannot compute installed manifest_sha256"
    return 1
  fi
  if [[ "$installed_sha" != "$lock_sha" ]]; then
    err "$name@$version: manifest drift — installed=$installed_sha lock=$lock_sha"
    return 1
  fi
  pass "$name@$version: manifest integrity verified"
  return 0
}

# deep_check_host_agent_body NAME
#
# D5: for each host vendor dir present (.claude/agents, .codex/agents,
# .opencode/agents), verify the per-member agent file:
#   - References .eidolons/<n>/agent.md  (MUST)
#   - References .eidolons/<n>/SPEC.md   (MUST)
#   - Does NOT reference <UPPER>.md patterns (MUST NOT — legacy)
# Returns count of failures (0 = pass).
# Bash 3.2 compatible: tr for upper-case, no ${var^^}.
deep_check_host_agent_body() {
  local name="$1"
  local upper
  upper="$(echo "$name" | tr 'a-z-' 'A-Z_' | tr '_' '-')"
  local host_dir host_file rc=0
  for host_dir in .claude/agents .codex/agents .opencode/agents; do
    host_file="$host_dir/$name.md"
    [[ -f "$host_file" ]] || continue
    if ! grep -qF ".eidolons/$name/agent.md" "$host_file" 2>/dev/null; then
      err "$name: $host_file does not reference .eidolons/$name/agent.md"
      rc=$((rc + 1))
    fi
    if ! grep -qF ".eidolons/$name/SPEC.md" "$host_file" 2>/dev/null; then
      err "$name: $host_file does not reference .eidolons/$name/SPEC.md"
      rc=$((rc + 1))
    fi
    if grep -Eq "(^|[^A-Z])${upper}\.md([^A-Z]|$)" "$host_file" 2>/dev/null; then
      err "$name: $host_file contains legacy ${upper}.md reference"
      rc=$((rc + 1))
    fi
  done
  if (( rc == 0 )); then
    pass "$name: host-vendor agent bodies clean"
  fi
  return "$rc"
}

# deep_check_skills_dual_write NAME
#
# D6: for every .eidolons/<n>/skills/*.md, verify the dual-write copy
# at .claude/skills/<n>-<basename>/SKILL.md exists and SHA matches.
# Returns count of failures (0 = pass).
# Bash 3.2 compatible: no mapfile, glob expansion in for loop.
deep_check_skills_dual_write() {
  local name="$1"
  local skills_dir=".eidolons/$name/skills"
  if [[ ! -d "$skills_dir" ]]; then
    pass "$name: no skills/ directory (nothing to dual-write)"
    return 0
  fi
  local src dst src_sha dst_sha rc=0 skill_basename
  for src in "$skills_dir"/*.md; do
    [[ -f "$src" ]] || continue
    skill_basename="$(basename "$src" .md)"
    dst=".claude/skills/${name}-${skill_basename}/SKILL.md"
    if [[ ! -f "$dst" ]]; then
      err "$name: skills dual-write missing — $dst"
      rc=$((rc + 1))
      continue
    fi
    src_sha="$(sha256_file "$src")"
    dst_sha="$(sha256_file "$dst")"
    if [[ "$src_sha" != "$dst_sha" ]]; then
      err "$name: skills dual-write SHA drift — $src vs $dst"
      rc=$((rc + 1))
    fi
  done
  if (( rc == 0 )); then
    pass "$name: skills dual-write parity verified"
  fi
  return "$rc"
}

# deep_check_aci_conformance NAME
#
# D7: verify the member's roster security block (the read/write/network boundary)
# conforms to its capability class's ACI contract in roster/aci.yaml. Codifies the
# SWE-agent ACI rubric (R8-02) as a mechanical gate — read-only-by-construction
# classes MUST NOT declare writes_repo:true, tool-less classes MUST declare all
# boundaries false, etc. Returns the violation count (0 = conformant).
deep_check_aci_conformance() {
  local name="$1"
  local aci_file; aci_file="$(dirname "$ROSTER_FILE")/aci.yaml"
  if [[ ! -f "$aci_file" ]]; then
    warn "$name: roster/aci.yaml missing — skipping ACI conformance (D7)"
    return 0
  fi
  local entry; entry="$(roster_get "$name" 2>/dev/null)" || {
    err "$name: not found in roster (cannot check ACI conformance)"; return 1; }
  local aci; aci="$(yaml_to_json "$aci_file")"
  local class; class="$(printf '%s' "$entry" | jq -r '.capability_class // ""')"
  if [[ -z "$class" ]]; then
    warn "$name: no capability_class in roster — skipping ACI conformance"
    return 0
  fi

  # The conformance logic lives in one jq program: it emits one line per
  # violation. Bool-safe comparisons throughout — `// false` would turn an
  # explicit `false` into the fallback, so we compare typed values directly.
  local violations
  violations="$(jq -nr \
    --argjson entry "$entry" --argjson aci "$aci" \
    '
    $aci.classes[$entry.capability_class] as $p
    | ($entry.security // {}) as $sec
    | if ($p == null) or ($p.exempt == true) then empty
      else
        ( if ($aci.universal.reads_network != null) and ($sec.reads_network != null)
             and ($sec.reads_network != $aci.universal.reads_network)
          then "reads_network=\($sec.reads_network) violates universal contract (must be \($aci.universal.reads_network))"
          else empty end ),
        ( if ($p.read_only == true) and ($sec.writes_repo == true)
          then "class \($entry.capability_class) is read-only-by-construction but writes_repo=true"
          else empty end ),
        ( if ($p.reads_repo != null) and ($sec.reads_repo != null) and ($sec.reads_repo != $p.reads_repo)
          then "class \($entry.capability_class) contract requires reads_repo=\($p.reads_repo) but reads_repo=\($sec.reads_repo)"
          else empty end ),
        ( if ($p.tool_less == true) and (($sec.writes_repo == true) or ($sec.reads_repo == true) or ($sec.reads_network == true))
          then "class \($entry.capability_class) is tool-less but declares reads_repo=\($sec.reads_repo) writes_repo=\($sec.writes_repo) reads_network=\($sec.reads_network)"
          else empty end )
      end
    ' 2>/dev/null)"

  local rc=0
  if [[ -n "$violations" ]]; then
    while IFS= read -r _v; do
      [[ -z "$_v" ]] && continue
      err "$name: ACI violation — $_v"
      rc=$((rc + 1))
    done <<< "$violations"
  else
    pass "$name: ACI boundary conforms (class=$class)"
  fi
  return "$rc"
}

# deep_check_host_tier_gate
#
# D9: when ≥2 coders are present in the routing table and one declares
# requires_host_tier, assert that with host_tier unset/standard the default
# resolution does NOT pick the gated coder. This is a structural check on the
# routing inputs — it catches a misconfiguration where a thinking-only coder is
# declared default_for_class but no fallback coder exists (so a conservative host
# would have nowhere to fall back to). Pure jq over routing.yaml + eidolons.yaml;
# no live routing call. Returns 0 (pass) or 1 (misconfiguration found).
deep_check_host_tier_gate() {
  local routing_file; routing_file="$(dirname "$ROSTER_FILE")/routing.yaml"
  if [[ ! -f "$routing_file" ]]; then
    pass "D10 host-tier gate: no routing.yaml — skip"
    return 0
  fi

  local routing_json; routing_json="$(yaml_to_json "$routing_file" 2>/dev/null || true)"
  if [[ -z "$routing_json" ]]; then
    warn "D10 host-tier gate: could not parse routing.yaml — skip"
    return 0
  fi

  # Read host_tier from the project manifest (null if absent).
  local host_tier_val="null"
  if [[ -f "$PROJECT_MANIFEST" ]]; then
    local _ht; _ht="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null \
      | jq -r '.host_tier // empty' 2>/dev/null || true)"
    if [[ -n "$_ht" ]]; then
      host_tier_val="$_ht"
    fi
  fi

  # Run the structural check via jq.
  # Logic:
  #   1. If fewer than 2 coder-class members → skip (no tiebreak in play).
  #   2. Find the default_for_class coder.
  #   3. If it declares requires_host_tier AND the project host_tier does NOT match:
  #      assert there is at least one OTHER coder to fall back to.
  #      Misconfiguration = gated default + no fallback.
  local result
  result="$(printf '%s' "$routing_json" | jq -r \
    --arg host_tier "$host_tier_val" \
    '
    (.eidolons | to_entries
      | map(select(.value.capability_class == "coder"))
    ) as $coders
    | if ($coders | length) < 2 then "skip"
      else
        ($coders | map(select(.value.default_for_class == "coder")) | .[0]) as $dflt
        | if $dflt == null then "skip"
          else
            ($dflt.value.requires_host_tier // null) as $rht
            | if $rht == null then "ok: no requires_host_tier on default coder"
              elif $rht == $host_tier then "ok: host_tier matches requires_host_tier"
              else
                ($coders | map(select(.key != $dflt.key)) | length) as $nfallback
                | if $nfallback > 0
                  then "ok: gated coder has fallback"
                  else "FAIL: default coder \($dflt.key) requires host_tier=\($rht) but host_tier=\($host_tier) and no fallback coder exists"
                  end
              end
          end
      end
    ' 2>/dev/null || echo "error")"

  case "$result" in
    skip|ok*)
      pass "D10 host-tier gate: routing tiebreak correctly structured"
      return 0
      ;;
    FAIL:*)
      err "D10 host-tier gate: ${result#FAIL: }"
      return 1
      ;;
    error)
      warn "D10 host-tier gate: jq parse error — skip"
      return 0
      ;;
    *)
      pass "D10 host-tier gate: routing tiebreak correctly structured"
      return 0
      ;;
  esac
}

#
# D12: harness lock⇄files consistency (R22, P3)
# Project-level gate: verifies that the lockfile's harness: claims match
# the on-disk surfaces (shims exist+exec, settings/hooks entries present,
# strict surfaces only on verified-sound hosts, effective-tier report).
# Returns the error count (0 = pass, ≥1 = fatal).
# Bash 3.2 safe: no declare -A, no readarray.
deep_check_harness_consistency() {
  local lock_json
  lock_json="$(yaml_to_json "${PROJECT_LOCK:-eidolons.lock}" 2>/dev/null || echo '{}')"
  local schema
  schema="$(printf '%s' "$lock_json" | jq -r '.harness.schema_version // "absent"' 2>/dev/null || echo "absent")"

  if [[ "$schema" == "absent" ]]; then
    pass "D12 harness: not installed (skip)"
    return 0
  fi

  local rc=0

  # schema_version must be 1.
  if [[ "$schema" != "1" ]]; then
    err "D12 harness.schema_version != 1 ($schema)"
    rc=$((rc + 1))
  fi

  # Every shim_path must exist and be executable.
  local _shim_line
  while IFS= read -r _shim_line; do
    [[ -z "$_shim_line" ]] && continue
    if [[ ! -f "$_shim_line" ]]; then
      err "D12 shim missing: $_shim_line (lock claims it but file absent)"
      rc=$((rc + 1))
    elif [[ ! -x "$_shim_line" ]]; then
      err "D12 shim not executable: $_shim_line"
      rc=$((rc + 1))
    fi
  done < <(printf '%s' "$lock_json" | jq -r '(.harness.shim_paths // [])[]' 2>/dev/null)

  # Check wired hosts for their config files.
  local _hosts_wired
  _hosts_wired="$(printf '%s' "$lock_json" | jq -r '(.harness.hosts_wired // []) | join(",")' 2>/dev/null || echo "")"

  if printf '%s' ",$_hosts_wired," | grep -q ",claude-code,"; then
    local settings_json=".claude/settings.json"
    if [[ ! -f "$settings_json" ]]; then
      err "D12 .claude/settings.json missing — claude-code wired but settings absent"
      rc=$((rc + 1))
    elif ! jq empty "$settings_json" 2>/dev/null; then
      err "D12 .claude/settings.json is not valid JSON"
      rc=$((rc + 1))
    else
      local _ups_check
      _ups_check="$(jq -r '(.hooks.UserPromptSubmit // []) | map(.hooks[]?.command? // "") | map(select(startswith(".eidolons/harness/"))) | length' "$settings_json" 2>/dev/null || echo "0")"
      if [[ "$_ups_check" == "0" ]]; then
        err "D12 .claude/settings.json missing eidolons UserPromptSubmit entry"
        rc=$((rc + 1))
      fi
    fi
  fi

  if printf '%s' ",$_hosts_wired," | grep -q ",codex,"; then
    local codex_hooks=".codex/hooks.json"
    if [[ ! -f "$codex_hooks" ]]; then
      err "D12 .codex/hooks.json missing — codex wired but hooks file absent"
      rc=$((rc + 1))
    elif ! jq empty "$codex_hooks" 2>/dev/null; then
      err "D12 .codex/hooks.json is not valid JSON"
      rc=$((rc + 1))
    fi
  fi

  if [[ -f "opencode.json" ]] && ! jq empty "opencode.json" 2>/dev/null; then
    err "D12 opencode.json is not valid JSON"
    rc=$((rc + 1))
  fi

  # Strict soundness: verify strict list contains only supported hosts.
  local _strict_wired
  _strict_wired="$(printf '%s' "$lock_json" | jq -r '(.harness.strict // []) | join(",")' 2>/dev/null || echo "")"
  local _strict_modes
  _strict_modes="$(printf '%s' "$lock_json" | jq -c '.harness.strict_modes // {}' 2>/dev/null || echo '{}')"

  local _sh
  for _sh in $(printf '%s' "$_strict_wired" | tr ',' ' '); do
    [[ -z "$_sh" ]] && continue
    case "$_sh" in
      claude-code|codex)
        # Verified-sound hard-block or protected-globs-only — accepted.
        ;;
      opencode)
        # Advisory only — must be recorded as advisory in strict_modes.
        local _oc_mode
        _oc_mode="$(printf '%s' "$_strict_modes" | jq -r '.opencode // "absent"' 2>/dev/null || echo "absent")"
        if [[ "$_oc_mode" != "advisory" ]]; then
          err "D12 opencode in strict[] but strict_modes.opencode != advisory ($__oc_mode) — unsound hard-block record"
          rc=$((rc + 1))
        fi
        ;;
      cursor)
        err "D12 cursor in strict[] — cursor strict is out of P3 scope; remove with 'eidolons harness remove && eidolons harness install'"
        rc=$((rc + 1))
        ;;
      *)
        err "D12 unknown host in strict[]: $_sh"
        rc=$((rc + 1))
        ;;
    esac

    # Orphan strict shim check (WARN: host in strict[] but PreToolUse shim absent).
    local _ptu_shim=".eidolons/harness/hooks/${_sh}-PreToolUse.sh"
    case "$_sh" in
      claude-code|codex)
        if [[ ! -f "$_ptu_shim" ]]; then
          warn "D12 orphan strict: $_sh in strict[] but PreToolUse shim absent ($_ptu_shim)"
        fi
        ;;
    esac
  done

  # Orphan shim check: PreToolUse shim on disk but host NOT in strict[].
  for _h in claude-code codex; do
    local _shim=".eidolons/harness/hooks/${_h}-PreToolUse.sh"
    if [[ -f "$_shim" ]]; then
      if ! printf '%s' ",$_strict_wired," | grep -q ",$_h,"; then
        warn "D12 orphan PreToolUse shim: ${_shim} present but $_h not in strict[] — run 'eidolons harness remove' to clean up"
      fi
    fi
  done

  # opencode plugin only-when-strict (WARN on violation, AC-R22-4).
  local _plugin=".opencode/plugins/eidolons.js"
  if [[ -f "$_plugin" ]]; then
    if ! printf '%s' ",$_strict_wired," | grep -q ",opencode,"; then
      warn "D12 orphan opencode plugin: $_plugin present but opencode not strict-wired — run 'eidolons harness remove' or re-install with --strict"
    fi
  fi
  if printf '%s' ",$_strict_wired," | grep -q ",opencode,"; then
    if [[ ! -f "$_plugin" ]]; then
      warn "D12 opencode strict-advisory recorded but plugin absent ($_plugin) — run 'eidolons harness install --strict'"
    fi
  fi

  # Effective-tier report (informational — never fatal, AC-R22-5).
  local _tier_host _tier _mode
  for _tier_host in $(printf '%s' "$_hosts_wired" | tr ',' ' '); do
    [[ -z "$_tier_host" ]] && continue
    case "$_tier_host" in
      claude-code) _tier="T3" ;;
      codex)       _tier="T3" ;;
      copilot)     _tier="T2" ;;
      cursor)      _tier="T2" ;;
      opencode)    _tier="T1" ;;
      *)           _tier="T?" ;;
    esac
    _mode="inject-only"
    if printf '%s' ",$_strict_wired," | grep -q ",$_tier_host,"; then
      local _m
      _m="$(printf '%s' "$_strict_modes" | jq -r --arg h "$_tier_host" '.[$h] // "block"' 2>/dev/null || echo "block")"
      _mode="strict:${_m}"
    fi
    pass "D12 effective-tier: $_tier_host $_tier [$_mode]"
  done

  if [[ "$rc" -eq 0 ]]; then
    pass "D12 harness lock⇄files consistent"
  fi
  return "$rc"
}

#
# D8: verify that an installed RECEIVER Eidolon ships a BLOCKING verify-incoming
# skill (ECL v1.0 section 6.2.2; frontier roadmap N3). The mechanical SHA-256
# gate runs at the orchestrator; this gate proves every receiver actually carries
# the refuse-on-mismatch skill (not the old warn-only posture), making N3's
# symmetric guarantee an enforced, nexus-checkable invariant. Receiver-ness +
# the blocking/forbidden markers come from roster/ecl.yaml. Returns the violation
# count (0 = conformant or exempt).
deep_check_verify_incoming_conformance() {
  local name="$1"
  local ecl_file; ecl_file="$(dirname "$ROSTER_FILE")/ecl.yaml"
  if [[ ! -f "$ecl_file" ]]; then
    warn "$name: roster/ecl.yaml missing — skipping ECL receiver conformance (D8)"
    return 0
  fi
  local entry; entry="$(roster_get "$name" 2>/dev/null)" || {
    err "$name: not found in roster (cannot check ECL receiver conformance)"; return 1; }
  local class; class="$(printf '%s' "$entry" | jq -r '.capability_class // ""')"
  if [[ -z "$class" ]]; then
    warn "$name: no capability_class in roster — skipping ECL receiver conformance"
    return 0
  fi

  local ecl; ecl="$(yaml_to_json "$ecl_file")"
  # Non-receivers (memory MCP substrate) are exempt — not hand-off receivers.
  local is_recv; is_recv="$(printf '%s' "$ecl" | jq -r --arg c "$class" '.classes[$c].receiver // false')"
  if [[ "$is_recv" != "true" ]]; then
    pass "$name: class=$class is not an ECL hand-off receiver (exempt from D8)"
    return 0
  fi

  local skill_rel; skill_rel="$(printf '%s' "$ecl" | jq -r '.verify_incoming.skill_path // "skills/verify-incoming.md"')"
  local skill=".eidolons/$name/$skill_rel"
  if [[ ! -f "$skill" ]]; then
    err "$name: missing blocking verify-incoming skill ($skill) — ECL 6.2.2 receiver gate (N3)"
    return 1
  fi

  local rc=0
  # At least one blocking marker MUST be present (proves refuse-on-mismatch).
  local found_block=0 _m
  while IFS= read -r _m; do
    [[ -z "$_m" ]] && continue
    if grep -qF -- "$_m" "$skill"; then found_block=1; break; fi
  done <<< "$(printf '%s' "$ecl" | jq -r '.verify_incoming.blocking_markers[]?')"
  if (( found_block == 0 )); then
    err "$name: verify-incoming present but declares no blocking posture (expected REFUSE / SHALL NOT / Do not process)"
    rc=$((rc + 1))
  fi

  # No prescriptive warn-only marker may be present.
  while IFS= read -r _m; do
    [[ -z "$_m" ]] && continue
    if grep -qF -- "$_m" "$skill"; then
      err "$name: verify-incoming declares warn-only posture — found \"$_m\" (ECL 6.2.2 requires refusal)"
      rc=$((rc + 1))
    fi
  done <<< "$(printf '%s' "$ecl" | jq -r '.verify_incoming.forbid_markers[]?')"

  if (( rc == 0 )); then
    pass "$name: blocking verify-incoming gate present (class=$class)"
  fi
  return "$rc"
}

# deep_check_coder_edit_gate NAME
#
# D10: for a `coder`-class member, assert the ACI contract declares
# requires_edit_gate:true AND the member's SPEC.md contains a reference to the
# lint gate (a SPEC.md pointer presence check). This is a DECLARATIVE check —
# not a runtime-wired assertion — mirroring the D7 posture (structure, not
# behaviour). Non-coder members are exempt. Returns 0 (pass/exempt) or 1 (fail).
deep_check_coder_edit_gate() {
  local name="$1"
  local aci_file; aci_file="$(dirname "$ROSTER_FILE")/aci.yaml"
  if [[ ! -f "$aci_file" ]]; then
    warn "$name: roster/aci.yaml missing — skipping coder edit-gate check (D11)"
    return 0
  fi
  local entry; entry="$(roster_get "$name" 2>/dev/null)" || {
    err "$name: not found in roster (cannot check coder edit-gate)"; return 1; }
  local class; class="$(printf '%s' "$entry" | jq -r '.capability_class // ""')"
  # Non-coder members are exempt.
  if [[ "$class" != "coder" ]]; then
    pass "$name: class=$class is not a coder (D11 exempt)"
    return 0
  fi
  local aci; aci="$(yaml_to_json "$aci_file")"
  # 1. ACI contract must declare requires_edit_gate:true for the coder class.
  local aci_gate; aci_gate="$(printf '%s' "$aci" \
    | jq -r '.classes.coder.requires_edit_gate // false' 2>/dev/null || echo "false")"
  local rc=0
  if [[ "$aci_gate" != "true" ]]; then
    err "$name: ACI coder class does not declare requires_edit_gate:true (D11)"
    rc=$((rc + 1))
  fi
  # 2. SPEC.md SHOULD reference the lint/edit-gate contract — ADVISORY (warn, not
  #    fail). The edit-gate methodology is a staged layer-2 rollout, and the
  #    conservative non-loop coder (apivr) legitimately omits it; a new gate must
  #    not regress an existing roster member (staged opt-in — dossier V.3 #5). The
  #    HARD invariant is the ACI class declaration (check 1); the per-member
  #    pointer is surfaced as a warning so loop-native coders adopt it over time.
  local spec_file=".eidolons/$name/SPEC.md"
  if [[ ! -f "$spec_file" ]]; then
    warn "$name: SPEC.md not installed at $spec_file — cannot verify lint-gate pointer (D11 advisory)"
  elif ! grep -qiE '(lint.hook|lint.gate|edit.gate|requires_edit_gate)' "$spec_file" 2>/dev/null; then
    warn "$name: SPEC.md does not yet reference the lint/edit gate (D11 advisory — loop-native coders should add a lint-gate pointer)"
  fi
  if (( rc == 0 )); then
    pass "$name: coder edit-gate declared in ACI coder class (D10)"
  fi
  return "$rc"
}
