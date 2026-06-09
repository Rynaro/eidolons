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
# junction is wiring_mode: transport (registered in .mcp.json only; never
# injected into any agent's tools: allowlist — keystone T3).
seed_mcps_catalogue() {
  local nexus_override="${1:-$EIDOLONS_ROOT}"
  mkdir -p "$nexus_override/roster"
  cat > "$nexus_override/roster/mcps.yaml" <<'EOF'
catalogue_version: "1.2"
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
    wiring_mode: transport
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
catalogue_version: "1.2"
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
      - ".mcp.json"
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

# ─── W1.x — junction is transport-only: no agent-file injection (T7-G1) ──────
#
# KEYSTONE: junction has wiring_mode: transport. mcp_wiring_apply_for_mcp
# junction MUST produce zero agent-file targets and write nothing to any agent
# file. mcp__junction__* must never appear in any tools: line.
# Tests W1.1-W1.3 were formerly positive-injection assertions; they are now
# non-injection assertions per spec T3 / SPEC-2026-06-01-AGENT-TOOLS-JUNCTION-BUS.

@test "W1.1: junction is transport-only — mcp_wiring_apply_for_mcp junction does NOT inject mcp__junction__* into atlas.md (T7-G1)" {
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
  # KEYSTONE: junction is transport-only. atlas.md MUST NOT have mcp__junction__*.
  ! grep -q 'mcp__junction__' .claude/agents/atlas.md
  # Original tools: line must be preserved unchanged.
  grep -q 'tools: Read, Grep, Glob' .claude/agents/atlas.md
}

@test "W1.2: junction is transport-only — forge.md stays 'tools: none' after apply_for_mcp junction (T7-G1)" {
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
  # KEYSTONE: forge.md MUST stay tools: none. Junction is transport-only.
  grep -q '^tools: none$' .claude/agents/forge.md
  # No junction injection anywhere.
  ! grep -q 'mcp__junction__' .claude/agents/forge.md
  ! grep -q 'mcp__junction__' .claude/agents/atlas.md
}

@test "W1.3: junction is transport-only — no x-eidolons-mcp-wired:junction sentinel written (T7-G1)" {
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
  # KEYSTONE: no sentinel written for junction in either agent file.
  ! grep -q 'x-eidolons-mcp-wired:.*junction' .claude/agents/atlas.md
  ! grep -q 'x-eidolons-mcp-wired:.*junction' .claude/agents/forge.md
}

@test "W1.4: mcp install atlas-aci DOES patch .claude/agents/atlas.md (allowlist MCP — T3 AC4)" {
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
  # atlas.md SHOULD be patched with atlas-aci (allowlist MCP, not transport).
  grep -q 'mcp__atlas_aci__\*' .claude/agents/atlas.md
  # forge.md should be unchanged (scoped grant: only atlas).
  diff .claude/agents/forge.md.before .claude/agents/forge.md
  # No junction injection.
  ! grep -q 'mcp__junction__' .claude/agents/atlas.md
}

@test "W1.5: junction apply_for_mcp is a no-op — agent files byte-stable before and after (T7-G1 idempotency)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock

  # Snapshot before.
  cp .claude/agents/atlas.md .claude/agents/atlas.md.before
  cp .claude/agents/forge.md .claude/agents/forge.md.before

  # First run.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  # Files must be byte-identical to the snapshot (transport-only = no write).
  diff .claude/agents/atlas.md.before .claude/agents/atlas.md
  diff .claude/agents/forge.md.before .claude/agents/forge.md

  # Second run — same assertion.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  diff .claude/agents/atlas.md.before .claude/agents/atlas.md
  diff .claude/agents/forge.md.before .claude/agents/forge.md
}

