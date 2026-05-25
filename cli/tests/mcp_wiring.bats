#!/usr/bin/env bats
#
# cli/tests/mcp_wiring.bats — coverage for MCP-to-Eidolon tool-surface wiring.
#
# Tests W1.1–W10.1 per spec §14 validation gates.
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.
#
# Key patterns:
#   - All tests use BATS_TEST_TMPDIR for isolation.
#   - Agent files are created from scratch in setup helpers.
#   - lib_mcp_wiring.sh is sourced directly for unit testing.
#   - Full CLI path tested for lifecycle-hook integration.

load helpers

FAKE_JUNCTION_VERSION="0.2.0"

# ─── Fixtures ────────────────────────────────────────────────────────────────

# Seed a minimal mcps.yaml with grants_to_eidolons fields.
seed_mcps_catalogue() {
  local nexus_override="${1:-$EIDOLONS_ROOT}"
  mkdir -p "$nexus_override/roster"
  cat > "$nexus_override/roster/mcps.yaml" <<'EOF'
catalogue_version: "1.1"
updated_at: "2026-05-25T00:00:00Z"
mcps:
  - name: junction
    display_name: "Junction"
    scope: system
    kind: binary
    description: "Container-isolated agent harness."
    use_cases:
      - "Sandbox APIVR-Delta implementation work."
    related_eidolons: []
    grants_to_eidolons: all
    exposes_tools:
      glob: "mcp__junction__*"
      list:
        - mcp__junction__harness_run
        - mcp__junction__harness_verify
        - mcp__junction__plan_dispatch
        - mcp__junction__reasoning_step
    source:
      type: github_release
      repo: "Rynaro/Junction"
      install_url: "https://example.com/junction/install.sh"
    versions:
      latest: "0.2.0"
      pins:
        stable: "0.2.0"
      releases:
        "0.2.0":
          archive_sha256: ""
          released_at: "2026-05-19T00:00:00Z"
    install:
      cache_path: "$EIDOLONS_HOME/cache/junction@<version>/"
      marker: ".eidolons/harness/manifest.json"
    health:
      probes:
        - binary_present
        - binary_version
        - docker_daemon_optional

  - name: atlas-aci
    display_name: "Atlas-ACI"
    scope: system
    kind: oci-image
    description: "Stdio MCP server exposing structural codebase intelligence."
    use_cases:
      - "Cross-language symbol search."
    related_eidolons: [atlas]
    grants_to_eidolons:
      - atlas
    exposes_tools:
      glob: "mcp__atlas_aci__*"
      list:
        - mcp__atlas_aci__view_file
        - mcp__atlas_aci__search_symbol
    source:
      type: ghcr
      image: "ghcr.io/rynaro/atlas-aci"
    versions:
      latest: "0.2.2"
      pins:
        stable: "0.2.2"
      releases:
        "0.2.2":
          digest: "sha256:386677f06b0ce23cb4883f6c0f91d8eac22328cd7d9451ae241e2f183207ad96"
          released_at: "2026-04-30T00:00:00Z"
    install:
      hosts_wired:
        - ".mcp.json"
      template: "cli/templates/mcp/atlas-aci.mcp.json.tmpl"
    health:
      probes:
        - docker_cli
EOF
}

# Seed a claude-code agent file for eidolon NAME with tools CSV.
seed_claude_agent() {
  local name="$1"
  local tools="${2:-Read, Grep, Glob}"
  mkdir -p ".claude/agents"
  cat > ".claude/agents/${name}.md" <<EOF
---
name: ${name}
description: Test agent for ${name}.
when_to_use: Testing.
tools: ${tools}
methodology: TEST
methodology_version: "1.0"
role: Tester
handoffs: []
---

# ${name} agent body.
EOF
}

# Seed a claude-code agent file with tools: none (FORGE pattern).
seed_claude_agent_none() {
  local name="${1:-forge}"
  mkdir -p ".claude/agents"
  cat > ".claude/agents/${name}.md" <<EOF
---
name: ${name}
description: Reasoner agent.
tools: none
methodology: FORGE
methodology_version: "1.0"
role: Reasoner
handoffs: []
---

# ${name} body.
EOF
}

# Seed a claude-code agent file with NO tools: line (safety-net stub pattern).
seed_claude_agent_no_tools() {
  local name="${1:-stub}"
  mkdir -p ".claude/agents"
  cat > ".claude/agents/${name}.md" <<EOF
---
name: ${name}
description: Safety-net stub.
---

# ${name} stub body.
EOF
}

