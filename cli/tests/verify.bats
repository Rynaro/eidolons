#!/usr/bin/env bats

load helpers

add_atlas_release_metadata() {
  local version="$1" commit="$2" tree="$3"
  mkdir -p custom-nexus/roster
  cp "$EIDOLONS_ROOT/roster/index.yaml" custom-nexus/roster/index.yaml
  python3 - "$version" "$commit" "$tree" <<'PY'
import sys
from pathlib import Path

version, commit, tree = sys.argv[1:4]
path = Path("custom-nexus/roster/index.yaml")
text = path.read_text()
needle = '''    versions:
      latest: "1.0.5"
      pins:
        stable: "1.0.5"
'''
replacement = f'''    versions:
      latest: "1.0.5"
      pins:
        stable: "1.0.5"
      releases:
        "{version}":
          tag: "v{version}"
          commit: "{commit}"
          tree: "{tree}"
          archive_sha256: null
          manifest_sha256: null
          provenance:
            github_attestation: false
            workflow: ".github/workflows/release.yml"
'''
text = text.replace(needle, replacement, 1)
path.write_text(text)
PY
  export EIDOLONS_NEXUS="$PWD/custom-nexus"
}

write_lock_with_integrity() {
  local version="$1" commit="$2" tree="$3"
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
    archive_sha256: ""
    manifest_sha256: ""
    verification: "verified"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
}

@test "verify: legacy roster metadata warns but passes in compatibility mode" {
  seed_lock_with_versions atlas=1.0.0
  run eidolons verify
  [ "$status" -eq 0 ]
  [[ "$output" =~ legacy ]]
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
