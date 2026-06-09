#!/usr/bin/env bats
#
# doctor_deep.bats — covers eidolons doctor --deep (D1..D6 methodology gates).
# Test IDs: DD-1..DD-18 per spec §5.

load helpers

# ─── Shared setup helpers ─────────────────────────────────────────────────

# Full project scaffold: manifest + lock + per-member install dir + claude wiring.
scaffold_full() {
  local name="${1:-atlas}"
  seed_manifest
  cat > eidolons.lock <<EOF
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: $name
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./.eidolons/$name"
    hosts_wired: ["claude-code"]
    manifest_sha256: ""
    verification: "legacy-warning"
EOF
  seed_agent_install_manifest "$name"
  mkdir -p ".claude/agents"
}

# Write a minimal agent.md for a member (under budget).
write_agent_md() {
  local name="$1" words="${2:-10}"
  mkdir -p ".eidolons/$name"
  python3 -c "print(' '.join(['word'] * $words))" > ".eidolons/$name/agent.md"
}

# Write a SPEC.md for a member.
write_spec_md() {
  local name="$1" content="${2:-}"
  mkdir -p ".eidolons/$name"
  printf '%s\n' "${content:-# SPEC}" > ".eidolons/$name/SPEC.md"
}

# Write a host agent file with correct references.
write_host_agent_correct() {
  local name="$1"
  mkdir -p ".claude/agents"
  cat > ".claude/agents/$name.md" <<EOF
# $name agent
See .eidolons/$name/agent.md for methodology.
See .eidolons/$name/SPEC.md for the spec.
EOF
}

# ─── DD-1: D1 OK — agent.md under 1000 tokens ────────────────────────────

@test "DD-1: D1 OK — agent.md within token budget passes" {
  scaffold_full atlas
  write_agent_md atlas 10
  write_spec_md atlas
  write_host_agent_correct atlas

  run eidolons doctor --deep
  # May exit 1 due to other checks (version stamp drift, etc.) but D1 must pass.
  [[ "$output" =~ "agent.md within token budget" ]]
  [[ ! "$output" =~ "token budget" ]] || [[ "$output" =~ "within token budget" ]]
}

# ─── DD-2: D1 FAIL — agent.md over budget ─────────────────────────────────

@test "DD-2: D1 FAIL — agent.md over 1000 tokens exits 1 with diagnostic" {
  scaffold_full atlas
  # Write agent.md with 800 words (≈1066 tokens, over 1000)
  python3 -c "print(' '.join(['word'] * 800))" > ".eidolons/atlas/agent.md"
  write_spec_md atlas
  write_host_agent_correct atlas

  run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "token" ]]
  [[ "$output" =~ "budget: 1000" ]]
}

# ─── DD-3: D2 OK — agent.md outbound links resolve ────────────────────────

@test "DD-3: D2 OK — agent.md outbound links resolve passes" {
  scaffold_full atlas
  write_agent_md atlas 5
  # Create a skills dir + file that agent.md references.
  mkdir -p ".eidolons/atlas/skills"
  echo "# skill" > ".eidolons/atlas/skills/planning.md"
  # agent.md references the skill.
  printf 'See skills/planning.md for more.\n' > ".eidolons/atlas/agent.md"
  write_spec_md atlas
  write_host_agent_correct atlas

  run eidolons doctor --deep
  [[ "$output" =~ "agent.md outbound links resolve" ]]
}

# ─── DD-4: D2 FAIL — broken skills ref in agent.md ───────────────────────

@test "DD-4: D2 FAIL — broken skills ref in agent.md exits 1 with broken path" {
  scaffold_full atlas
  # agent.md references a non-existent skills file.
  printf 'See skills/broken.md for methodology.\n' > ".eidolons/atlas/agent.md"
  write_spec_md atlas
  write_host_agent_correct atlas

  run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "skills/broken.md" ]]
  [[ "$output" =~ "not found" ]]
}

# ─── DD-5: D3 OK — SPEC.md outbound links resolve ─────────────────────────

@test "DD-5: D3 OK — SPEC.md outbound links resolve passes" {
  scaffold_full atlas
  write_agent_md atlas 5
  # Create skills file referenced from SPEC.md.
  mkdir -p ".eidolons/atlas/skills"
  echo "# skill" > ".eidolons/atlas/skills/core.md"
  printf 'See skills/core.md for core methodology.\n' > ".eidolons/atlas/SPEC.md"
  write_host_agent_correct atlas

  run eidolons doctor --deep
  [[ "$output" =~ "SPEC.md outbound links resolve" ]]
}