@test "W1.6: junction apply_for_mcp 3x in a row — 0 diffs after run 1 (transport no-op G-IDEMP-2)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock

  # Snapshot before any run.
  cp .claude/agents/atlas.md .claude/agents/atlas.md.snap
  cp .claude/agents/forge.md .claude/agents/forge.md.snap

  # Run 1.
  bash -c "$(_source_wiring_libs); mcp_wiring_apply_for_mcp junction" 2>/dev/null
  diff .claude/agents/atlas.md.snap .claude/agents/atlas.md
  diff .claude/agents/forge.md.snap .claude/agents/forge.md

  # Run 2.
  bash -c "$(_source_wiring_libs); mcp_wiring_apply_for_mcp junction" 2>/dev/null
  diff .claude/agents/atlas.md.snap .claude/agents/atlas.md
  diff .claude/agents/forge.md.snap .claude/agents/forge.md

  # Run 3.
  bash -c "$(_source_wiring_libs); mcp_wiring_apply_for_mcp junction" 2>/dev/null
  diff .claude/agents/atlas.md.snap .claude/agents/atlas.md
  diff .claude/agents/forge.md.snap .claude/agents/forge.md
}

# ─── W2.x — mcp uninstall is a no-op for agent files (junction never injected) ──

@test "W2.1: mcp uninstall junction — atlas.md unchanged because junction never injected (G-REV-1)" {
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

  # Apply (no-op — transport-only).
  bash -c "$(_source_wiring_libs); mcp_wiring_apply_for_mcp junction" 2>/dev/null

  # Unapply.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_unapply_for_mcp junction
  "
  [ "$status" -eq 0 ]

  # atlas.md must equal original (was never touched by apply or unapply).
  diff .claude/agents/atlas.md.original .claude/agents/atlas.md
}

@test "W2.2: mcp uninstall junction — forge stays tools: none (never replaced by junction)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent_none "forge"
  seed_junction_lock

  # Apply (no-op — transport-only).
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

  # forge.md must still be tools: none (was never modified by transport-mode junction).
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

  # Apply + update lock (no-op write — transport-only).
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

# ─── W3.x — eidolons sync re-wires (atlas-aci as the allowlist MCP) ──────────

@test "W3.1: mcp_wiring_reapply_all re-wires atlas-aci after per-Eidolon installer rewrite (S4 simulation)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"

  # Seed a lockfile with atlas-aci (the allowlist MCP) so reapply_all picks it up.
  cat > eidolons.mcp.lock <<EOF
# eidolons.mcp.lock
generated_at: "2026-05-25T00:00:00Z"
eidolons_cli_version: "1.4.0"
catalogue_version: "1.2"
mcps:
  - name: atlas-aci
    kind: oci-image
    version: "0.2.2"
    source:
      repo: "Rynaro/atlas-aci"
    integrity:
      algo: none
      value: ""
    target: ""
    hosts_wired:
      - ".claude/agents/atlas.md"
      - ".mcp.json"
    installed_at: "2026-05-25T00:00:00Z"
EOF

  # Wire atlas-aci (the genuine allowlist MCP) — first application.
  bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp atlas-aci
  " 2>/dev/null

  # Simulate per-Eidolon installer rewrite (like atlas@1.x/install.sh does).
  seed_claude_agent "atlas"

  # At this point atlas.md is back to baseline (no sentinel).
  ! grep -q 'x-eidolons-mcp-wired' .claude/agents/atlas.md

  # Now reapply_all.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_reapply_all
  "
  [ "$status" -eq 0 ]

  # atlas.md should be wired again with atlas-aci (it's in the lockfile).
  grep -q 'mcp__atlas_aci__\*' .claude/agents/atlas.md
  grep -q 'x-eidolons-mcp-wired:.*atlas-aci' .claude/agents/atlas.md
  # junction must never appear in agent files.
  ! grep -q 'mcp__junction__' .claude/agents/atlas.md
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

@test "W4.1: vigil agent — junction NOT wired after reapply_all (transport-only MCP stays out of agent files)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"

  # Start with atlas + forge.
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock  # junction in lockfile but transport-only

  # Now add vigil: add to manifest + create its agent file (simulating eidolons add vigil + sync).
  cat >> eidolons.yaml <<'ADDEOF'
  - name: vigil
    version: "^1.0.0"
    source: github:Rynaro/VIGIL
ADDEOF
  seed_claude_agent "vigil" "Read, Grep"

  # Snapshot vigil.md before reapply.
  cp .claude/agents/vigil.md .claude/agents/vigil.md.before

  # Run reapply_all (what sync does).
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_reapply_all
  "
  [ "$status" -eq 0 ]

  # vigil.md MUST NOT contain junction (junction is transport-only).
  ! grep -q 'mcp__junction__' .claude/agents/vigil.md
  # atlas.md MUST NOT contain junction.
  ! grep -q 'mcp__junction__' .claude/agents/atlas.md
  # forge.md must still be tools: none (junction never replaces it).
  grep -q '^tools: none$' .claude/agents/forge.md
}

