#!/usr/bin/env bash
# tests/helpers.bash — shared fixtures for the atlas-aci bats suite.
#
# Destination in Rynaro/ATLAS: tests/helpers.bash
#
# Every test sources this file. The suite exercises the real
# commands/aci.sh by invoking it as a subprocess with:
#   - cwd = a fresh tmp "consumer project"
#   - PATH = a stubs dir first, then a curated allowlist
#   - $HOME / $XDG_CONFIG_HOME = fake dirs under $BATS_TEST_TMPDIR so T29
#     can assert nothing leaked outside cwd.
#
# Stubs record every invocation to $BATS_TEST_TMPDIR/<tool>.log so tests
# can assert call-count / args. Each stub honours an env var to inject a
# non-zero exit for failure-path tests.
#
# Bash 3.2 rules (P5): no associative arrays, no ${var,,}, no
# readarray/mapfile, no &>>. Mirror cli/tests/helpers.bash in the
# Rynaro/eidolons nexus for style.

# Absolute path to the ATLAS repo root (two levels up from this file).
ATLAS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ATLAS_ROOT

# Path to the script under test. In Rynaro/ATLAS this is commands/aci.sh.
ACI_SCRIPT="$ATLAS_ROOT/commands/aci.sh"
export ACI_SCRIPT

setup() {
  # Each test runs in its own pristine project dir.
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"

  # Fake HOME / XDG so T29 can assert nothing leaked outside cwd.
  FAKE_HOME="$BATS_TEST_TMPDIR/fakehome"
  FAKE_XDG="$BATS_TEST_TMPDIR/fakexdg"
  mkdir -p "$FAKE_HOME" "$FAKE_XDG"
  export HOME="$FAKE_HOME"
  export XDG_CONFIG_HOME="$FAKE_XDG"

  # Stubs dir — PATH is rewritten to put this first.
  STUBS_DIR="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS_DIR"

  # Curated PATH: stubs first, then a minimal allowlist of real tools
  # the host box provides but we do NOT want to stub (coreutils etc).
  # jq/yq/shellcheck tests use the real binaries since we test the
  # script's integration with them.
  _STUB_REAL_TOOLS_PATH="$(real_tools_path)"
  export PATH="$STUBS_DIR:$_STUB_REAL_TOOLS_PATH"
}

teardown() {
  cd "$ATLAS_ROOT"
}

# ─── Stub fabrication ────────────────────────────────────────────────────

# real_tools_path — echoes a PATH made of the directories containing
# real coreutils + jq + yq + bash + awk + sed + python3. We assemble this
# from `command -v <tool>` against the host's real PATH so the stub dir
# can shadow things without losing access to essentials.
real_tools_path() {
  # Snapshot the test process's inbound PATH before we rewrite it.
  # (bats inherits the host PATH; BATS_ORIGINAL_PATH may be set in some
  # bats versions — fall back to PATH.)
  local snapshot="${BATS_ORIGINAL_PATH:-$PATH}"
  echo "$snapshot"
}

# install_stub NAME EXIT_CODE [BODY]
#   Creates an executable at $STUBS_DIR/NAME that:
#     - appends one line to $BATS_TEST_TMPDIR/NAME.log per invocation,
#       formatted "<timestamp-ish> <all-args>"
#     - optionally runs BODY (a snippet evaluated in the stub's shell —
#       lets individual tests shape output)
#     - exits with EXIT_CODE (or whatever $STUB_NAME_EXIT overrides to
#       at call time, uppercased).
install_stub() {
  local name="$1" exit_code="$2" body="${3:-}"
  local upper_env
  # Bash 3.2 cannot do ${var^^}. Upper-case via tr.
  upper_env="STUB_$(echo "$name" | tr '[:lower:]-' '[:upper:]_')_EXIT"
  local logfile="$BATS_TEST_TMPDIR/${name}.log"
  local stub_path="$STUBS_DIR/$name"
  cat > "$stub_path" <<EOF
#!/usr/bin/env bash
# Auto-generated stub for \`$name\` — do not edit in place.
printf '%s\n' "\$*" >> "$logfile"
${body}
_override="\${${upper_env}:-}"
if [ -n "\$_override" ]; then exit "\$_override"; fi
exit ${exit_code}
EOF
  chmod +x "$stub_path"
  : > "$logfile"
}

# uninstall_stub NAME — removes a stub so `command -v NAME` fails.
uninstall_stub() {
  rm -f "$STUBS_DIR/$1"
}

# setup_stubs — install the default happy-path stubs every install test
# relies on. Individual tests can override by reinstalling a stub or
# setting STUB_<NAME>_EXIT at the @test level.
setup_stubs() {
  install_stub "uv" 0
  install_stub "rg" 0
  install_stub "python3" 0 'case "$1" in
  --version) echo "Python 3.11.7"; exit 0 ;;
esac'
  install_stub "atlas-aci" 0 'case "$1" in
  index) shift; mkdir -p ./.atlas && printf "generated: true\n" > ./.atlas/manifest.yaml ;;
  *) : ;;
esac'
  # jq and yq are genuine dependencies of the script logic — we let the
  # host box supply them via the PATH tail. If a test needs to stub them
  # (e.g. to force a parse failure), it can call install_stub "jq" 1
  # explicitly.
}

# stub_log_count NAME — echoes the number of times the stub was invoked.
stub_log_count() {
  local logfile="$BATS_TEST_TMPDIR/${1}.log"
  if [ -f "$logfile" ]; then
    wc -l < "$logfile" | tr -d ' '
  else
    echo 0
  fi
}

# ─── Fixture builders ────────────────────────────────────────────────────