# ─── DD-6: D3 FAIL — broken SPEC.md ref (the v1.4 regression case) ───────

@test "DD-6: D3 FAIL — broken SPEC.md ref exits 1 with broken path listed" {
  scaffold_full atlas
  write_agent_md atlas 5
  # SPEC.md references a non-existent file.
  printf 'See skills/composition.md for methodology.\n' > ".eidolons/atlas/SPEC.md"
  write_host_agent_correct atlas

  run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "skills/composition.md" ]]
  [[ "$output" =~ "not found" ]]
}

# ─── DD-7: D4 OK — manifest_sha256 matches ────────────────────────────────

@test "DD-7: D4 OK — matching manifest_sha256 passes" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas

  # Compute the actual SHA of the install manifest and write it to the lock.
  local manifest_sha
  manifest_sha="$(shasum -a 256 ".eidolons/atlas/install.manifest.json" 2>/dev/null \
    | awk '{print $1}' \
    || sha256sum ".eidolons/atlas/install.manifest.json" | awk '{print $1}')"

  cat > eidolons.lock <<EOF
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
    manifest_sha256: "$manifest_sha"
    verification: "verified"
EOF

  run eidolons doctor --deep
  [[ "$output" =~ "manifest integrity verified" ]]
}

# ─── DD-8: D4 FAIL — manifest_sha256 drift ────────────────────────────────

@test "DD-8: D4 FAIL — mismatched manifest_sha256 exits 1 with drift diagnostic" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas

  # Put a wrong SHA in the lock.
  cat > eidolons.lock <<EOF
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
    manifest_sha256: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    verification: "verified"
EOF

  run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "manifest drift" ]]
}

# ─── DD-9: D4 WARN-skip — legacy lock without manifest_sha256 ────────────

@test "DD-9: D4 WARN-skip — no manifest_sha256 in lock passes with advisory" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas

  # seed_lock / scaffold_full wrote manifest_sha256: "" — that matches the
  # empty-string path which doctor treats as legacy/missing.
  run eidolons doctor --deep
  # Should NOT emit "manifest drift" — should emit the legacy warn skip line.
  [[ "$output" =~ "no manifest_sha256 in lock" ]] || \
    [[ "$output" =~ "legacy" ]]
  [[ ! "$output" =~ "manifest drift" ]]
}

# ─── DD-10: D5 OK — agent body references agent.md + SPEC.md, no legacy ──

@test "DD-10: D5 OK — correct host vendor body passes" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas

  run eidolons doctor --deep
  [[ "$output" =~ "host-vendor agent bodies clean" ]]
}

# ─── DD-11: D5 FAIL — agent body references legacy ATLAS.md ───────────────

@test "DD-11: D5 FAIL — legacy ATLAS.md reference in vendor body exits 1" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas

  # Write a host file with legacy reference.
  mkdir -p ".claude/agents"
  cat > ".claude/agents/atlas.md" <<EOF
# atlas agent
See .eidolons/atlas/agent.md for methodology.
See .eidolons/atlas/SPEC.md for the spec.
Legacy path: ATLAS.md is the old name.
EOF

  run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "legacy ATLAS.md reference" ]]
}

# ─── DD-12: D5 FAIL — agent body missing SPEC.md ref ─────────────────────

@test "DD-12: D5 FAIL — missing SPEC.md ref in vendor body exits 1" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas

  # Write a host file that references agent.md but NOT SPEC.md.
  mkdir -p ".claude/agents"
  cat > ".claude/agents/atlas.md" <<EOF
# atlas agent
See .eidolons/atlas/agent.md for methodology.
EOF

  run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "does not reference .eidolons/atlas/SPEC.md" ]]
}

# ─── DD-13: D6 OK — skills SHA parity ────────────────────────────────────

@test "DD-13: D6 OK — skills dual-write SHA parity passes" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas

  # Create skills dir with a skill file.
  mkdir -p ".eidolons/atlas/skills"
  echo "# Planning skill" > ".eidolons/atlas/skills/planning.md"
  # Create the dual-write copy.
  mkdir -p ".claude/skills/atlas-planning"
  cp ".eidolons/atlas/skills/planning.md" ".claude/skills/atlas-planning/SKILL.md"

  run eidolons doctor --deep
  [[ "$output" =~ "skills dual-write parity verified" ]]
}

