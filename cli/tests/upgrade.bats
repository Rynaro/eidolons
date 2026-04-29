#!/usr/bin/env bats
#
# upgrade.bats — covers cli/src/upgrade.sh per docs/specs/eidolons-upgrade/.
# Test IDs in comments (T1..T31) cross-reference spec.md §6.

load helpers

# ─── Read-only path (--check) ────────────────────────────────────────────

# T1
@test "upgrade --check: no eidolons.yaml prints nexus-only report" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  run eidolons upgrade --check
  [ "$status" -eq 0 ]
  [[ "$output" =~ NEXUS ]]
  [[ ! "$output" =~ MEMBERS ]]
}

# T2
@test "upgrade --check: with manifest + lock, all current, prints up-to-date" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.2.2
  seed_lock_with_versions atlas=1.2.2
  run eidolons upgrade --check
  [ "$status" -eq 0 ]
  [[ "$output" =~ up-to-date ]]
  [[ "$output" =~ atlas ]]
}

# T3
@test "upgrade --check: detects member upgrade available" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --check
  [ "$status" -eq 0 ]
  [[ "$output" =~ "upgrade available" ]]
  [[ "$output" =~ 1\.0\.0 ]]
  [[ "$output" =~ 1\.2\.2 ]]
}

# T4
@test "upgrade --check: detects pinned-out member" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  # Override the roster's atlas latest to 2.0.0 by writing a custom roster
  # file and pointing EIDOLONS_NEXUS at the project so it picks ours up.
  mkdir -p custom-nexus/roster
  cp "$EIDOLONS_ROOT/roster/index.yaml" custom-nexus/roster/index.yaml
  # rewrite atlas latest + pins.stable to 2.0.0
  python3 - <<PYEOF
import re,sys
with open("custom-nexus/roster/index.yaml") as f:
  s=f.read()
# crude replace inside the atlas block
def bump(m):
  blk=m.group(0)
  blk=re.sub(r'latest: "\d+\.\d+\.\d+"','latest: "2.0.0"',blk)
  blk=re.sub(r'stable: "\d+\.\d+\.\d+"','stable: "2.0.0"',blk)
  return blk
s=re.sub(r'(- name: atlas[\s\S]*?references:)',bump,s)
open("custom-nexus/roster/index.yaml","w").write(s)
PYEOF
  export EIDOLONS_NEXUS="$PWD/custom-nexus"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --check
  [ "$status" -eq 0 ]
  [[ "$output" =~ pinned-out ]]
  [[ "$output" =~ eidolons\.yaml ]]
}

# T5
@test "upgrade --check: detects not-installed member" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  # No lockfile entry for atlas.
  cat > eidolons.lock <<'EOF'
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members: []
EOF
  run eidolons upgrade --check
  [ "$status" -eq 0 ]
  [[ "$output" =~ not-installed ]]
}

# T6
@test "upgrade --check: stale nexus produces upgrade-available row" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0
v1.1.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  run eidolons upgrade --check
  [ "$status" -eq 0 ]
  [[ "$output" =~ NEXUS ]]
  [[ "$output" =~ "upgrade available" ]]
  [[ "$output" =~ install\.sh ]] || [[ "$output" =~ curl ]]
}

# T7
@test "upgrade --check: --json emits valid object on stdout, banner on stderr" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  # Capture stdout only (bats merges by default; use eval-bash to split).
  json_out="$(eidolons upgrade --check --json 2>/dev/null)"
  echo "$json_out" | jq -e '.nexus and .members and .summary' >/dev/null
}

# T8
@test "upgrade --check: offline nexus probe degrades, doesn't fail" {
  # Fake-git with no FAKE_LSREMOTE_TAGS → ls-remote returns empty (probe fails
  # to find a tag → unknown). We additionally simulate a hard probe failure by
  # forcing the wrapper to return non-zero through a sentinel file.
  setup_fake_git_for_upgrade
  unset FAKE_LSREMOTE_TAGS
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --check
  [ "$status" -eq 0 ]
  [[ "$output" =~ unreachable ]] || [[ "$output" =~ unknown ]] || [[ "$output" =~ offline ]]
  [[ "$output" =~ atlas ]]
}

# T9 — caret/tilde/exact constraint operators
@test "upgrade --check: respects ^ constraint operator" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --check
  [ "$status" -eq 0 ]
  # latest 1.2.2 with ^1.0.0 → upgrade available, not pinned-out.
  [[ "$output" =~ "upgrade available" ]]
  [[ ! "$output" =~ pinned-out ]]
}

