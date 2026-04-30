#!/usr/bin/env bats

load helpers

add_atlas_release_metadata() {
  local version="$1" commit="$2" tree="$3"
  local archive_sha="${4:-}" manifest_sha="${5:-}"
  mkdir -p custom-nexus/roster
  cp "$EIDOLONS_ROOT/roster/index.yaml" custom-nexus/roster/index.yaml
  python3 - "$version" "$commit" "$tree" "$archive_sha" "$manifest_sha" <<'PY'
import re
import sys
from pathlib import Path

version, commit, tree, archive_sha, manifest_sha = sys.argv[1:6]
path = Path("custom-nexus/roster/index.yaml")
text = path.read_text()

# Anchor: atlas's versions block. After PR #40 landed on main, the roster
# already contains a `releases:` block under atlas; we must strip it (and
# any other existing 6-space-indented siblings of `pins:`) before
# inserting our test-only fixture, otherwise YAML emits two `releases:`
# keys at the same level and the second-load-wins rule overrides our
# fixture with the real metadata.
versions_anchor = '''    versions:
      latest: "1.2.2"
      pins:
        stable: "1.2.2"
'''
if versions_anchor not in text:
    raise SystemExit("verify.bats helper: atlas versions anchor not found in roster")

# Capture from the end of the anchor up to (but not including) the next
# 4-space-indented sibling key under atlas (e.g. `    install:` or
# `    handoffs:`). Anything in that range is currently a child of
# `versions:` — we drop it, then rebuild with only `pins:` + the test's
# `releases:`.
end_of_anchor = text.index(versions_anchor) + len(versions_anchor)
next_sibling = re.search(r"^    [a-z_]+:\s*$", text[end_of_anchor:], re.MULTILINE)
stop = end_of_anchor + next_sibling.start() if next_sibling else len(text)

archive_value = f'"{archive_sha}"' if archive_sha else 'null'
manifest_value = f'"{manifest_sha}"' if manifest_sha else 'null'
new_releases = f'''      releases:
        "{version}":
          tag: "v{version}"
          commit: "{commit}"
          tree: "{tree}"
          archive_sha256: {archive_value}
          manifest_sha256: {manifest_value}
          provenance:
            github_attestation: false
            workflow: ".github/workflows/release.yml"
'''
text = text[:end_of_anchor] + new_releases + text[stop:]
path.write_text(text)
PY
  export EIDOLONS_NEXUS="$PWD/custom-nexus"
}

# Set the roster integrity.enforcement override to a value we control.
# Use this for strict-mode coverage.
override_integrity_enforcement() {
  export EIDOLONS_INTEGRITY_ENFORCEMENT="$1"
}

write_lock_with_integrity() {
  local version="$1" commit="$2" tree="$3"
  local archive_sha="${4:-}" manifest_sha="${5:-}"
  cat > eidolons.lock <<EOF
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "$version"
    resolved: "github:Rynaro/ATLAS@$commit"
    commit: "$commit"
    tree: "$tree"
    archive_sha256: "$archive_sha"
    manifest_sha256: "$manifest_sha"
    verification: "verified"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
}

# Materialize an installed Eidolon at ./.eidolons/<name>/install.manifest.json
# whose SHA-256 is deterministic (callers pass the version string only).
seed_atlas_install_manifest() {
  local version="$1"
  mkdir -p ".eidolons/atlas"
  cat > ".eidolons/atlas/install.manifest.json" <<EOF
{
  "name": "atlas",
  "version": "$version",
  "hosts_wired": ["claude-code"],
  "files": []
}
EOF
}

# Compute the SHA-256 of the file we just wrote — used by tests that need
# the lock's manifest_sha256 to match (or deliberately not match) disk.
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

@test "verify: legacy roster metadata warns but passes in compatibility mode" {
  seed_lock_with_versions atlas=1.0.0
  run eidolons verify
  [ "$status" -eq 0 ]
  [[ "$output" =~ "compatibility verification is warning-only" ]]
  [[ "$output" =~ "Integrity verification complete" ]]
}

@test "verify: release metadata match passes" {
  commit="abc1234567890abcdef1234567890abcdef123456"
  tree="abc1234567890abcdef1234567890abcdef123456"
  add_atlas_release_metadata "1.0.0" "$commit" "$tree"
  write_lock_with_integrity "1.0.0" "$commit" "$tree"
  run eidolons verify atlas
  [ "$status" -eq 0 ]
  [[ "$output" =~ "atlas@1.0.0 verified" ]]
}