# ─── W5.x — manifest opt-out ─────────────────────────────────────────────────

@test "W5.1: manifest mcp_wiring.exclude.atlas-aci: [forge] keeps forge unwired from atlas-aci" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"

  # Write manifest with exclusion on atlas-aci for forge.
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
    atlas-aci: [forge]
EOF

  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp atlas-aci
  "
  [ "$status" -eq 0 ]

  # atlas.md should be wired with atlas-aci.
  grep -q 'mcp__atlas_aci__\*' .claude/agents/atlas.md

  # forge.md must NOT be wired (excluded, and atlas-aci only grants to [atlas] anyway).
  ! grep -q 'mcp__atlas_aci__\*' .claude/agents/forge.md

  # No junction injection anywhere.
  ! grep -q 'mcp__junction__' .claude/agents/atlas.md
  ! grep -q 'mcp__junction__' .claude/agents/forge.md
}

# ─── W6.x — codex hosts ──────────────────────────────────────────────────────

@test "W6.1: codex hosts.wire patches .codex/agents/atlas.md with atlas-aci (allowlist MCP, case d)" {
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
    mcp_wiring_apply_for_mcp atlas-aci
  "
  [ "$status" -eq 0 ]

  # claude-code agent patched with atlas-aci.
  grep -q 'mcp__atlas_aci__\*' .claude/agents/atlas.md
  # codex agent patched with atlas-aci as block-sequence item.
  grep -q 'mcp__atlas_aci__\*' .codex/agents/atlas.md
  grep -q 'x-eidolons-mcp-wired:.*atlas-aci' .codex/agents/atlas.md

  # No junction in any agent file.
  ! grep -q 'mcp__junction__' .claude/agents/atlas.md
  ! grep -q 'mcp__junction__' .codex/agents/atlas.md
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

  # No junction injection (transport-only for junction; cursor is also info-only).
  [ ! -d ".claude/agents" ] || ! grep -rq 'mcp__junction__' .claude/agents/ 2>/dev/null
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

  # No junction injection.
  [ ! -d ".claude/agents" ] || ! grep -rq 'mcp__junction__' .claude/agents/ 2>/dev/null
}

# ─── W8.x — strict-hosts non-interaction ─────────────────────────────────────

@test "W8.1: --strict-hosts: atlas-aci wiring lands in .claude/agents/ and does NOT touch .eidolons/" {
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
    mcp_wiring_apply_for_mcp atlas-aci
  "
  [ "$status" -eq 0 ]

  # Wiring landed in .claude/agents/ with atlas-aci.
  grep -q 'mcp__atlas_aci__\*' .claude/agents/atlas.md

  # .eidolons/ was NOT touched.
  [ "$(cat .eidolons/atlas/sentinel.txt)" = "original" ]

  # No junction in agent files.
  ! grep -q 'mcp__junction__' .claude/agents/atlas.md
}

# ─── W9.x — soft failure ─────────────────────────────────────────────────────