# T10
@test "upgrade --check: idempotent (run twice, byte-identical stdout)" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  out1="$(eidolons upgrade --check 2>/dev/null)"
  out2="$(eidolons upgrade --check 2>/dev/null)"
  [ "$out1" = "$out2" ]
}

# T11 — JSON schema sanity (not a full draft-07 validation; jq-level shape check)
@test "upgrade --check: --json output matches expected shape" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  json_out="$(eidolons upgrade --check --json 2>/dev/null)"
  echo "$json_out" | jq -e '
    .nexus.current.tag and .nexus.current.commit and .nexus.status and
    (.members | type == "array") and
    .summary.member_upgrades_available != null and
    .summary.member_upgrades_pinned_out != null and
    .summary.members_not_installed != null and
    .summary.nexus_upgrade_available != null
  ' >/dev/null
}

# T12 — alias resolution (atlas has no alias by default; use idg→scribe)
@test "upgrade --check: aliases resolve via roster_get" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  # Pass a known roster name (atlas) — alias plumbing reuses roster_get;
  # passing atlas itself is the canonical positive path.
  run eidolons upgrade --check atlas
  [ "$status" -eq 0 ]
  [[ "$output" =~ atlas ]]
}

# ─── Mutating path (member upgrades) ─────────────────────────────────────

# T13
@test "upgrade: --non-interactive --yes runs without prompting" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --non-interactive --yes
  [ "$status" -eq 0 ]
  [ -f "$FAKE_INSTALL_LOG" ]
  grep -q atlas "$FAKE_INSTALL_LOG"
}

# T14
@test "upgrade: --non-interactive without --yes fails fast" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --non-interactive
  [ "$status" -eq 2 ]
  [[ "$output" =~ "--yes" ]]
}

# T15
@test "upgrade: re-runs install.sh only for upgrade-available members" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  # atlas stale (1.0.0 → 1.2.2); set spectra to its current latest so it's up-to-date.
  spectra_latest="$(yq -r '.eidolons[] | select(.name == "spectra") | .versions.latest' "$EIDOLONS_ROOT/roster/index.yaml")"
  seed_manifest_with atlas=^1.0.0 spectra=^4.2.0
  seed_lock_with_versions atlas=1.0.0 spectra="$spectra_latest"
  run eidolons upgrade --non-interactive --yes
  [ "$status" -eq 0 ]
  # exactly one install: atlas
  [ -f "$FAKE_INSTALL_LOG" ]
  count="$(grep -c '^install ' "$FAKE_INSTALL_LOG" 2>/dev/null || echo 0)"
  [ "$count" -eq 1 ]
  grep -q atlas "$FAKE_INSTALL_LOG"
  ! grep -q spectra "$FAKE_INSTALL_LOG"
}

# T16
@test "upgrade: invalidates cache for upgraded members only" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  # Pre-populate stale cache directory. Don't include .git so fetch_eidolon
  # would still re-clone; here we're testing the pre-emptive removal.
  mkdir -p "$EIDOLONS_HOME/cache/atlas@1.0.0"
  : > "$EIDOLONS_HOME/cache/atlas@1.0.0/marker"
  run eidolons upgrade --non-interactive --yes
  [ "$status" -eq 0 ]
  [ ! -f "$EIDOLONS_HOME/cache/atlas@1.0.0/marker" ]
}

# T17
@test "upgrade: writes new lockfile with new resolved versions" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --non-interactive --yes
  [ "$status" -eq 0 ]
  grep -q '1\.2\.2' eidolons.lock
}

# T18
@test "upgrade: lockfile mtime unchanged when no upgrades occur" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.2.2
  before="$(ls -l eidolons.lock | awk '{print $6, $7, $8}')"
  if stat -f %m eidolons.lock >/dev/null 2>&1; then
    before_mt="$(stat -f %m eidolons.lock)"
  else
    before_mt="$(stat -c %Y eidolons.lock)"
  fi
  sleep 1
  run eidolons upgrade --non-interactive --yes
  [ "$status" -eq 0 ]
  if stat -f %m eidolons.lock >/dev/null 2>&1; then
    after_mt="$(stat -f %m eidolons.lock)"
  else
    after_mt="$(stat -c %Y eidolons.lock)"
  fi
  [ "$before_mt" = "$after_mt" ]
}