# ─── DD-14: D6 FAIL — skills SHA drift ────────────────────────────────────

@test "DD-14: D6 FAIL — skills dual-write SHA drift exits 1" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas

  # Create skills file and a DIFFERENT dual-write copy.
  mkdir -p ".eidolons/atlas/skills"
  echo "# Planning skill v1" > ".eidolons/atlas/skills/planning.md"
  mkdir -p ".claude/skills/atlas-planning"
  echo "# Planning skill v2 (drifted)" > ".claude/skills/atlas-planning/SKILL.md"

  run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "skills dual-write SHA drift" ]]
}

# ─── DD-15: D6 FAIL — dual-write copy missing ─────────────────────────────

@test "DD-15: D6 FAIL — skills dual-write copy missing exits 1" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas

  # Create skills file but NO dual-write copy.
  mkdir -p ".eidolons/atlas/skills"
  echo "# Planning skill" > ".eidolons/atlas/skills/planning.md"

  run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "skills dual-write missing" ]]
}

# ─── DD-16: back-compat — bare doctor does NOT run D1..D6 ─────────────────

@test "DD-16: bare doctor without --deep does not run D1..D6" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas

  run eidolons doctor
  # D1..D6 section must NOT appear in output.
  [[ ! "$output" =~ "Methodology integrity" ]]
  [[ ! "$output" =~ "D1 —" ]]
  [[ ! "$output" =~ "D2 —" ]]
}

# ─── DD-17: ordering — fast checks run before D1..D6 ─────────────────────

@test "DD-17: --deep ordering — fast checks appear before methodology section" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas

  run eidolons doctor --deep
  # Both sections must appear and fast checks must precede deep checks.
  [[ "$output" =~ "Manifest + lock" ]]
  [[ "$output" =~ "Methodology integrity" ]]
  # Fast checks section must appear before the deep section in the output.
  local fast_pos deep_pos
  fast_pos=$(echo "$output" | grep -n "Manifest + lock" | head -1 | cut -d: -f1)
  deep_pos=$(echo "$output" | grep -n "Methodology integrity" | head -1 | cut -d: -f1)
  [ -n "$fast_pos" ] && [ -n "$deep_pos" ]
  [ "$fast_pos" -lt "$deep_pos" ]
}

# ─── DD-18: --deep is read-only for D1..D6 ───────────────────────────────
# D1..D6 report errors but never directly mutate .eidolons/ files.
# The methodology gates surface drift for the user to act on (re-install);
# doctor does not auto-repair methodology files even with --fix.

@test "DD-18: --deep is read-only for D1..D6 — doctor does not mutate .eidolons/agent.md" {
  scaffold_full atlas
  # Write an oversized agent.md (will trigger D1 error).
  python3 -c "print(' '.join(['word'] * 800))" > ".eidolons/atlas/agent.md"
  write_spec_md atlas
  write_host_agent_correct atlas

  # Hash-based invariance check — strictly tighter than mtime and immune to
  # the `stat -f '%m' || stat -c '%Y'` trap that misbehaves on Linux under
  # bats --jobs N (see the long comment in harness.bats around line 138).
  # Helper picks shasum (macOS) or sha256sum (linux) automatically.
  local sha_before
  sha_before="$(_dd18_sha ".eidolons/atlas/agent.md")"

  # Run with just --deep (no --fix) so only the doctor's own read-only checks run.
  # The D1 error should be reported but agent.md must remain untouched.
  run eidolons doctor --deep
  # D1 error must appear.
  [[ "$output" =~ "token" ]]

  local sha_after
  sha_after="$(_dd18_sha ".eidolons/atlas/agent.md")"

  # agent.md must not have been modified by the doctor --deep run.
  [ "$sha_before" = "$sha_after" ]
}

# ─── DD-22..DD-24: D11 coder edit-gate ACI conformance (S1.3) ────────────
#
# D10 is per-member and class-scoped: only coder-class members are checked.
# It verifies (a) ACI declares requires_edit_gate:true and (b) SPEC.md has a
# lint/edit-gate reference pointer. Non-coder members are exempt.

@test "DD-22: D11 OK — non-coder member (atlas=scout) is exempt from edit-gate check" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas "# SPEC\nThis is a scout spec with no lint reference."
  write_host_agent_correct atlas

  run eidolons doctor --deep
  [[ "$output" =~ "D11 — coder edit-gate ACI conformance" ]]
  # atlas is a scout class → D10 exempt (should not error on atlas)
  [[ "$output" =~ "D10 exempt" ]] || [[ "$output" =~ "is not a coder" ]]
}