@test "verify: commit mismatch fails" {
  add_atlas_release_metadata "1.0.0" \
    "1111111111111111111111111111111111111111" \
    "abc1234567890abcdef1234567890abcdef123456"
  write_lock_with_integrity "1.0.0" \
    "abc1234567890abcdef1234567890abcdef123456" \
    "abc1234567890abcdef1234567890abcdef123456"
  run eidolons verify atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ "commit mismatch" ]]
}

@test "sync: opted-in release metadata commit mismatch aborts before install" {
  setup_fake_git_for_upgrade
  add_atlas_release_metadata "1.0.0" \
    "1111111111111111111111111111111111111111" \
    "abc1234567890abcdef1234567890abcdef123456"
  seed_manifest_with atlas=^1.0.0
  run eidolons sync --yes
  [ "$status" -ne 0 ]
  [[ "$output" =~ "commit mismatch" ]]
  [ ! -f "$FAKE_INSTALL_LOG" ] || ! grep -q atlas "$FAKE_INSTALL_LOG"
}

# ─── Negative-path coverage (Story 5.L) ───────────────────────────────────

@test "verify: tree mismatch fails" {
  commit="abc1234567890abcdef1234567890abcdef123456"
  add_atlas_release_metadata "1.0.0" "$commit" \
    "2222222222222222222222222222222222222222"
  write_lock_with_integrity "1.0.0" "$commit" \
    "abc1234567890abcdef1234567890abcdef123456"
  run eidolons verify atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ "tree mismatch" ]]
}

@test "verify: archive checksum mismatch fails" {
  commit="abc1234567890abcdef1234567890abcdef123456"
  tree="abc1234567890abcdef1234567890abcdef123456"
  expected_archive="1111111111111111111111111111111111111111111111111111111111111111"
  lock_archive="2222222222222222222222222222222222222222222222222222222222222222"
  add_atlas_release_metadata "1.0.0" "$commit" "$tree" "$expected_archive"
  write_lock_with_integrity "1.0.0" "$commit" "$tree" "$lock_archive"
  run eidolons verify atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ "archive checksum mismatch" ]]
}

@test "verify: installed manifest changed since lock fails" {
  commit="abc1234567890abcdef1234567890abcdef123456"
  tree="abc1234567890abcdef1234567890abcdef123456"
  add_atlas_release_metadata "1.0.0" "$commit" "$tree"
  # Lock claims a manifest hash; on-disk manifest will hash to something else.
  fake_lock_hash="dead0beefdead0beefdead0beefdead0beefdead0beefdead0beefdead0beef0"
  write_lock_with_integrity "1.0.0" "$commit" "$tree" "" "$fake_lock_hash"
  seed_atlas_install_manifest "1.0.0"
  run eidolons verify atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ "installed manifest changed" ]]
}

@test "verify: roster manifest_sha256 mismatch fails when manifest present" {
  commit="abc1234567890abcdef1234567890abcdef123456"
  tree="abc1234567890abcdef1234567890abcdef123456"
  expected_manifest="cafe0babecafe0babecafe0babecafe0babecafe0babecafe0babecafe0babe0"
  add_atlas_release_metadata "1.0.0" "$commit" "$tree" "" "$expected_manifest"
  seed_atlas_install_manifest "1.0.0"
  # Lock keeps manifest_sha256 empty so "installed-manifest-changed" check is skipped.
  write_lock_with_integrity "1.0.0" "$commit" "$tree" "" ""
  run eidolons verify atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ "manifest checksum mismatch" ]]
}

@test "verify: missing install.manifest.json fails when roster pins manifest_sha256" {
  commit="abc1234567890abcdef1234567890abcdef123456"
  tree="abc1234567890abcdef1234567890abcdef123456"
  expected_manifest="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  add_atlas_release_metadata "1.0.0" "$commit" "$tree" "" "$expected_manifest"
  write_lock_with_integrity "1.0.0" "$commit" "$tree"
  # Note: no .eidolons/atlas/install.manifest.json on disk.
  run eidolons verify atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ "install.manifest.json missing" ]]
}

@test "verify: missing member in lockfile fails" {
  seed_lock_with_versions atlas=1.0.0
  run eidolons verify spectra
  [ "$status" -ne 0 ]
  [[ "$output" =~ "spectra is not present in eidolons.lock" ]]
}

@test "verify: strict enforcement without metadata fails" {
  override_integrity_enforcement strict
  seed_lock_with_versions atlas=1.0.0
  run eidolons verify atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ "missing roster release integrity metadata" ]]
}

@test "verify: no eidolons.lock present fails fast" {
  run eidolons verify
  [ "$status" -ne 0 ]
  [[ "$output" =~ "No eidolons.lock found" ]]
}