# Seed a codex agent file with tools as a YAML block sequence.
seed_codex_agent() {
  local name="$1"
  mkdir -p ".codex/agents"
  cat > ".codex/agents/${name}.md" <<EOF
---
name: ${name}
description: Codex agent for ${name}.
tools:
  - Read
  - Grep
model: gpt-5
---

# ${name} codex body.
EOF
}

# Seed a minimal eidolons.yaml with hosts.wire = [claude-code].
seed_manifest_claude() {
  cat > eidolons.yaml <<EOF
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.5.0"
    source: github:Rynaro/ATLAS
  - name: forge
    version: "^1.3.0"
    source: github:Rynaro/FORGE
EOF
}

# Seed a minimal eidolons.yaml with hosts.wire = [claude-code, codex].
seed_manifest_claude_codex() {
  cat > eidolons.yaml <<EOF
version: 1
hosts:
  wire: [claude-code, codex]
members:
  - name: atlas
    version: "^1.5.0"
    source: github:Rynaro/ATLAS
EOF
}

# Seed a cursor-only manifest.
seed_manifest_cursor() {
  cat > eidolons.yaml <<EOF
version: 1
hosts:
  wire: [cursor]
members:
  - name: atlas
    version: "^1.5.0"
    source: github:Rynaro/ATLAS
EOF
}

# Seed an opencode-only manifest.
seed_manifest_opencode() {
  cat > eidolons.yaml <<EOF
version: 1
hosts:
  wire: [opencode]
members:
  - name: atlas
    version: "^1.5.0"
    source: github:Rynaro/ATLAS
EOF
}

# Seed a manifest with mcp_wiring.exclude.
seed_manifest_with_exclude() {
  local mcp_name="$1"
  shift
  # remaining args are eidolon names to exclude
  cat > eidolons.yaml <<EOF
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.5.0"
    source: github:Rynaro/ATLAS
  - name: forge
    version: "^1.3.0"
    source: github:Rynaro/FORGE
mcp_wiring:
  exclude:
    ${mcp_name}: [$(printf '%s' "$@" | tr ' ' ', ')]
EOF
}

# Seed a minimal junction lockfile entry.
seed_junction_lock() {
  local ver="${1:-$FAKE_JUNCTION_VERSION}"
  local cache_dir="$EIDOLONS_HOME/cache/junction@${ver}"
  mkdir -p "$cache_dir"
  cat > "$cache_dir/junction" <<'JSTUB'
#!/usr/bin/env bash
echo "stub"
JSTUB
  chmod +x "$cache_dir/junction"

  cat > eidolons.mcp.lock <<EOF
# eidolons.mcp.lock
generated_at: "2026-05-25T00:00:00Z"
eidolons_cli_version: "1.4.0"
catalogue_version: "1.1"
mcps:
  - name: junction
    kind: binary
    version: "${ver}"
    source:
      repo: "Rynaro/Junction"
    integrity:
      algo: none
      value: ""
    target: "${cache_dir}/junction"
    hosts_wired:
      - ".eidolons/harness/manifest.json"
    installed_at: "2026-05-25T00:00:00Z"
EOF
}

# Source the wiring library in a subshell-friendly way.
# Returns a script fragment that loads lib.sh + lib_mcp.sh + lib_mcp_wiring.sh.
# Uses the already-exported EIDOLONS_NEXUS (set by each test before calling this).
# EIDOLONS_HOME is already exported by setup() in helpers.bash.
_source_wiring_libs() {
  echo ". '$EIDOLONS_ROOT/cli/src/lib.sh'; . '$EIDOLONS_ROOT/cli/src/lib_mcp.sh'; . '$EIDOLONS_ROOT/cli/src/lib_mcp_wiring.sh'"
}

# ─── W1.x — mcp install junction wires agent files ───────────────────────────

@test "W1.1: mcp install junction patches .claude/agents/atlas.md (case a — CSV append)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas" "Read, Grep, Glob"
  seed_claude_agent_none "forge"

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  [ "$status" -eq 0 ]
  # Check that atlas.md has mcp__junction__* appended.
  grep -q 'mcp__junction__\*' .claude/agents/atlas.md
  # Verify it's an append, not a replace.
  grep -q 'Read, Grep, Glob' .claude/agents/atlas.md
}

@test "W1.2: mcp install junction patches .claude/agents/forge.md (case b — none replacement)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  [ "$status" -eq 0 ]
  # forge.md should have tools: mcp__junction__* (replacement of none)
  grep -q 'tools: mcp__junction__\*' .claude/agents/forge.md
  # Should NOT contain "none" anymore in the tools line.
  ! grep '^tools:' .claude/agents/forge.md | grep -q 'none'
}