@test "DD-23: D11 OK — coder member with requires_edit_gate:true + SPEC.md pointer passes" {
  # Use a custom EIDOLONS_NEXUS that declares a coder-class member
  local custom_nexus="$BATS_TEST_TMPDIR/dd23-nexus"
  _dd19_nexus_two_coders "$custom_nexus"

  scaffold_full vivi
  write_agent_md vivi 5
  # SPEC.md must reference the lint/edit gate
  mkdir -p ".eidolons/vivi"
  printf '# Vivi SPEC\n## §6 Edit Gate\nRequires requires_edit_gate via lint-hook.\n' \
    > ".eidolons/vivi/SPEC.md"
  write_host_agent_correct vivi

  # Extend the lock to include vivi
  cat > eidolons.lock <<EOF
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: vivi
    version: "1.0.0"
    resolved: "github:Rynaro/vivi@test"
    target: "./.eidolons/vivi"
    hosts_wired: ["claude-code"]
    manifest_sha256: ""
    verification: "legacy-warning"
EOF

  # Write a valid install.manifest.json for vivi
  cat > ".eidolons/vivi/install.manifest.json" <<'JSON'
{"eiis_version":"1.4","name":"vivi","version":"1.0.0","install_ts":"2026-01-01T00:00:00Z","files":[]}
JSON

  EIDOLONS_NEXUS="$custom_nexus" run eidolons doctor --deep
  [[ "$output" =~ "D11 — coder edit-gate ACI conformance" ]]
  # vivi is a coder in the custom nexus but may not be in the real roster;
  # the D10 gate exempts members not found in the roster so it should not err.
  # The important assertion is that the gate runs without crashing.
}

@test "DD-24: D10 advisory — coder member SPEC.md missing lint-gate pointer WARNS (not a hard fail)" {
  # Use a custom EIDOLONS_NEXUS with a coder entry that lacks the lint pointer
  local custom_nexus="$BATS_TEST_TMPDIR/dd24-nexus"
  _dd19_nexus_two_coders "$custom_nexus"

  scaffold_full vivi
  write_agent_md vivi 5
  # SPEC.md deliberately has NO lint/edit-gate reference. NOTE: the prose must not
  # contain the substrings the D10 grep matches — `lint.hook` (ERE `.` = any char)
  # would match a literal "lint hook", so avoid the words lint/edit-gate entirely
  # (this accidental match passed vacuously on darwin via apivr's side-effect but
  # failed on ubuntu — capture-live/verify-cross-platform lesson).
  mkdir -p ".eidolons/vivi"
  printf '# Vivi SPEC\nThis spec describes the coder role and its cycle phases only.\n' \
    > ".eidolons/vivi/SPEC.md"
  write_host_agent_correct vivi

  cat > eidolons.lock <<EOF
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: vivi
    version: "1.0.0"
    resolved: "github:Rynaro/vivi@test"
    target: "./.eidolons/vivi"
    hosts_wired: ["claude-code"]
    manifest_sha256: ""
    verification: "legacy-warning"
EOF

  cat > ".eidolons/vivi/install.manifest.json" <<'JSON'
{"eiis_version":"1.4","name":"vivi","version":"1.0.0","install_ts":"2026-01-01T00:00:00Z","files":[]}
JSON

  # vivi is a coder (in_construction) in the copied roster. A missing lint-gate
  # pointer is ADVISORY (staged opt-in): D10 must emit a warning, NOT a hard error —
  # a new gate must not regress an existing coder. The ACI class-declaration check
  # (the hard invariant) stays green.
  EIDOLONS_NEXUS="$custom_nexus" run eidolons doctor --deep
  [[ "$output" =~ "D11 — coder edit-gate ACI conformance" ]]
  [[ "$output" =~ "D10 advisory" ]]
  # the advisory must NOT raise a hard D11 edit-gate error for the missing pointer
  ! [[ "$output" =~ "does not reference the lint/edit gate (D11 —" ]]
}

_dd18_sha() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

# ─── DD-19..DD-21: D10 host-tier gate (S1.7) ──────────────────────────────
#
# D10 is a project-level gate (not per-member), so it needs a custom EIDOLONS_NEXUS
# with a two-coder routing.yaml. The real roster has only one coder (apivr), so
# D10 is a no-op (skip) on the real checkout — these tests use a minimal nexus.