@test "W9.1: read-only .claude/agents/atlas.md → atlas-aci wiring warns + continues (no abort)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent_none "forge"
  seed_junction_lock

  # Make atlas.md read-only.
  chmod 444 .claude/agents/atlas.md

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp atlas-aci
  "
  # Must NOT fail.
  [ "$status" -eq 0 ]

  # Restore permissions.
  chmod 644 .claude/agents/atlas.md
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

  # Wire atlas-aci and update lockfile.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp atlas-aci
    _mcp_wiring_update_lockfile_add atlas-aci .claude/agents/atlas.md
  "
  [ "$status" -eq 0 ]

  # lockfile should now include .claude/agents/atlas.md for atlas-aci.
  grep -q '\.claude/agents/atlas\.md' eidolons.mcp.lock || true

  # Unwire atlas-aci and update lockfile.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_unapply_for_mcp atlas-aci
  "
  [ "$status" -eq 0 ]
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

  # Call the low-level patch directly (bypasses transport gate in apply_for_mcp).
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_patch_agent_file claude-code .claude/agents/atlas.md atlas-aci mcp__atlas_aci__*
  "
  [ "$status" -eq 0 ]

  # tools: line should now exist and contain the glob.
  grep -q '^tools: mcp__atlas_aci__\*' .claude/agents/atlas.md
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

  # Wire atlas-aci first via low-level patch (bypasses transport gate).
  bash -c "
    $(_source_wiring_libs)
    mcp_wiring_patch_agent_file claude-code .claude/agents/atlas.md atlas-aci mcp__atlas_aci__*
  " 2>/dev/null

  # Wire a second hypothetical MCP directly via low-level patch.
  bash -c "
    $(_source_wiring_libs)
    mcp_wiring_patch_agent_file claude-code .claude/agents/atlas.md crystalium mcp__crystalium__*
  " 2>/dev/null

  # sentinel should be sorted: atlas-aci before crystalium.
  local sentinel_line
  sentinel_line="$(grep 'x-eidolons-mcp-wired:' .claude/agents/atlas.md)"
  echo "$sentinel_line" | grep -q 'atlas-aci'
  echo "$sentinel_line" | grep -q 'crystalium'
  # Verify order: atlas-aci position < crystalium position.
  aci_pos="$(echo "$sentinel_line" | grep -bo 'atlas-aci' | head -1 | cut -d: -f1)"
  cry_pos="$(echo "$sentinel_line" | grep -bo 'crystalium' | head -1 | cut -d: -f1)"
  [ "$aci_pos" -lt "$cry_pos" ]
}

@test "T7-G1: atlas.md contains no mcp__junction__ token after full apply_for_mcp cycle" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas" "Read, Grep, Glob"
  seed_claude_agent_none "forge"
  seed_junction_lock

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
    mcp_wiring_reapply_all
  "
  [ "$status" -eq 0 ]

  # KEYSTONE: no junction tools in any agent file.
  ! grep -q 'mcp__junction__' .claude/agents/atlas.md
  ! grep -q 'mcp__junction__' .claude/agents/forge.md
}

# ─── Fixture: mcps catalogue that includes crystalium (allowlist/direct) ─────
#
# crystalium has grants_to_eidolons: all and NO wiring_mode field (so it
# defaults to allowlist/direct). Contrast with junction which has
# wiring_mode: transport and is therefore never injected into agent files.

seed_mcps_catalogue_with_crystalium() {
  local nexus_override="${1:-$EIDOLONS_ROOT}"
  mkdir -p "$nexus_override/roster"
  cat > "$nexus_override/roster/mcps.yaml" <<'EOF'
catalogue_version: "1.2"
updated_at: "2026-06-01T00:00:00Z"
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
    wiring_mode: transport
    exposes_tools:
      glob: "mcp__junction__*"
      list:
        - mcp__junction__harness_run
        - mcp__junction__harness_verify
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

  - name: crystalium
    display_name: "CRYSTALIUM"
    scope: system
    kind: oci-image
    description: "Portable memory harness — four-layer crystal lattice."
    use_cases:
      - "Cross-session memory recall."
    related_eidolons: []
    grants_to_eidolons: all
    exposes_tools:
      glob: "mcp__crystalium__*"
      list:
        - mcp__crystalium__recall
        - mcp__crystalium__commit
        - mcp__crystalium__ingest
        - mcp__crystalium__update
        - mcp__crystalium__skill_invoke
        - mcp__crystalium__plan_checkpoint
        - mcp__crystalium__plan_replan
        - mcp__crystalium__session_end
    source:
      type: ghcr
      image: "ghcr.io/rynaro/crystalium"
    versions:
      latest: "1.2.0"
      pins:
        stable: "1.2.0"
      releases:
        "1.2.0":
          digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
          released_at: "2026-06-01T00:00:00Z"
    install:
      hosts_wired:
        - ".mcp.json"
      template: "cli/templates/mcp/crystalium.mcp.json.tmpl"
    health:
      probes:
        - docker_cli
EOF
}

# ─── W11.x — crystalium is allowlist/direct: injected into all agent files ───
#
# KEYSTONE: crystalium has grants_to_eidolons: all and no wiring_mode field
# (defaults to allowlist/direct). mcp_wiring_apply_for_mcp crystalium MUST
# inject mcp__crystalium__* into every eligible Eidolon's tools: line.
# This is the OPPOSITE of the junction transport tests (W1.1-W1.3).