@test "W1.3: mcp install junction writes x-eidolons-mcp-wired: [junction] sentinel" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  [ "$status" -eq 0 ]
  grep -q 'x-eidolons-mcp-wired:.*junction' .claude/agents/atlas.md
  grep -q 'x-eidolons-mcp-wired:.*junction' .claude/agents/forge.md
}

@test "W1.4: mcp install atlas-aci does NOT touch .claude/agents/forge.md (scoped grant)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"

  # Save forge.md before.
  cp .claude/agents/forge.md .claude/agents/forge.md.before

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp atlas-aci
  "
  [ "$status" -eq 0 ]
  # atlas.md should be patched with atlas-aci.
  grep -q 'mcp__atlas_aci__\*' .claude/agents/atlas.md
  # forge.md should be unchanged.
  diff .claude/agents/forge.md.before .claude/agents/forge.md
}

@test "W1.5: mcp install is byte-stable on second run (G-IDEMP-1)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock

  # First run.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  # Capture state after first run.
  cp .claude/agents/atlas.md .claude/agents/atlas.md.after1
  cp .claude/agents/forge.md .claude/agents/forge.md.after1

  # Second run.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  # Files must be byte-identical.
  diff .claude/agents/atlas.md.after1 .claude/agents/atlas.md
  diff .claude/agents/forge.md.after1 .claude/agents/forge.md
}

@test "W1.6: mcp install 3x in a row — 0 diffs after run 2 (G-IDEMP-2)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock

  # Run 1.
  bash -c "$(_source_wiring_libs); mcp_wiring_apply_for_mcp junction" 2>/dev/null
  # Snapshot after run 1.
  cp .claude/agents/atlas.md .claude/agents/atlas.md.snap
  cp .claude/agents/forge.md .claude/agents/forge.md.snap

  # Run 2.
  bash -c "$(_source_wiring_libs); mcp_wiring_apply_for_mcp junction" 2>/dev/null
  diff .claude/agents/atlas.md.snap .claude/agents/atlas.md
  diff .claude/agents/forge.md.snap .claude/agents/forge.md

  # Run 3.
  bash -c "$(_source_wiring_libs); mcp_wiring_apply_for_mcp junction" 2>/dev/null
  diff .claude/agents/atlas.md.snap .claude/agents/atlas.md
  diff .claude/agents/forge.md.snap .claude/agents/forge.md
}

# ─── W2.x — mcp uninstall reverses patches ───────────────────────────────────

@test "W2.1: mcp uninstall junction reverts .claude/agents/atlas.md to pre-install byte state (G-REV-1)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas" "Read, Grep, Glob"
  seed_junction_lock

  # Save original.
  cp .claude/agents/atlas.md .claude/agents/atlas.md.original

  # Wire.
  bash -c "$(_source_wiring_libs); mcp_wiring_apply_for_mcp junction" 2>/dev/null

  # Verify wired.
  grep -q 'mcp__junction__\*' .claude/agents/atlas.md

  # Unwire.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_unapply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  # File should be byte-identical to original.
  diff .claude/agents/atlas.md.original .claude/agents/atlas.md
}

@test "W2.2: mcp uninstall junction reverts .claude/agents/forge.md to tools: none" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent_none "forge"

  # Add forge to the lockfile's hosts_wired so unapply works.
  seed_junction_lock
  # Update lock to include forge.
  bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
    _mcp_wiring_update_lockfile_add junction .claude/agents/forge.md
  " 2>/dev/null

  # Unwire.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_unapply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  # forge.md should be back to tools: none.
  grep -q '^tools: none$' .claude/agents/forge.md
}

@test "W2.3: mcp uninstall is a no-op on second run (already gone)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_junction_lock

  # Wire + update lock.
  bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
    _mcp_wiring_update_lockfile_add junction .claude/agents/atlas.md
  " 2>/dev/null

  # First uninstall.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_unapply_for_mcp junction
  "
  [ "$status" -eq 0 ]
  cp .claude/agents/atlas.md .claude/agents/atlas.md.after1

  # Second uninstall — should be no-op.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_unapply_for_mcp junction
  "
  [ "$status" -eq 0 ]
  diff .claude/agents/atlas.md.after1 .claude/agents/atlas.md
}

# ─── W3.x — eidolons sync re-wires ───────────────────────────────────────────