# setup_fresh_project — seed the atlas install manifest so the §4.3 guard
# passes, then return. Caller cd's into $TEST_PROJECT (setup did that).
setup_fresh_project() {
  mkdir -p ./.eidolons/atlas
  cat > ./.eidolons/atlas/install.manifest.json <<'EOF'
{
  "name": "atlas",
  "version": "1.0.0",
  "hosts_wired": ["claude-code"],
  "files": []
}
EOF
}

# seed_claude_host — create the marker that detect_hosts_mcp picks up
# for the claude-code host (either CLAUDE.md or .claude/).
seed_claude_host() {
  mkdir -p .claude
  : > CLAUDE.md
}

# seed_cursor_host — marker for cursor host detection.
seed_cursor_host() {
  mkdir -p .cursor
}

# seed_copilot_host_with_agent — marker for copilot host plus one agent
# file containing a non-trivial YAML frontmatter and a markdown body.
seed_copilot_host_with_agent() {
  mkdir -p .github/agents
  cat > .github/agents/example.agent.md <<'EOF'
---
name: example
description: a test agent
tools:
  shell: true
---
# Example agent

This is the markdown body. It must survive byte-for-byte through
install and remove per T15.

- bullet one
- bullet two
EOF
}

# seed_copilot_host_empty — .github/ present but no .github/agents/.
# Triggers T14.
seed_copilot_host_empty() {
  mkdir -p .github
}

# seed_mcp_json_with_peer FILE — write a valid .mcp.json / .cursor/mcp.json
# with a pre-existing mcpServers.other-server entry so T9 / T10 can
# assert byte-level preservation.
seed_mcp_json_with_peer() {
  local target="$1"
  local dir
  dir="$(dirname "$target")"
  mkdir -p "$dir"
  cat > "$target" <<'EOF'
{
  "mcpServers": {
    "other-server": {
      "command": "node",
      "args": ["./other-server.js"],
      "env": {
        "OTHER_TOKEN": "keep-me"
      }
    }
  }
}
EOF
}

# seed_copilot_agent_with_peer — agent file whose frontmatter already has
# a peer MCP server entry. T9c / T10c preserve it.
seed_copilot_agent_with_peer() {
  mkdir -p .github/agents
  cat > .github/agents/example.agent.md <<'EOF'
---
name: example
description: peer test
tools:
  mcp_servers:
    - name: other-server
      transport: stdio
      command: ["node", "./other-server.js"]
---
# Peer preservation body

Body content under T9c / T10c.
EOF
}

# ─── Assertions ──────────────────────────────────────────────────────────

assert_mcp_json_contains() {
  local target="$1" key="$2"
  run jq -e --arg k "$key" '.mcpServers[$k] // empty' "$target"
  [ "$status" -eq 0 ] || {
    echo "expected mcpServers.$key in $target; got:"
    cat "$target"
    return 1
  }
}

assert_mcp_json_missing() {
  local target="$1" key="$2"
  run jq -e --arg k "$key" '.mcpServers[$k] // empty' "$target"
  [ "$status" -ne 0 ] || {
    echo "did not expect mcpServers.$key in $target; got:"
    cat "$target"
    return 1
  }
}

# assert_peer_preserved FILE — confirms mcpServers.other-server matches
# the original seeded shape byte-for-byte (after jq -S normalisation).
assert_peer_preserved() {
  local target="$1"
  local actual
  actual="$(jq -S '.mcpServers["other-server"]' "$target")"
  [ "$actual" = "$(cat <<'EOF' | jq -S .
{
  "command": "node",
  "args": ["./other-server.js"],
  "env": {"OTHER_TOKEN": "keep-me"}
}
EOF
)" ] || {
    echo "peer mcpServers.other-server was disturbed in $target:"
    echo "$actual"
    return 1
  }
}

assert_agent_md_body_preserved() {
  local target="$1" expected_body="$2"
  local actual_body
  # Extract body: everything after the second '---' line.
  actual_body="$(awk '
    /^---$/ { c++; if (c == 2) { capture = 1; next } }
    capture { print }
  ' "$target")"
  [ "$actual_body" = "$expected_body" ] || {
    echo "agent body was disturbed in $target"
    echo "--- expected"
    printf "%s\n" "$expected_body"
    echo "--- actual"
    printf "%s\n" "$actual_body"
    return 1
  }
}

# assert_agent_md_has_atlas_aci FILE — confirms tools.mcp_servers[] has a
# name: atlas-aci entry.
assert_agent_md_has_atlas_aci() {
  local target="$1"
  local fm
  fm="$(awk 'NR>1 && /^---$/ { exit } NR>1 { print }' "$target")"
  run bash -c "printf '%s' '$fm' | yq eval '.tools.mcp_servers[] | select(.name == \"atlas-aci\")' -"
  [ "$status" -eq 0 ] && [ -n "$output" ] || {
    echo "agent $target lacks tools.mcp_servers[name=atlas-aci]:"
    cat "$target"
    return 1
  }
}

# normalise_json FILE — echoes the jq -S (sorted-keys) rendering so
# idempotency tests can cmp across runs without false-failing on key
# order noise.
normalise_json() {
  jq -S . "$1"
}

# snapshot_mtimes DIR — echoes "<path>\t<mtime>" lines for every file
# under DIR. Used by T25 to prove --dry-run touched nothing.
snapshot_mtimes() {
  find "$1" -type f -print0 2>/dev/null \
    | xargs -0 stat -f '%N %m' 2>/dev/null \
    || find "$1" -type f -print0 2>/dev/null \
       | xargs -0 stat -c '%n %Y' 2>/dev/null
}

# run_aci ARGS... — invoke the script under test from the current
# project cwd. Bats captures $output and $status.
run_aci() {
  run bash "$ACI_SCRIPT" "$@"
}