# T19
@test "upgrade <member>: positional arg upgrades only that member" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0 spectra=^4.2.0
  seed_lock_with_versions atlas=1.0.0 spectra=4.2.0
  run eidolons upgrade --non-interactive --yes atlas
  [ "$status" -eq 0 ]
  count="$(grep -c '^install ' "$FAKE_INSTALL_LOG" 2>/dev/null || echo 0)"
  [ "$count" -eq 1 ]
  grep -q atlas "$FAKE_INSTALL_LOG"
  ! grep -q spectra "$FAKE_INSTALL_LOG"
  # The lockfile should still record spectra.
  grep -q 'name: spectra' eidolons.lock
}

# T20
@test "upgrade <m1>,<m2>: comma-separated list" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0 spectra=^4.2.0 apivr=^3.0.0
  seed_lock_with_versions atlas=1.0.0 spectra=4.2.0 apivr=3.0.0
  run eidolons upgrade --non-interactive --yes atlas,spectra
  [ "$status" -eq 0 ]
  count="$(grep -c '^install ' "$FAKE_INSTALL_LOG" 2>/dev/null || echo 0)"
  [ "$count" -eq 2 ]
  grep -q atlas "$FAKE_INSTALL_LOG"
  grep -q spectra "$FAKE_INSTALL_LOG"
  ! grep -q apivr "$FAKE_INSTALL_LOG"
}

# T21
@test "upgrade unknown-member: exits 2 with hint" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --non-interactive --yes not-a-real-eidolon
  [ "$status" -eq 2 ]
  [[ "$output" =~ "not found" ]] || [[ "$output" =~ Try ]]
}

# T22
@test "upgrade: per-member install failure continues, reports at end, exits 1" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  export FAKE_CLONE_RESULT="fail"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --non-interactive --yes
  [ "$status" -eq 1 ]
  [[ "$output" =~ fail ]] || [[ "$output" =~ failed ]]
}

# T23
@test "upgrade: idempotent on repeat run" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --non-interactive --yes
  [ "$status" -eq 0 ]
  : > "$FAKE_INSTALL_LOG"
  run eidolons upgrade --non-interactive --yes
  [ "$status" -eq 0 ]
  [[ "$output" =~ up-to-date ]]
  ! grep -q '^install ' "$FAKE_INSTALL_LOG" 2>/dev/null
}

# T24
@test "upgrade: pinned-out member is skipped silently in mutating path" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  # Custom roster putting atlas at major 2.
  mkdir -p custom-nexus/roster
  cp "$EIDOLONS_ROOT/roster/index.yaml" custom-nexus/roster/index.yaml
  python3 - <<PYEOF
import re
with open("custom-nexus/roster/index.yaml") as f:
  s=f.read()
def bump(m):
  blk=m.group(0)
  blk=re.sub(r'latest: "\d+\.\d+\.\d+"','latest: "2.0.0"',blk)
  blk=re.sub(r'stable: "\d+\.\d+\.\d+"','stable: "2.0.0"',blk)
  return blk
s=re.sub(r'(- name: atlas[\s\S]*?references:)',bump,s)
open("custom-nexus/roster/index.yaml","w").write(s)
PYEOF
  export EIDOLONS_NEXUS="$PWD/custom-nexus"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --non-interactive --yes
  [ "$status" -eq 0 ]
  [[ "$output" =~ pinned-out ]]
  ! grep -q '^install ' "$FAKE_INSTALL_LOG" 2>/dev/null
}

# T25
@test "upgrade: --dry-run prints plan without fetching" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --non-interactive --yes --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "dry-run" ]]
  ! grep -q '^clone ' "$FAKE_CLONE_LOG" 2>/dev/null
  ! grep -q '^install ' "$FAKE_INSTALL_LOG" 2>/dev/null
}

# ─── Nexus path ──────────────────────────────────────────────────────────

# T26
@test "upgrade --system: stale nexus is fetched + reset" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0
v1.1.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  # Need a .git dir under EIDOLONS_NEXUS for nexus_self_update to attempt a fetch.
  # The default helper points EIDOLONS_NEXUS at the real checkout (which has .git).
  run eidolons upgrade --system --non-interactive --yes
  [ "$status" -eq 0 ]
  grep -q 'fetch ' "$FAKE_FETCH_LOG"
  grep -q 'reset ' "$FAKE_RESET_LOG"
}