@test "W3.1: mcp_wiring_reapply_all re-wires after per-Eidolon installer rewrite (S4 simulation)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent_none "forge"
  seed_junction_lock

  # Wire forge.
  bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
    _mcp_wiring_update_lockfile_add junction .claude/agents/forge.md
  " 2>/dev/null

  # Simulate per-Eidolon installer rewrite (like forge@1.3.3/install.sh does).
  seed_claude_agent_none "forge"

  # At this point forge.md is back to tools: none (no sentinel).
  ! grep -q 'x-eidolons-mcp-wired' .claude/agents/forge.md

  # Now reapply_all.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_reapply_all
  "
  [ "$status" -eq 0 ]

  # forge.md should be wired again.
  grep -q 'mcp__junction__\*' .claude/agents/forge.md
  grep -q 'x-eidolons-mcp-wired:.*junction' .claude/agents/forge.md
}

@test "W3.2: mcp_wiring_reapply_all is byte-stable on second run (S4)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock

  # Wire.
  bash -c "
    $(_source_wiring_libs)
    mcp_wiring_reapply_all
  " 2>/dev/null

  cp .claude/agents/atlas.md .claude/agents/atlas.md.snap
  cp .claude/agents/forge.md .claude/agents/forge.md.snap

  # Reapply again — must be byte-stable.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_reapply_all
  "
  [ "$status" -eq 0 ]
  diff .claude/agents/atlas.md.snap .claude/agents/atlas.md
  diff .claude/agents/forge.md.snap .claude/agents/forge.md
}

# ─── W4.x — eidolons add vigil ───────────────────────────────────────────────

@test "W4.1: vigil agent gets wired after reapply_all when junction is installed (S5)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"

  # Start with atlas + forge.
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock

  bash -c "
    $(_source_wiring_libs)
    mcp_wiring_reapply_all
    _mcp_wiring_update_lockfile_add junction .claude/agents/atlas.md
    _mcp_wiring_update_lockfile_add junction .claude/agents/forge.md
  " 2>/dev/null

  # Now add vigil: add to manifest + create its agent file (simulating eidolons add vigil + sync).
  cat >> eidolons.yaml <<'ADDEOF'
  - name: vigil
    version: "^1.0.0"
    source: github:Rynaro/VIGIL
ADDEOF
  seed_claude_agent "vigil" "Read, Grep"

  # Run reapply_all (what sync does).
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_reapply_all
  "
  [ "$status" -eq 0 ]

  # vigil.md should now be wired.
  grep -q 'mcp__junction__\*' .claude/agents/vigil.md
  grep -q 'x-eidolons-mcp-wired:.*junction' .claude/agents/vigil.md

  # Previously-wired Eidolons stay wired.
  grep -q 'x-eidolons-mcp-wired:.*junction' .claude/agents/atlas.md
  grep -q 'x-eidolons-mcp-wired:.*junction' .claude/agents/forge.md
}

# ─── W5.x — manifest opt-out ─────────────────────────────────────────────────

@test "W5.1: manifest mcp_wiring.exclude.junction: [forge] keeps forge unwired" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"

  # Write manifest with exclusion.
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.5.0"
    source: github:Rynaro/ATLAS
  - name: forge
    version: "^1.3.0"
    source: github:Rynaro/FORGE
mcp_wiring:
  exclude:
    junction: [forge]
EOF

  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  # atlas.md should be wired.
  grep -q 'mcp__junction__\*' .claude/agents/atlas.md

  # forge.md must NOT be wired.
  ! grep -q 'mcp__junction__\*' .claude/agents/forge.md
  ! grep -q 'x-eidolons-mcp-wired' .claude/agents/forge.md
}

# ─── W6.x — codex hosts ──────────────────────────────────────────────────────

@test "W6.1: codex hosts.wire patches .codex/agents/atlas.md block sequence (case d)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude_codex
  seed_claude_agent "atlas"
  seed_codex_agent "atlas"
  seed_junction_lock

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  # claude-code agent patched.
  grep -q 'mcp__junction__\*' .claude/agents/atlas.md
  # codex agent patched as block-sequence item.
  grep -q 'mcp__junction__\*' .codex/agents/atlas.md
  grep -q 'x-eidolons-mcp-wired:.*junction' .codex/agents/atlas.md
}

# ─── W7.x — cursor / opencode no-ops ─────────────────────────────────────────

@test "W7.1: cursor-only project: NO files patched; info line emitted (S8)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_cursor

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  " 2>&1
  [ "$status" -eq 0 ]

  # No agent files created.
  [ ! -d ".claude/agents" ] || [ -z "$(ls -A .claude/agents 2>/dev/null)" ]
  [ ! -d ".codex/agents" ] || [ -z "$(ls -A .codex/agents 2>/dev/null)" ]

  # Info line about cursor should appear in output.
  [[ "$output" == *"cursor"* ]]
}