@test "W11.1: crystalium is allowlist/direct — mcp_wiring_apply_for_mcp crystalium DOES inject mcp__crystalium__* into atlas.md" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue_with_crystalium "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas" "Read, Grep, Glob"
  seed_claude_agent_none "forge"

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp crystalium
  "
  [ "$status" -eq 0 ]
  # KEYSTONE: crystalium is allowlist/direct — atlas.md MUST have mcp__crystalium__*.
  grep -q 'mcp__crystalium__\*' .claude/agents/atlas.md
  # sentinel must record crystalium wiring.
  grep -q 'x-eidolons-mcp-wired:.*crystalium' .claude/agents/atlas.md
}

@test "W11.2: crystalium is allowlist/direct — mcp__crystalium__* injected into all eligible agent files (grants_to_eidolons: all)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue_with_crystalium "$EIDOLONS_NEXUS"

  # Manifest with three agents.
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.5.0"
    source: github:Rynaro/ATLAS
  - name: spectra
    version: "^4.0.0"
    source: github:Rynaro/SPECTRA
  - name: apivr
    version: "^3.0.0"
    source: github:Rynaro/APIVR-Delta
EOF

  seed_claude_agent "atlas" "Read, Grep, Glob"
  seed_claude_agent "spectra" "Read, Grep"
  seed_claude_agent "apivr" "Read, Edit, Write"

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp crystalium
  "
  [ "$status" -eq 0 ]
  # All three agent files MUST have crystalium injected (grants_to_eidolons: all).
  grep -q 'mcp__crystalium__\*' .claude/agents/atlas.md
  grep -q 'mcp__crystalium__\*' .claude/agents/spectra.md
  grep -q 'mcp__crystalium__\*' .claude/agents/apivr.md
  # No junction injection anywhere (junction is still transport-only).
  ! grep -q 'mcp__junction__' .claude/agents/atlas.md
  ! grep -q 'mcp__junction__' .claude/agents/spectra.md
  ! grep -q 'mcp__junction__' .claude/agents/apivr.md
}

@test "W11.3: crystalium wiring is idempotent — second apply_for_mcp crystalium produces no diff (G-IDEMP)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue_with_crystalium "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas" "Read, Grep, Glob"

  # First apply.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp crystalium
  "
  [ "$status" -eq 0 ]
  cp .claude/agents/atlas.md .claude/agents/atlas.md.snap

  # Second apply — must produce byte-identical output.
  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp crystalium
  "
  [ "$status" -eq 0 ]
  diff .claude/agents/atlas.md.snap .claude/agents/atlas.md
}

# ─── W12.x — zero-wire warning for allowlist MCP with no agent files present ─
#
# When an allowlist MCP (e.g. crystalium) is wired before any Eidolon agent
# files exist on disk, mcp_wiring_apply_for_mcp must emit a warning on stderr
# rather than silently succeeding. Transport MCPs (e.g. junction) must NOT emit
# this warning because their zero-target result is correct by design.

@test "W12.1: allowlist MCP with no agent files emits 'wired 0 agent files' warning" {
  # Seed nexus with crystalium catalogue entry (allowlist, grants_to_eidolons: all).
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue_with_crystalium "$EIDOLONS_NEXUS"

  # Manifest present (wiring reads it for host/member lists) but NO agent files.
  seed_manifest_claude

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp crystalium
  " 2>&1
  [ "$status" -eq 0 ]
  # Warning must appear on stderr (bats merges stdout+stderr into $output here).
  [[ "$output" =~ "wired 0 agent files" ]]
  [[ "$output" =~ "eidolons mcp install crystalium --force" ]]
}

@test "W12.2: transport MCP (junction) does NOT emit 'wired 0 agent files' warning even with no agent files" {
  # Junction is wiring_mode: transport. Zero targets is expected — no warning.
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue "$EIDOLONS_NEXUS"

  # Manifest present but NO agent files (same scenario as W12.1).
  seed_manifest_claude

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp junction
  " 2>&1
  [ "$status" -eq 0 ]
  # Transport MCP must NOT warn about zero agent files.
  [[ ! "$output" =~ "wired 0 agent files" ]]
}

