#!/usr/bin/env bats
# cli/tests/verify_release.bats — VR-1..VR-12
#
# Tests for `eidolons verify-release` (Layer 2 methodology integrity).
# These tests run offline: setup_fake_git_for_upgrade stubs git clone so no
# network calls are made. Each test seeds its own lock + eidolons.yaml and
# a fake Eidolon cache that materialises an identical (or mutated) install tree.

load helpers

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Seed a minimal eidolons.yaml wiring claude-code.
seed_yaml_simple() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
  shared_dispatch: false
members:
  - name: atlas
    version: "1.7.1"
    source: github:Rynaro/ATLAS
EOF
}

# Seed a lock with one member (atlas@1.7.1).
seed_lock_atlas() {
  cat > eidolons.lock <<'EOF'
generated_at: "2026-05-26T00:00:00Z"
eidolons_cli_version: "1.12.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.7.1"
    resolved: "github:Rynaro/ATLAS@abc1234567890abcdef1234567890abcdef123456"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
}

# Seed a lock with two members (atlas@1.7.1 + spectra@4.5.1).
seed_lock_two_members() {
  cat > eidolons.lock <<'EOF'
generated_at: "2026-05-26T00:00:00Z"
eidolons_cli_version: "1.12.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.7.1"
    resolved: "github:Rynaro/ATLAS@abc1234567890abcdef1234567890abcdef123456"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
  - name: spectra
    version: "4.5.1"
    resolved: "github:Rynaro/SPECTRA@abc1234567890abcdef1234567890abcdef123456"
    target: "./.eidolons/spectra"
    hosts_wired: ["claude-code"]
EOF
}

# Materialise a fake cache at $CACHE_DIR/atlas@1.7.1 with a minimal install.sh
# that writes a fixed set of files into --target.
# The same content is then written to .eidolons/atlas/ (consumer side) so the
# comparison is clean (no drift).
seed_fake_atlas_cache_and_consumer() {
  local cache_dir="$EIDOLONS_HOME/cache/atlas@1.7.1"
  mkdir -p "$cache_dir/.git"
  # Write the stub install.sh into the fake cache.
  cat > "$cache_dir/install.sh" <<'STUB'
#!/usr/bin/env bash
# Stub installer for verify-release tests.
TGT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TGT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$TGT"
# Write a deterministic set of files.
printf 'atlas agent content' > "$TGT/agent.md"
printf 'atlas spec content'  > "$TGT/SPEC.md"
mkdir -p "$TGT/skills/locate"
printf 'locate skill'        > "$TGT/skills/locate/SKILL.md"
# Write the manifest (excluded from diff).
cat > "$TGT/install.manifest.json" <<JSON
{
  "name": "atlas",
  "version": "1.7.1",
  "hosts_wired": ["claude-code"],
  "files": []
}
JSON
exit 0
STUB
  chmod +x "$cache_dir/install.sh"

  # Write identical content to the consumer side.
  mkdir -p ".eidolons/atlas/skills/locate"
  printf 'atlas agent content' > ".eidolons/atlas/agent.md"
  printf 'atlas spec content'  > ".eidolons/atlas/SPEC.md"
  printf 'locate skill'        > ".eidolons/atlas/skills/locate/SKILL.md"
  # Consumer has an install.manifest.json (should be excluded from diff).
  cat > ".eidolons/atlas/install.manifest.json" <<JSON
{
  "name": "atlas",
  "version": "1.7.1",
  "hosts_wired": ["claude-code"],
  "files": []
}
JSON
}

# Materialise atlas cache + consumer identical to seed_fake_atlas_cache_and_consumer,
# PLUS a spectra cache/consumer pair.
seed_fake_spectra_cache_and_consumer() {
  local cache_dir="$EIDOLONS_HOME/cache/spectra@4.5.1"
  mkdir -p "$cache_dir/.git"
  cat > "$cache_dir/install.sh" <<'STUB'
#!/usr/bin/env bash
TGT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TGT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$TGT"
printf 'spectra agent content' > "$TGT/agent.md"
cat > "$TGT/install.manifest.json" <<JSON
{
  "name": "spectra",
  "version": "4.5.1",
  "hosts_wired": ["claude-code"],
  "files": []
}
JSON
exit 0
STUB
  chmod +x "$cache_dir/install.sh"
  mkdir -p ".eidolons/spectra"
  printf 'spectra agent content' > ".eidolons/spectra/agent.md"
  cat > ".eidolons/spectra/install.manifest.json" <<JSON
{
  "name": "spectra",
  "version": "4.5.1",
  "hosts_wired": ["claude-code"],
  "files": []
}
JSON
}

# ─── Tests ────────────────────────────────────────────────────────────────────

# VR-1: no eidolons.lock → die with message
@test "VR-1: verify-release with no lock dies cleanly" {
  seed_yaml_simple
  # No lock written.
  run eidolons verify-release
  [ "$status" -eq 1 ]
  [[ "$output" =~ "No eidolons.lock found" ]]
}

# VR-2: lock present but empty members → warn + exit 0
@test "VR-2: verify-release with empty lock warns and exits 0" {
  cat > eidolons.lock <<'EOF'
generated_at: "2026-05-26T00:00:00Z"
eidolons_cli_version: "1.12.0"
nexus_commit: "test"
members: []
EOF
  run eidolons verify-release
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No members in eidolons.lock" ]]
}