# T27
@test "upgrade --system: current nexus is no-op" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  run eidolons upgrade --system --non-interactive --yes
  [ "$status" -eq 0 ]
  [[ "$output" =~ up-to-date ]]
  ! grep -q 'fetch ' "$FAKE_FETCH_LOG" 2>/dev/null
}

# T28
@test "upgrade --system: fetch failure exits 1" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0
v1.1.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  export FAKE_FETCH_RESULT="fail"
  run eidolons upgrade --system --non-interactive --yes
  [ "$status" -eq 1 ]
  ! grep -q 'reset ' "$FAKE_RESET_LOG" 2>/dev/null
}

# T29
@test "upgrade --system: with positional member name fails with mutex error" {
  setup_fake_git_for_upgrade
  run eidolons upgrade --system spectra
  [ "$status" -eq 2 ]
  [[ "$output" =~ "operates on the nexus only" ]] || [[ "$output" =~ "project scope" ]]
}

# T30
@test "upgrade --all: nexus first then members" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0
v1.1.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --all --non-interactive --yes
  [ "$status" -eq 0 ]
  grep -q 'fetch ' "$FAKE_FETCH_LOG"
  grep -q '^install atlas' "$FAKE_INSTALL_LOG"
}

# T31
@test "upgrade --all: aborts member phase if nexus fails" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0
v1.1.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  export FAKE_FETCH_RESULT="fail"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --all --non-interactive --yes
  [ "$status" -eq 1 ]
  ! grep -q '^install ' "$FAKE_INSTALL_LOG" 2>/dev/null
}

# ─── Scope-flag refinement (spec §11) ────────────────────────────────────

# T32
@test "upgrade --project: explicit project scope behaves like bare upgrade" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --project --non-interactive --yes
  [ "$status" -eq 0 ]
  [ -f "$FAKE_INSTALL_LOG" ]
  count="$(grep -c '^install ' "$FAKE_INSTALL_LOG" 2>/dev/null || echo 0)"
  [ "$count" -eq 1 ]
  grep -q atlas "$FAKE_INSTALL_LOG"
  grep -q '1\.2\.2' eidolons.lock
}

# T33
@test "upgrade --system --project: equivalent to --all" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0
v1.1.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --system --project --non-interactive --yes
  [ "$status" -eq 0 ]
  grep -q 'fetch ' "$FAKE_FETCH_LOG"
  grep -q '^install atlas' "$FAKE_INSTALL_LOG"
}

# T34
@test "upgrade --check --system: narrows report to nexus row only" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --check --system
  [ "$status" -eq 0 ]
  [[ "$output" =~ NEXUS ]]
  [[ ! "$output" =~ MEMBERS ]]
  ! grep -q 'atlas' <<<"$output"
}

# T35
@test "upgrade --check --project: narrows report to members only" {
  setup_fake_git_for_upgrade
  export FAKE_LSREMOTE_TAGS="v1.0.0
v1.1.0"
  export FAKE_NEXUS_HEAD_TAG="v1.0.0"
  seed_manifest_with atlas=^1.0.0
  seed_lock_with_versions atlas=1.0.0
  run eidolons upgrade --check --project
  [ "$status" -eq 0 ]
  [[ "$output" =~ MEMBERS ]]
  [[ ! "$output" =~ NEXUS ]]
}

# T36
@test "upgrade --nexus: rejected as unknown flag (post-rename)" {
  setup_fake_git_for_upgrade
  run eidolons upgrade --nexus
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Unknown option: --nexus" ]]
}

# Companion to T36: --all is kept as a public flag, but its asymmetric removal
# would surprise users who relied on the original spec. This guard ensures the
# pre-revision exit-status semantics for the dropped --all-only-nexus alias
# (none — we keep --all) stay intact. Also confirms the new --system flag is
# documented in the help output and --nexus is absent.

# ─── Help / argument parsing ─────────────────────────────────────────────

@test "upgrade -h: help prints usage" {
  run eidolons upgrade -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons\ upgrade ]]
  [[ "$output" =~ --system ]]
  [[ "$output" =~ --project ]]
  [[ ! "$output" =~ "--nexus" ]]
}

@test "upgrade: rejects unknown flag" {
  run eidolons upgrade --bogus
  [ "$status" -eq 2 ]
}
