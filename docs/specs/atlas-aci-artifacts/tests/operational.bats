#!/usr/bin/env bats
# tests/operational.bats — T25, T26, T27, T28, T29 from §5.2.
#
# Operational guarantees: dry-run touches nothing, no-host-detected
# path, bash 3.2 shebang sanity, stderr-only logging, and the Layer-2
# write boundary (no writes outside cwd).

load helpers

# ─── T25 ─────────────────────────────────────────────────────────────────

# Anchors: Spec §5.2 T25 (--dry-run writes nothing, emits CREATE|MODIFY|INDEX)
@test "T25: --dry-run creates no files and emits CREATE/INDEX on stdout" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  # Snapshot mtimes of the pre-run tree.
  local before
  before="$(snapshot_mtimes "$TEST_PROJECT")"

  run_aci --install --host claude-code --dry-run --non-interactive
  [ "$status" -eq 0 ]
  # Stdout must list one CREATE or MODIFY or INDEX line per affected path.
  [[ "$output" == *"CREATE "*".mcp.json"* ]] || [[ "$output" == *"MODIFY "*".mcp.json"* ]]
  [[ "$output" == *"INDEX "* ]]

  # No new files and no mtime changes.
  [ ! -f .mcp.json ]
  [ ! -f .cursor/mcp.json ]
  [ ! -d .atlas ]
  local after
  after="$(snapshot_mtimes "$TEST_PROJECT")"
  [ "$before" = "$after" ]

  # atlas-aci index MUST NOT be invoked on dry-run.
  local count
  count="$(stub_log_count atlas-aci)"
  [ "$count" = "0" ]
}

# ─── T26 ─────────────────────────────────────────────────────────────────

# Anchors: Spec §5.2 T26 (no host + no --host → exit 4)
@test "T26: no detectable host + no --host → exit 4" {
  setup_fresh_project
  setup_stubs
  # No seed_*_host calls → cwd has no host markers.

  run_aci --install --non-interactive
  [ "$status" -eq 4 ]
  [[ "$output" == *"No MCP-capable host"* ]] || [[ "$output" == *"no MCP-capable host"* ]]
}

# ─── T27 ─────────────────────────────────────────────────────────────────

# Anchors: Spec §5.2 T27 (bash 3.2 / P5 — shebang sanity)
# The ATLAS-repo CI job MUST run this suite under /bin/bash on
# macos-latest to cover true bash 3.2 behaviour. Shellcheck under
# `-s bash` covers the syntactic half. This @test merely asserts the
# script's shebang is `#!/usr/bin/env bash` and not pinned to a newer
# runtime — see §5.2 T27 and follow-up F2 if a feature probe becomes
# necessary.
@test "T27: commands/aci.sh shebang is #!/usr/bin/env bash" {
  local shebang
  shebang="$(head -n 1 "$ACI_SCRIPT")"
  [ "$shebang" = "#!/usr/bin/env bash" ]
}

# ─── T28 ─────────────────────────────────────────────────────────────────

# Anchors: Spec §5.2 T28 (stdout empty on --install success; stderr has log)
@test "T28: --install success writes only to stderr (stdout is empty)" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  # bats' `run` collapses stderr+stdout into $output. Split them.
  local stdout_file="$BATS_TEST_TMPDIR/aci.stdout"
  local stderr_file="$BATS_TEST_TMPDIR/aci.stderr"
  bash "$ACI_SCRIPT" --install --host claude-code --non-interactive \
    > "$stdout_file" 2> "$stderr_file"
  local rc=$?
  [ "$rc" -eq 0 ]
  # Stdout MUST be empty on --install success.
  [ ! -s "$stdout_file" ]
  # Stderr MUST contain progress log markers.
  run grep -E '▸|✓|·' "$stderr_file"
  [ "$status" -eq 0 ]
}

# ─── T29 ─────────────────────────────────────────────────────────────────

# Anchors: Spec §5.2 T29 (writes never escape cwd — P4 / D3)
# Best-effort check: run under fake HOME / XDG_CONFIG_HOME and verify
# no files were created in either after install+remove. A stricter
# check with `strace -e trace=openat` (Linux) / `dtruss` (macOS) is
# logged as a follow-up because it requires platform-specific wiring
# beyond what bats can portably do.
@test "T29: install + remove produces zero writes under \$HOME or \$XDG_CONFIG_HOME" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  # Snapshot counts (fake dirs are empty from setup()).
  local home_before xdg_before
  home_before="$(find "$FAKE_HOME" -type f 2>/dev/null | wc -l | tr -d ' ')"
  xdg_before="$(find "$FAKE_XDG" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$home_before" = "0" ]
  [ "$xdg_before"  = "0" ]

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  run_aci --remove --host claude-code --non-interactive
  [ "$status" -eq 0 ]

  local home_after xdg_after
  home_after="$(find "$FAKE_HOME" -type f 2>/dev/null | wc -l | tr -d ' ')"
  xdg_after="$(find "$FAKE_XDG"  -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$home_after" = "0" ] || {
    echo "Unexpected files under \$HOME ($FAKE_HOME):"
    find "$FAKE_HOME" -type f
    return 1
  }
  [ "$xdg_after" = "0" ] || {
    echo "Unexpected files under \$XDG_CONFIG_HOME ($FAKE_XDG):"
    find "$FAKE_XDG" -type f
    return 1
  }
}