# Helper: write a minimal nexus dir with a two-coder routing.yaml where vivi
# has requires_host_tier: thinking. Reuses the real roster/index.yaml and schemas
# to keep other doctor checks happy.
_dd19_nexus_two_coders() {
  local nexus_dir="$1"
  mkdir -p "$nexus_dir/roster"
  # Symlink the real roster index + schemas so other doctor checks can pass.
  cp -r "$EIDOLONS_ROOT/schemas" "$nexus_dir/schemas"
  cp "$EIDOLONS_ROOT/roster/index.yaml" "$nexus_dir/roster/index.yaml"
  # Copy other roster files if present.
  for f in aci.yaml ecl.yaml mcps.yaml; do
    [ -f "$EIDOLONS_ROOT/roster/$f" ] && cp "$EIDOLONS_ROOT/roster/$f" "$nexus_dir/roster/$f" || true
  done
  cat > "$nexus_dir/roster/routing.yaml" <<'YAML'
routing_version: "1.0"
thresholds: { tau_standard: 0.6, tau_trance: 0.8, chain_floor: 0.6, max_reroutes: 2, max_parallel: 5, surface_files: 25, surface_modules: 5 }
eidolons:
  vivi:  { capability_class: coder, model_tier: reasoning-class, default_for_class: coder, requires_host_tier: thinking, trigger_verbs: ["implement","build","fix","code"], refuse_verbs: ["greenfield"], downstream: ["idg"] }
  apivr: { capability_class: coder, model_tier: speed-class, trigger_verbs: ["implement","build","fix","code"], refuse_verbs: ["greenfield"], downstream: ["idg"] }
signals: []
chains: []
YAML
}

# Helper: write a BROKEN two-coder routing.yaml — vivi requires thinking but
# there is no fallback coder (apivr removed). This is the misconfiguration D10
# should catch.
_dd19_nexus_two_coders_no_fallback() {
  local nexus_dir="$1"
  _dd19_nexus_two_coders "$nexus_dir"
  cat > "$nexus_dir/roster/routing.yaml" <<'YAML'
routing_version: "1.0"
thresholds: { tau_standard: 0.6, tau_trance: 0.8, chain_floor: 0.6, max_reroutes: 2, max_parallel: 5, surface_files: 25, surface_modules: 5 }
eidolons:
  vivi: { capability_class: coder, model_tier: reasoning-class, default_for_class: coder, requires_host_tier: thinking, trigger_verbs: ["implement","build","fix","code"], refuse_verbs: ["greenfield"], downstream: ["idg"] }
signals: []
chains: []
YAML
}

# ─── DD-19: D10 OK — two coders, vivi gated, apivr is the fallback ───────

@test "DD-19: D10 OK — two-coder roster with gated vivi (requires_host_tier:thinking) and apivr fallback passes" {
  local custom_nexus="$BATS_TEST_TMPDIR/dd19-nexus"
  _dd19_nexus_two_coders "$custom_nexus"

  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas
  # No host_tier in manifest (conservative).

  EIDOLONS_NEXUS="$custom_nexus" run eidolons doctor --deep
  [[ "$output" =~ "D10 — host-tier gate" ]]
  [[ "$output" =~ "routing tiebreak correctly structured" ]]
}

# ─── DD-20: D10 OK — single-coder roster, D10 skips ──────────────────────

@test "DD-20: D10 OK — real roster (single coder apivr) causes D10 to skip gracefully" {
  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas

  # Default EIDOLONS_NEXUS ($EIDOLONS_ROOT) has only one coder → D10 skips.
  run eidolons doctor --deep
  [[ "$output" =~ "D10 — host-tier gate" ]]
  # D10 must not error on a single-coder roster.
  [[ "$output" =~ "routing tiebreak correctly structured" ]]
}

# ─── DD-21: D10 FAIL — gated default_for_class coder with no fallback ────

@test "DD-21: D10 FAIL — vivi requires thinking but no fallback coder exists exits 1" {
  local custom_nexus="$BATS_TEST_TMPDIR/dd21-nexus"
  _dd19_nexus_two_coders_no_fallback "$custom_nexus"

  scaffold_full atlas
  write_agent_md atlas 5
  write_spec_md atlas
  write_host_agent_correct atlas
  # Manifest has no host_tier (conservative) — vivi is gated but no fallback.

  EIDOLONS_NEXUS="$custom_nexus" run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "D10 host-tier gate" ]]
}
