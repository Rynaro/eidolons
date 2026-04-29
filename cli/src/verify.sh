#!/usr/bin/env bash
# eidolons verify — re-check installed release integrity metadata
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

usage() {
  cat <<EOF
eidolons verify — verify installed Eidolon release integrity

Usage: eidolons verify [member...]

Behavior:
  - Reads eidolons.lock
  - Compares locked commit/tree/checksums with roster release metadata
  - Recomputes install.manifest.json SHA-256 when the manifest exists
  - In compatibility mode, members without release metadata warn but pass
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ -f "$PROJECT_LOCK" ]] || die "No eidolons.lock found. Run 'eidolons sync' first."

LOCK_JSON="$(yaml_to_json "$PROJECT_LOCK")"

TARGETS=""
if [[ $# -gt 0 ]]; then
  for arg in "$@"; do
    IFS=',' read -ra parts <<< "$arg"
    for p in "${parts[@]}"; do
      [[ -n "$p" ]] && TARGETS="$TARGETS"$'\n'"$p"
    done
  done
  TARGETS="${TARGETS#$'\n'}"
else
  TARGETS="$(echo "$LOCK_JSON" | jq -r '(.members // [])[].name')"
fi

failures=0
checked=0

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  checked=$((checked + 1))
  lock_entry="$(echo "$LOCK_JSON" | jq -c --arg n "$name" '(.members // [])[] | select(.name == $n)' | head -n 1)"
  if [[ -z "$lock_entry" || "$lock_entry" == "null" ]]; then
    warn "$name is not present in eidolons.lock"
    failures=$((failures + 1))
    continue
  fi

  version="$(echo "$lock_entry" | jq -r '.version // ""')"
  target="$(echo "$lock_entry" | jq -r '.target // ""')"
  commit="$(echo "$lock_entry" | jq -r '.commit // (.resolved | split("@")[-1]) // ""')"
  tree="$(echo "$lock_entry" | jq -r '.tree // ""')"
  archive_sha="$(echo "$lock_entry" | jq -r '.archive_sha256 // ""')"
  manifest_sha="$(echo "$lock_entry" | jq -r '.manifest_sha256 // ""')"
  meta="$(release_metadata_for "$name" "$version" 2>/dev/null || true)"

  if [[ -z "$meta" || "$meta" == "null" ]]; then
    if [[ "$(integrity_enforcement_mode)" == "strict" ]]; then
      warn "$name@$version missing roster release integrity metadata"
      failures=$((failures + 1))
    else
      warn "$name@$version has no roster release integrity metadata; compatibility verification is warning-only"
    fi
    continue
  fi

  expected_commit="$(echo "$meta" | jq -r '.commit // empty')"
  expected_tree="$(echo "$meta" | jq -r '.tree // empty')"
  expected_archive="$(echo "$meta" | jq -r '.archive_sha256 // empty')"
  expected_manifest="$(echo "$meta" | jq -r '.manifest_sha256 // empty')"

  if [[ -n "$expected_commit" && "$commit" != "$expected_commit" ]]; then
    warn "$name@$version commit mismatch: lock has ${commit:-unknown}, roster expects $expected_commit"
    failures=$((failures + 1))
    continue
  fi
  if [[ -n "$expected_tree" && "$tree" != "$expected_tree" ]]; then
    warn "$name@$version tree mismatch: lock has ${tree:-unknown}, roster expects $expected_tree"
    failures=$((failures + 1))
    continue
  fi
  if [[ -n "$expected_archive" && "$archive_sha" != "$expected_archive" ]]; then
    warn "$name@$version archive checksum mismatch: lock has ${archive_sha:-unknown}, roster expects $expected_archive"
    failures=$((failures + 1))
    continue
  fi

  if [[ -f "$target/install.manifest.json" ]]; then
    actual_manifest="$(lock_manifest_sha256 "$target/install.manifest.json")"
    if [[ -n "$manifest_sha" && "$actual_manifest" != "$manifest_sha" ]]; then
      warn "$name@$version installed manifest changed: got $actual_manifest, lock expects $manifest_sha"
      failures=$((failures + 1))
      continue
    fi
    if [[ -n "$expected_manifest" && "$actual_manifest" != "$expected_manifest" ]]; then
      warn "$name@$version manifest checksum mismatch: got $actual_manifest, roster expects $expected_manifest"
      failures=$((failures + 1))
      continue
    fi
  elif [[ -n "$expected_manifest" ]]; then
    warn "$name@$version install.manifest.json missing at $target"
    failures=$((failures + 1))
    continue
  fi

  ok "$name@$version verified"
done <<< "$TARGETS"

if [[ "$checked" -eq 0 ]]; then
  warn "No members to verify"
fi

if [[ "$failures" -gt 0 ]]; then
  die "$failures integrity verification failure(s)"
fi

ok "Integrity verification complete"