# ─── A1.1 — atlas-aci grant to [atlas, vivi] (S1.1) ──────────────────────────
#
# These tests use a LOCAL catalogue fixture (seed_mcps_catalogue_with_vivi) rather
# than mutating the shared seed_mcps_catalogue, which many sibling tests depend
# on for [atlas]-only semantics. This keeps the existing W1.4/W1.5/W1.6 tests
# passing unchanged while covering the new [atlas, vivi] grant.

# Local fixture: atlas-aci with grants_to_eidolons: [atlas, vivi].
seed_mcps_catalogue_with_vivi() {
  local nexus_override="${1:-$EIDOLONS_ROOT}"
  mkdir -p "$nexus_override/roster"
  cat > "$nexus_override/roster/mcps.yaml" <<'EOF'
catalogue_version: "1.2"
updated_at: "2026-06-05T00:00:00Z"
mcps:
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
      - vivi
    exposes_tools:
      glob: "mcp__atlas_aci__*"
      list:
        - mcp__atlas_aci__view_file
        - mcp__atlas_aci__search_symbol
    source:
      type: ghcr
      image: "ghcr.io/rynaro/atlas-aci"
    versions:
      latest: "0.2.3"
      pins:
        stable: "0.2.3"
      releases:
        "0.2.3":
          digest: "sha256:86f82c454d21378ba99ce7ef92494c34ad533e82bc76e6ea7affa4a8056326b3"
          released_at: "2026-06-02T00:00:00Z"
    install:
      hosts_wired:
        - ".mcp.json"
      template: "cli/templates/mcp/atlas-aci.mcp.json.tmpl"
    health:
      probes:
        - docker_cli
EOF
}

@test "A1.1a: atlas-aci grant [atlas,vivi] — vivi.md installed → gains mcp__atlas_aci__* glob" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue_with_vivi "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent "vivi" "Read, Edit, Write"

  # Save vivi.md before to verify it changed.
  cp .claude/agents/vivi.md .claude/agents/vivi.md.before

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp atlas-aci
  "
  [ "$status" -eq 0 ]
  # vivi.md MUST be patched with the atlas-aci glob (grant includes vivi).
  grep -q 'mcp__atlas_aci__\*' .claude/agents/vivi.md
  # atlas.md MUST also be patched (still in the grant list).
  grep -q 'mcp__atlas_aci__\*' .claude/agents/atlas.md
}

@test "A1.1b: atlas-aci grant [atlas,vivi] — vivi.md ABSENT → clean no-op (soft-fail GAP 7)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue_with_vivi "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  # vivi.md is deliberately NOT created.

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp atlas-aci
  "
  # Must succeed (no error) even though vivi.md is absent.
  [ "$status" -eq 0 ]
  # vivi.md must NOT have been created.
  [ ! -f ".claude/agents/vivi.md" ]
  # atlas.md still gets the glob (it IS installed).
  grep -q 'mcp__atlas_aci__\*' .claude/agents/atlas.md
}

@test "A1.1c: atlas-aci grant [atlas,vivi] — apivr.md present → receives NO atlas-aci glob (G3)" {
  export EIDOLONS_NEXUS="$BATS_TEST_TMPDIR/nexus"
  mkdir -p "$EIDOLONS_NEXUS"
  cp -r "$EIDOLONS_ROOT/cli" "$EIDOLONS_NEXUS/cli"
  cp -r "$EIDOLONS_ROOT/schemas" "$EIDOLONS_NEXUS/schemas"
  seed_mcps_catalogue_with_vivi "$EIDOLONS_NEXUS"
  seed_manifest_claude
  seed_claude_agent "atlas"
  seed_claude_agent "apivr" "Read, Edit, Write"

  # Save apivr.md before.
  cp .claude/agents/apivr.md .claude/agents/apivr.md.before

  run bash -c "
    $(_source_wiring_libs)
    mcp_wiring_apply_for_mcp atlas-aci
  "
  [ "$status" -eq 0 ]
  # apivr.md MUST NOT receive atlas-aci glob (not in the grant list).
  ! grep -q 'mcp__atlas_aci__' .claude/agents/apivr.md
  # apivr.md must be byte-identical to before.
  diff .claude/agents/apivr.md.before .claude/agents/apivr.md
  # atlas.md still gets the glob.
  grep -q 'mcp__atlas_aci__\*' .claude/agents/atlas.md
}
