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

_dd18_sha() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}