# VR-3: all members clean → exit 0, "verified" in output
@test "VR-3: verify-release: all members verified clean exits 0" {
  seed_yaml_simple
  seed_lock_atlas
  seed_fake_atlas_cache_and_consumer
  run eidolons verify-release
  [ "$status" -eq 0 ]
  [[ "$output" =~ "verified" ]]
}

# VR-4: tampered file → DIFFER reported (no --strict → exit 0)
@test "VR-4: verify-release: tampered file reports DIFFER, exit 0 without --strict" {
  seed_yaml_simple
  seed_lock_atlas
  seed_fake_atlas_cache_and_consumer
  # Mutate one file on the consumer side.
  printf 'tampered content' > ".eidolons/atlas/agent.md"
  run eidolons verify-release
  [ "$status" -eq 0 ]
  [[ "$output" =~ "DIFFER" ]]
}

# VR-5: tampered file + --strict → exit 1
@test "VR-5: verify-release --strict: tampered file exits 1" {
  seed_yaml_simple
  seed_lock_atlas
  seed_fake_atlas_cache_and_consumer
  printf 'tampered content' > ".eidolons/atlas/agent.md"
  run eidolons verify-release --strict
  [ "$status" -eq 1 ]
  [[ "$output" =~ "DIFFER" ]]
}

# VR-6: deleted file → MISSING reported
@test "VR-6: verify-release: deleted file reports MISSING" {
  seed_yaml_simple
  seed_lock_atlas
  seed_fake_atlas_cache_and_consumer
  rm ".eidolons/atlas/SPEC.md"
  run eidolons verify-release
  [ "$status" -eq 0 ]
  [[ "$output" =~ "MISSING" ]]
}

# VR-7: extra user file → EXTRA reported
@test "VR-7: verify-release: extra user file reports EXTRA" {
  seed_yaml_simple
  seed_lock_atlas
  seed_fake_atlas_cache_and_consumer
  printf 'my notes' > ".eidolons/atlas/user-note.md"
  run eidolons verify-release
  [ "$status" -eq 0 ]
  [[ "$output" =~ "EXTRA" ]]
}

# VR-8: --eidolon atlas with two-member lock → only atlas verified, spectra absent
@test "VR-8: verify-release --eidolon atlas scopes to single member" {
  seed_lock_two_members
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
  shared_dispatch: false
members:
  - name: atlas
    version: "1.7.1"
    source: github:Rynaro/ATLAS
  - name: spectra
    version: "4.5.1"
    source: github:Rynaro/SPECTRA
EOF
  seed_fake_atlas_cache_and_consumer
  # spectra is NOT seeded — so if it were included it would error/drift.
  run eidolons verify-release --eidolon atlas
  [ "$status" -eq 0 ]
  # spectra should not appear in the output at all.
  [[ ! "$output" =~ "spectra" ]]
  [[ "$output" =~ "atlas" ]]
}

# VR-9: --eidolon unknown → die with "is not in eidolons.lock"
@test "VR-9: verify-release --eidolon unknown dies" {
  seed_yaml_simple
  seed_lock_atlas
  run eidolons verify-release --eidolon unknownmember
  [ "$status" -eq 1 ]
  [[ "$output" =~ "is not in eidolons.lock" ]]
}

# VR-10: --no-fetch with no cache → die with cache-miss hint
@test "VR-10: verify-release --no-fetch with missing cache dies with hint" {
  seed_yaml_simple
  seed_lock_atlas
  # No cache seeded (EIDOLONS_HOME is a fresh tmpdir from helpers.bash).
  run eidolons verify-release --no-fetch
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Cache for atlas@1.7.1 missing" ]]
  [[ "$output" =~ "Run without --no-fetch" ]]
}

# VR-11: --json emits parseable JSON with expected schema
@test "VR-11: verify-release --json emits parseable JSON" {
  seed_yaml_simple
  seed_lock_atlas
  seed_fake_atlas_cache_and_consumer
  run eidolons verify-release --json
  [ "$status" -eq 0 ]
  # stdout should be valid JSON with expected keys.
  echo "$output" | jq -e '.summary.verified' >/dev/null
  echo "$output" | jq -e '.members[0].name' >/dev/null
  echo "$output" | jq -e '.members[0].status' >/dev/null
  # Verify schema shape.
  _name="$(echo "$output" | jq -r '.members[0].name')"
  [ "$_name" = "atlas" ]
  _status="$(echo "$output" | jq -r '.members[0].status')"
  [ "$_status" = "ok" ]
}

# VR-12: install.manifest.json mutations excluded from diff (0 drift)
@test "VR-12: verify-release: install.manifest.json excluded from diff" {
  seed_yaml_simple
  seed_lock_atlas
  seed_fake_atlas_cache_and_consumer
  # Mutate ONLY the manifest on the consumer side.
  cat > ".eidolons/atlas/install.manifest.json" <<JSON
{
  "name": "atlas",
  "version": "1.7.1",
  "installed_at": "2099-01-01T00:00:00Z",
  "hosts_wired": ["claude-code"],
  "files": ["mutated-extra-field"]
}
JSON
  run eidolons verify-release
  [ "$status" -eq 0 ]
  # Should show 0 drift (manifest excluded).
  [[ "$output" =~ "0 drift" ]]
  # No DIFFER/MISSING/EXTRA lines.
  [[ ! "$output" =~ "DIFFER" ]]
  [[ ! "$output" =~ "MISSING" ]]
  [[ ! "$output" =~ "EXTRA" ]]
}