@test "W7.2: opencode-only project: NO files patched; deferred info line emitted (S9)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_opencode

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  " 2>&1
  [ "$status" -eq 0 ]

  # No agent files created.
  [ ! -d ".claude/agents" ] || [ -z "$(ls -A .claude/agents 2>/dev/null)" ]

  # Info line about opencode / FU1 should appear in output.
  [[ "$output" == *"opencode"* ]] || [[ "$output" == *"FU1"* ]]
}

# ─── W8.x — strict-hosts non-interaction ─────────────────────────────────────

@test "W8.1: --strict-hosts: wiring lands in .claude/agents/ and does NOT touch .eidolons/" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_junction_lock

  # Create a fake .eidolons/atlas dir to ensure it's not touched.
  mkdir -p ".eidolons/atlas"
  echo "original" > ".eidolons/atlas/sentinel.txt"

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  # Wiring landed in .claude/agents/.
  grep -q 'mcp__junction__\*' .claude/agents/atlas.md

  # .eidolons/ was NOT touched.
  [ "$(cat .eidolons/atlas/sentinel.txt)" = "original" ]
}

# ─── W9.x — soft failure ─────────────────────────────────────────────────────

@test "W9.1: read-only .claude/agents/forge.md → warn + continue (no abort)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock

  # Make forge.md read-only.
  chmod 444 .claude/agents/forge.md

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  # Must NOT fail.
  [ "$status" -eq 0 ]

  # atlas.md should still be patched.
  grep -q 'mcp__junction__\*' .claude/agents/atlas.md

  # Restore permissions.
  chmod 644 .claude/agents/forge.md
}

# ─── W10.x — lockfile grows and shrinks ──────────────────────────────────────

@test "W10.1: eidolons.mcp.lock hosts_wired[] grows on wire and shrinks on unwire (S1+S3)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas" "Read, Grep"
  seed_junction_lock

  # Wire and update lockfile.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
    _mcp_wiring_update_lockfile_add junction .claude/agents/atlas.md
  "
  [ "$status" -eq 0 ]

  # lockfile should now include .claude/agents/atlas.md.
  grep -q '\.claude/agents/atlas\.md' eidolons.mcp.lock

  # Unwire and update lockfile.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_unapply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  # lockfile should no longer include .claude/agents/atlas.md.
  ! grep -q '\.claude/agents/atlas\.md' eidolons.mcp.lock
}

# ─── Additional unit tests for lib internals ─────────────────────────────────

@test "lib: strategy (c) insert — no tools: line in safety-net stub gets tools: inserted" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude

  # Use safety-net stub (no tools: line).
  seed_claude_agent_no_tools "stub"
  # Rename to atlas so manifest_members finds it.
  mv .claude/agents/stub.md .claude/agents/atlas.md
  # Fix the name field.
  sed -i.bak 's/^name: stub/name: atlas/' .claude/agents/atlas.md
  rm -f .claude/agents/atlas.md.bak

  seed_junction_lock

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_patch_agent_file claude-code .claude/agents/atlas.md junction mcp__junction__*
  "
  [ "$status" -eq 0 ]

  # tools: line should now exist and contain the glob.
  grep -q '^tools: mcp__junction__\*' .claude/agents/atlas.md
}

@test "lib: sentinel sorted alphabetically when two MCPs are wired" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_junction_lock

  # Wire junction first (comes after atlas-aci alphabetically).
  bash -c "
    $(_source_wiring_libs)
    mcp_wiring_patch_agent_file claude-code .claude/agents/atlas.md junction mcp__junction__*
  " 2>/dev/null

  # Wire atlas-aci second.
  bash -c "
    $(_source_wiring_libs)
    mcp_wiring_patch_agent_file claude-code .claude/agents/atlas.md atlas-aci mcp__atlas_aci__*
  " 2>/dev/null

  # sentinel should be sorted: atlas-aci before junction.
  local sentinel_line
  sentinel_line="$(grep 'x-eidolons-mcp-wired:' .claude/agents/atlas.md)"
  # atlas-aci should appear before junction in the sentinel.
  echo "$sentinel_line" | grep -q 'atlas-aci'
  echo "$sentinel_line" | grep -q 'junction'
  # Verify order: atlas-aci position < junction position.
  aci_pos="$(echo "$sentinel_line" | grep -bo 'atlas-aci' | head -1 | cut -d: -f1)"
  junc_pos="$(echo "$sentinel_line" | grep -bo 'junction' | head -1 | cut -d: -f1)"
  [ "$aci_pos" -lt "$junc_pos" ]
}
